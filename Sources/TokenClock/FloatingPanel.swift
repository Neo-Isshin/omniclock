import AppKit

/// 自定义浮动面板：无标题栏、始终置顶、可拖拽
final class FloatingPanel: NSPanel {
    /// 面板宽 / 高由用户选择的表盘大小（ClockSize）派生，读取 UserDefaults，随设置实时变化。
    static var panelWidth: CGFloat { currentClockSize.panelWidth }
    static var detailPanelWidth: CGFloat { currentClockSize.detailPanelWidth }
    static var collapsedHeight: CGFloat { currentClockSize.diameter }
    static let resizeGripHeight: CGFloat = 18
    static let detailHorizontalInset: CGFloat = 8
    static var clockHeight: CGFloat { currentClockSize.diameter }
    static let dropdownVerticalMargin: CGFloat = 10
    static let forecastHeight: CGFloat = 76
    /// Three control rows plus the table header. Keep this in sync with
    /// DetailDropdownView so an empty tool list never clips the launchers.
    static let headerHeight: CGFloat = 147
    static let toolRowHeight: CGFloat = 37

    /// 当前表盘大小（缺省 / 越界回退 medium）。
    private static var currentClockSize: ClockSize {
        if let raw = UserDefaults.standard.string(for: .clockSize),
           let size = ClockSize(rawValue: raw) {
            return size
        }
        return .medium
    }

    init(viewModel: ViewModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setupWindow(viewModel: viewModel)
    }

    private func setupWindow(viewModel: ViewModel) {
        // 窗口级别：默认 normal（不置顶），不进入全屏 Space
        self.level = .normal

        // 无标题栏，背景透明
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        // 不拦截其他应用的激活事件
        self.becomesKeyOnlyIfNeeded = true
        // 普通窗口默认：collectionBehavior 置空（不 join 任何 Space）→ 不进入全屏 Space，
        // 原生全屏播放器可覆盖。alwaysOnTop 开启时由 AppDelegate 覆写为
        // [.canJoinAllSpaces, .fullScreenAuxiliary]（跨桌面 + 全屏置顶）。
        self.collectionBehavior = []

        // 默认位置
        if let screen = NSScreen.main {
            let pos = ViewModel.loadWindowPosition(
                screenFrame: screen.visibleFrame,
                panelSize: NSSize(width: Self.panelWidth, height: Self.collapsedHeight)
            )
            let frameOrigin = NSPoint(x: pos.x, y: pos.y)
            self.setFrameOrigin(frameOrigin)
        }
    }

    // 点击背景可拖拽，不激活
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // 右键菜单：直接在 panel 层拦截，用屏幕坐标定位
    override func rightMouseDown(with event: NSEvent) {
        self.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// 表盘窗口保持当前档位尺寸；展开内容由独立详情面板承载。
    /// 尺寸变化时保持视觉中心（midX）与顶部（maxY）不变，表盘不会"跳位"。
    func updateSize(expanded: Bool, activeToolCount: Int = 0, showsWeather: Bool = false) {
        let midX = frame.midX
        let topY = frame.maxY
        let width = Self.panelWidth
        let height = Self.collapsedHeight
        setFrame(
            NSRect(x: midX - width / 2, y: topY - height, width: width, height: height),
            display: true
        )
    }

    /// 保存窗口位置
    func savePosition() {
        ViewModel.saveWindowPosition(self.frame.origin)
    }
}

final class DropdownPanel: NSPanel, NSWindowDelegate {
    private var resizeStartHeight: CGFloat = 0
    private var resizeTopY: CGFloat = 0
    private var minPanelHeight: CGFloat = 0
    private var maxPanelHeight: CGFloat = 0
    private var preferredPanelHeight: CGFloat?
    private var preferredPanelWidth: CGFloat?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: FloatingPanel.detailPanelWidth, height: FloatingPanel.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = []
        delegate = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if PanelResizeEdgesView.route(event, in: self) { return }
        super.sendEvent(event)
    }

    func configureLevel(alwaysOnTop: Bool) {
        if alwaysOnTop {
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            level = .normal
            collectionBehavior = []   // 普通窗口：不进全屏 Space，全屏播放器可覆盖
        }
    }

    func requiredHeight(activeToolCount: Int, showsWeather: Bool) -> CGFloat {
        let contentHeight = (showsWeather ? FloatingPanel.forecastHeight : 0)
            + FloatingPanel.headerHeight
            + CGFloat(activeToolCount) * FloatingPanel.toolRowHeight
            + FloatingPanel.resizeGripHeight
            + FloatingPanel.dropdownVerticalMargin
        return max(120, contentHeight)
    }

    func show(below clockFrame: NSRect, activeToolCount: Int, showsWeather: Bool) {
        updateLimits(below: clockFrame, activeToolCount: activeToolCount, showsWeather: showsWeather)
        let targetHeight = min(max(preferredPanelHeight ?? minPanelHeight, minPanelHeight), maxPanelHeight)
        setFrame(frame(below: clockFrame, height: targetHeight), display: true)
        orderFront(nil)
    }

    func hide() {
        PanelResizeEdgesView.releaseCursor(in: self)
        orderOut(nil)
    }

    func reposition(below clockFrame: NSRect) {
        updateLimits(below: clockFrame)
        setFrame(frame(below: clockFrame, height: min(frame.height, maxPanelHeight)), display: true)
    }

    func beginResize() {
        resizeStartHeight = frame.height
        resizeTopY = frame.maxY
    }

    func updateResize(deltaY: CGFloat) {
        let requestedHeight = resizeStartHeight + deltaY
        let newHeight = min(max(requestedHeight, minPanelHeight), maxPanelHeight)
        preferredPanelHeight = newHeight
        setFrame(
            NSRect(x: frame.minX, y: resizeTopY - newHeight, width: frame.width, height: newHeight),
            display: true
        )
    }

    func endResize() {}

    func windowDidEndLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === self else { return }
        preferredPanelWidth = frame.width
        preferredPanelHeight = frame.height
    }

    /// 额度卡片通常比单个工具列表更高；首次打开时只向下扩展到舒适高度，
    /// 不覆盖用户已经调得更大的尺寸，也始终受当前屏幕可用空间限制。
    func ensureHeight(_ requestedHeight: CGFloat) {
        guard isVisible else { return }
        let targetHeight = min(max(frame.height, requestedHeight), maxPanelHeight)
        guard targetHeight > frame.height else { return }
        preferredPanelHeight = targetHeight
        setFrame(
            NSRect(
                x: frame.minX,
                y: frame.maxY - targetHeight,
                width: frame.width,
                height: targetHeight
            ),
            display: true
        )
    }

    private func updateLimits(
        below clockFrame: NSRect,
        activeToolCount: Int? = nil,
        showsWeather: Bool? = nil
    ) {
        if let activeToolCount, let showsWeather {
            minPanelHeight = requiredHeight(activeToolCount: activeToolCount, showsWeather: showsWeather)
        }
        let screenFrame = targetScreen(for: clockFrame)?.visibleFrame
        let availableHeight = max(80, clockFrame.minY - (screenFrame?.minY ?? 0))
        minPanelHeight = min(minPanelHeight, availableHeight)
        maxPanelHeight = availableHeight
        let availableWidth = max(1, (screenFrame?.width ?? FloatingPanel.detailPanelWidth) - 16)
        minSize = NSSize(width: min(FloatingPanel.detailPanelWidth, availableWidth), height: minPanelHeight)
        maxSize = NSSize(width: availableWidth, height: maxPanelHeight)
    }

    private func targetScreen(for clockFrame: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: clockFrame.midX, y: clockFrame.midY)) } ?? screen ?? NSScreen.main
    }

    private func frame(below clockFrame: NSRect, height: CGFloat) -> NSRect {
        let width = min(max(preferredPanelWidth ?? FloatingPanel.detailPanelWidth, minSize.width), maxSize.width)
        let visible = targetScreen(for: clockFrame)?.visibleFrame
        let centeredX = clockFrame.midX - width/2
        let x = visible.map { min(max(centeredX,$0.minX+8),$0.maxX-width-8) } ?? centeredX
        return NSRect(x: x, y: clockFrame.minY-height, width: width, height: height)
    }
}

final class NotificationPanel: NSPanel, NSWindowDelegate {
    private var preferredSize: NSSize?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        level = .normal
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = []
        delegate = self
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if PanelResizeEdgesView.route(event, in: self) { return }
        super.sendEvent(event)
    }

    func configureLevel(alwaysOnTop: Bool) {
        if alwaysOnTop {
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            level = .normal
            collectionBehavior = []
        }
    }

    func show(near clockFrame: NSRect) {
        let screenFrame = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: clockFrame.midX, y: clockFrame.midY)) } ?? screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:280,height:240)
        let available = screenFrame.insetBy(dx: 8, dy: 8)
        minSize = NSSize(width: min(280, max(1,available.width)), height: min(200, max(1,available.height)))
        maxSize = NSSize(width: max(minSize.width,available.width), height: max(minSize.height,available.height))
        let preferred = preferredSize ?? NSSize(width: 280, height: 240)
        let targetSize = NSSize(width: min(max(preferred.width,minSize.width),maxSize.width),
                                height: min(max(preferred.height,minSize.height),maxSize.height))
        let margin: CGFloat = 10
        var x = clockFrame.maxX - targetSize.width
        var y = clockFrame.minY - targetSize.height - margin
        if y < screenFrame.minY {
            y = clockFrame.maxY + margin
        }
        x = min(max(x, available.minX), available.maxX - targetSize.width)
        y = min(max(y, available.minY), available.maxY - targetSize.height)
        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: targetSize), display: true)
        orderFront(nil)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === self else { return }
        preferredSize = frame.size
    }

    func hide() {
        PanelResizeEdgesView.releaseCursor(in: self)
        orderOut(nil)
    }
}


// MARK: - Edge resizing for the borderless detail and notification panels

enum PanelResizeEdge: CaseIterable {
    case left, right, bottom, top, bottomLeft, bottomRight, topLeft, topRight
    var adjustsLeft: Bool { [.left, .bottomLeft, .topLeft].contains(self) }
    var adjustsRight: Bool { [.right, .bottomRight, .topRight].contains(self) }
    var adjustsBottom: Bool { [.bottom, .bottomLeft, .bottomRight].contains(self) }
    var adjustsTop: Bool { [.top, .topLeft, .topRight].contains(self) }
    @MainActor var cursor: NSCursor {
        if #available(macOS 15.0, *) {
        let position: NSCursor.FrameResizePosition
        switch self {
        case .left: position = .left
        case .right: position = .right
        case .bottom: position = .bottom
        case .top: position = .top
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        }
        return .frameResize(position: position, directions: .all)
        }
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return Self.diagonalCursor(rising: self == .bottomLeft || self == .topRight)
        }
    }
}

private extension PanelResizeEdge {
    @MainActor static func diagonalCursor(rising: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            let points: [NSPoint] = rising ? [.init(x:3,y:3),.init(x:15,y:15)] : [.init(x:3,y:15),.init(x:15,y:3)]
            path.move(to:points[0]);path.line(to:points[1])
            for (p,dx,dy) in [(points[0],CGFloat(1),rising ? CGFloat(1):CGFloat(-1)),(points[1],CGFloat(-1),rising ? CGFloat(-1):CGFloat(1))] {
                path.move(to:NSPoint(x:p.x+5*dx,y:p.y));path.line(to:p);path.line(to:NSPoint(x:p.x,y:p.y+5*dy))
            }
            path.lineWidth=3.5;NSColor.windowBackgroundColor.setStroke();path.stroke()
            path.lineWidth=1.5;NSColor.labelColor.setStroke();path.stroke();return true
        }
        return NSCursor(image:image,hotSpot:NSPoint(x:9,y:9))
    }
}

struct PanelResizeGeometry {
    /// Include the detail panel's transparent margin so the visible border is draggable.
    /// Notification panels use zero inset. Interior buttons remain outside these bands.
    static func regions(in bounds: NSRect, horizontalInset: CGFloat = 0) -> [(edge: PanelResizeEdge, rect: NSRect)] {
        let verticalThickness = min(6, bounds.height / 2)
        let horizontalThickness = min(6 + max(0, horizontalInset), bounds.width / 2)
        let cornerWidth = min(max(12, horizontalThickness), bounds.width / 2)
        let cornerHeight = min(12, bounds.height / 2)
        guard verticalThickness > 0, horizontalThickness > 0 else { return [] }
        let x = bounds.minX, y = bounds.minY, right = bounds.maxX, top = bounds.maxY
        let regions: [(edge: PanelResizeEdge, rect: NSRect)] = [
            (.left, NSRect(x: x, y: y + cornerHeight, width: horizontalThickness, height: bounds.height - 2 * cornerHeight)),
            (.right, NSRect(x: right - horizontalThickness, y: y + cornerHeight, width: horizontalThickness, height: bounds.height - 2 * cornerHeight)),
            (.bottom, NSRect(x: x + cornerWidth, y: y, width: bounds.width - 2 * cornerWidth, height: verticalThickness)),
            (.top, NSRect(x: x + cornerWidth, y: top - verticalThickness, width: bounds.width - 2 * cornerWidth, height: verticalThickness)),
            (.bottomLeft, NSRect(x: x, y: y, width: cornerWidth, height: verticalThickness)),
            (.bottomLeft, NSRect(x: x, y: y + verticalThickness, width: horizontalThickness, height: cornerHeight - verticalThickness)),
            (.bottomRight, NSRect(x: right - cornerWidth, y: y, width: cornerWidth, height: verticalThickness)),
            (.bottomRight, NSRect(x: right - horizontalThickness, y: y + verticalThickness, width: horizontalThickness, height: cornerHeight - verticalThickness)),
            (.topLeft, NSRect(x: x, y: top - verticalThickness, width: cornerWidth, height: verticalThickness)),
            (.topLeft, NSRect(x: x, y: top - cornerHeight, width: horizontalThickness, height: cornerHeight - verticalThickness)),
            (.topRight, NSRect(x: right - cornerWidth, y: top - verticalThickness, width: cornerWidth, height: verticalThickness)),
            (.topRight, NSRect(x: right - horizontalThickness, y: top - cornerHeight, width: horizontalThickness, height: cornerHeight - verticalThickness)),
        ]
        return regions.filter { !$0.rect.isEmpty }
    }

    static func edge(at point: NSPoint, in bounds: NSRect, horizontalInset: CGFloat = 0) -> PanelResizeEdge? {
        regions(in: bounds, horizontalInset: horizontalInset).first { $0.rect.contains(point) }?.edge
    }

    static func resizedFrame(from original: NSRect, edge: PanelResizeEdge, delta: NSSize,
                             minimum: NSSize, maximum: NSSize, visibleFrame: NSRect?) -> NSRect {
        var result = original
        func clamp(_ length: CGFloat, minimum: CGFloat, maximum: CGFloat, available: CGFloat) -> CGFloat {
            let upper = max(0, min(maximum, available))
            return min(max(length, min(minimum, upper)), upper)
        }
        if edge.adjustsLeft {
            let width = clamp(original.width - delta.width, minimum: minimum.width, maximum: maximum.width,
                              available: visibleFrame.map { original.maxX - $0.minX } ?? maximum.width)
            result.origin.x = original.maxX - width; result.size.width = width
        } else if edge.adjustsRight {
            result.size.width = clamp(original.width + delta.width, minimum: minimum.width, maximum: maximum.width,
                                      available: visibleFrame.map { $0.maxX - original.minX } ?? maximum.width)
        }
        if edge.adjustsBottom {
            let height = clamp(original.height - delta.height, minimum: minimum.height, maximum: maximum.height,
                               available: visibleFrame.map { original.maxY - $0.minY } ?? maximum.height)
            result.origin.y = original.maxY - height; result.size.height = height
        } else if edge.adjustsTop {
            result.size.height = clamp(original.height + delta.height, minimum: minimum.height, maximum: maximum.height,
                                       available: visibleFrame.map { $0.maxY - original.minY } ?? maximum.height)
        }
        return result
    }
}

/// An invisible perimeter above the hosting view. Its center is click-through;
/// the standard container keeps SwiftUI's own hit testing out of edge tracking.
final class PanelResizeEdgesView: NSView {
    private struct Drag {
        let edge: PanelResizeEdge
        let mouse: NSPoint
        let frame: NSRect
        let minimum: NSSize
        let maximum: NSSize
        let visibleFrame: NSRect?
    }
    private var drag: Drag?
    private var edgeTrackingArea: NSTrackingArea?
    private var cursorTrackingAreas: [NSTrackingArea] = []
    private var hoveredEdge: PanelResizeEdge?
    private weak var cursorWindow: NSWindow?
    private var restoresCursorRects = false
    private var cursorRevision = 0
    private var cursorReapplyPending = false
    let horizontalInset: CGFloat

    init(frame: NSRect, horizontalInset: CGFloat = 0) {
        self.horizontalInset = horizontalInset
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func wrapping(_ content: NSView, horizontalInset: CGFloat = 0) -> NSView {
        PanelResizeContainerView(content: content, horizontalInset: horizontalInset)
    }

    @discardableResult static func install(on panel: NSPanel) -> PanelResizeEdgesView? {
        if let container = panel.contentView as? PanelResizeContainerView { return container.edges }
        guard let content = panel.contentView else { return nil }
        let container = PanelResizeContainerView(content: content, horizontalInset: panel is DropdownPanel ? FloatingPanel.detailHorizontalInset : 0)
        panel.contentView = container
        return container.edges
    }

    /// A resizable NSPanel may consume its outer frame before dispatching to NSView.
    /// Route just the border sequence here; interior controls keep normal window delivery.
    static func route(_ event: NSEvent, in panel: NSPanel) -> Bool {
        guard let container = panel.contentView as? PanelResizeContainerView else { return false }
        let edges = container.edges
        switch event.type {
        case .leftMouseDown:
            guard edges.hitTest(container.convert(event.locationInWindow, from: nil)) != nil else { return false }
            edges.mouseDown(with: event)
            return edges.drag != nil
        case .leftMouseDragged:
            guard edges.drag != nil else { return false }
            edges.mouseDragged(with: event)
            return true
        case .leftMouseUp:
            guard edges.drag != nil else { return false }
            edges.mouseUp(with: event)
            return true
        case .mouseMoved, .cursorUpdate:
            let point = edges.convert(event.locationInWindow, from: nil)
            let isEdge = PanelResizeGeometry.edge(at: point, in: edges.bounds, horizontalInset: edges.horizontalInset) != nil
            edges.updateCursor(for: event, force: true)
            return isEdge
        default: return false
        }
    }

    static func releaseCursor(in panel: NSPanel) {
        (panel.contentView as? PanelResizeContainerView)?.edges.releaseResizeCursor()
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        guard let source = notification.object as? NSWindow, source === window,
              notification.name == NSWindow.willCloseNotification || !source.isVisible else { return }
        releaseResizeCursor()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHiddenOrHasHiddenAncestor, super.hitTest(point) != nil,
              PanelResizeGeometry.edge(at: convert(point, from: superview), in: bounds, horizontalInset: horizontalInset) != nil else { return nil }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for region in PanelResizeGeometry.regions(in: bounds, horizontalInset: horizontalInset) { addCursorRect(region.rect, cursor: region.edge.cursor) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let edgeTrackingArea { removeTrackingArea(edgeTrackingArea) }
        for area in cursorTrackingAreas { removeTrackingArea(area) }
        // AppKit explicitly does not deliver cursorUpdate with activeAlways.
        // Keep inactive hover delivery separate from the native cursor-update regions.
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        edgeTrackingArea = area
        cursorTrackingAreas = PanelResizeGeometry.regions(in: bounds, horizontalInset: horizontalInset).map {
            NSTrackingArea(rect: $0.rect, options: [.cursorUpdate, .activeInActiveApp], owner: self, userInfo: nil)
        }
        for area in cursorTrackingAreas { addTrackingArea(area) }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    private func updateCursor(for event: NSEvent, force: Bool = false) {
        let edge = drag?.edge ?? PanelResizeGeometry.edge(at: convert(event.locationInWindow, from: nil),
            in: bounds, horizontalInset: horizontalInset)
        guard let edge else { releaseResizeCursor(); return }
        guard let window, window.isVisible else { return }
        if cursorWindow == nil {
            cursorWindow = window
            restoresCursorRects = window.areCursorRectsEnabled
            if restoresCursorRects { window.disableCursorRects() }
        }
        let changed = edge != hoveredEdge
        hoveredEdge = edge
        if changed || force { edge.cursor.set() }
        // NSHostingView can reset the cursor later in the same event dispatch.
        // Reapply once at its end, only while this visible border still owns it.
        guard !cursorReapplyPending else { return }
        cursorReapplyPending = true
        let revision = cursorRevision
        DispatchQueue.main.async { [weak self] in
            guard let self, self.cursorRevision == revision else { return }
            self.cursorReapplyPending = false
            guard let edge = self.hoveredEdge, self.cursorWindow?.isVisible == true else { return }
            edge.cursor.set()
        }
    }

    private func releaseResizeCursor() {
        guard cursorWindow != nil || hoveredEdge != nil else { return }
        cursorRevision += 1
        cursorReapplyPending = false
        if restoresCursorRects, let cursorWindow {
            cursorWindow.enableCursorRects()
            cursorWindow.invalidateCursorRects(for: self)
        }
        cursorWindow = nil
        restoresCursorRects = false
        hoveredEdge = nil
        NSCursor.arrow.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event, force: true)
        if hoveredEdge == nil { super.cursorUpdate(with: event) }
    }
    override func mouseEntered(with event: NSEvent) { updateCursor(for: event, force: true) }
    override func mouseMoved(with event: NSEvent) { updateCursor(for: event, force: true) }
    override func mouseExited(with event: NSEvent) {
        if drag == nil { releaseResizeCursor() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, window.styleMask.contains(.resizable),
              let edge = PanelResizeGeometry.edge(at: convert(event.locationInWindow, from: nil), in: bounds, horizontalInset: horizontalInset) else { return }
        drag = Drag(edge: edge, mouse: window.convertPoint(toScreen: event.locationInWindow), frame: window.frame,
                    minimum: window.minSize, maximum: window.maxSize, visibleFrame: window.screen?.visibleFrame)
        edge.cursor.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let frame = PanelResizeGeometry.resizedFrame(from: drag.frame, edge: drag.edge,
            delta: NSSize(width: mouse.x - drag.mouse.x, height: mouse.y - drag.mouse.y),
            minimum: drag.minimum, maximum: drag.maximum, visibleFrame: drag.visibleFrame)
        window.setFrame(frame, display: true)
        drag.edge.cursor.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        mouseDragged(with: event)
        finishResize()
        updateCursor(for: event, force: true)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finishResize(); releaseResizeCursor() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func finishResize() {
        guard drag != nil else { return }
        drag = nil
        if let window {
            window.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
        }
        releaseResizeCursor()
    }
}

private final class PanelResizeContainerView: NSView {
    let edges: PanelResizeEdgesView
    init(content: NSView, horizontalInset: CGFloat = 0) {
        edges = PanelResizeEdgesView(frame: .zero, horizontalInset: horizontalInset)
        super.init(frame: NSRect(origin: .zero, size: content.frame.size))
        content.removeFromSuperview()
        content.frame = bounds; content.autoresizingMask = [.width, .height]
        addSubview(content)
        edges.frame = bounds; edges.autoresizingMask = [.width, .height]
        addSubview(edges, positioned: .above, relativeTo: content)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

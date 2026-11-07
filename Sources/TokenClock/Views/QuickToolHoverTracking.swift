#if os(macOS)
import AppKit
import SwiftUI

struct QuickToolHoverRegion: Equatable {
    let tool: QuickTool
    let rect: NSRect
}

/// The labels and native hover regions use the same widths while the strip expands.
struct QuickToolHoverLayout {
    static let spacing: CGFloat = 6
    let narrowWidth: CGFloat
    let expandedWidth: CGFloat
    let regions: [QuickToolHoverRegion]

    init(items: [QuickTool], expanded: QuickTool?, width: CGFloat) {
        let otherCount = CGFloat(max(0, items.count - 1))
        let narrow = min(32, max(24, (width - Self.spacing * otherCount - 110) / max(1, otherCount)))
        let wide = max(narrow, width - (narrow + Self.spacing) * otherCount)
        narrowWidth = narrow
        expandedWidth = wide
        let selected = expanded.flatMap { items.contains($0) ? $0 : nil } ?? items.first
        var x: CGFloat = 0
        regions = items.map { item in
            let itemWidth = item == selected ? wide : narrow
            defer { x += itemWidth + Self.spacing }
            return QuickToolHoverRegion(tool: item, rect: NSRect(x: x, y: 0, width: itemWidth, height: 46))
        }
    }
}

/// SwiftUI hover delivery can depend on activation in a nonactivating NSPanel.
/// AppKit tracks this strip even while another app is active, without taking clicks.
struct QuickToolHoverTracking: NSViewRepresentable {
    let regions: [QuickToolHoverRegion]
    let onHover: (QuickTool?) -> Void

    func makeNSView(context: Context) -> QuickToolHoverNSView {
        QuickToolHoverNSView(regions: regions, onHover: onHover)
    }
    func updateNSView(_ view: QuickToolHoverNSView, context: Context) {
        view.regions = regions
        view.onHover = onHover
    }
    static func dismantleNSView(_ view: QuickToolHoverNSView, coordinator: ()) {
        view.onHover = { _ in }
    }
}

final class QuickToolHoverNSView: NSView {
    var regions: [QuickToolHoverRegion]
    var onHover: (QuickTool?) -> Void
    private var area: NSTrackingArea?
    private var hoveredTool: QuickTool?

    init(regions: [QuickToolHoverRegion], onHover: @escaping (QuickTool?) -> Void) {
        self.regions = regions
        self.onHover = onHover
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if window == nil { hoveredTool = nil }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseEntered(with event: NSEvent) { track(event) }
    override func mouseMoved(with event: NSEvent) { track(event) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func track(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHovered(bounds.contains(point) ? regions.first { $0.rect.contains(point) }?.tool : nil)
    }
    private func setHovered(_ tool: QuickTool?) {
        guard tool != hoveredTool else { return }
        hoveredTool = tool
        onHover(tool)
    }
}
#endif

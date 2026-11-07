#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import TokenClock

/// Send mouse sequences through the window containing the actual detail view.
/// The visible rounded border is inset from the transparent NSPanel bounds.
@MainActor final class NormalPanelBorderTests: XCTestCase {
    private func settle(_ view: NSView) {
        for _ in 0..<4 { view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    private func event(_ type: NSEvent.EventType, screenPoint: NSPoint, panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: screenPoint),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    private func clock() throws -> NSRect {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        return NSRect(x: screen.midX - 120, y: screen.maxY - 220, width: 240, height: 200)
    }
    private func drag(_ panel: NSPanel, from start: NSPoint, to end: NSPoint) throws {
        panel.sendEvent(try event(.leftMouseDown, screenPoint: start, panel: panel))
        panel.sendEvent(try event(.leftMouseDragged, screenPoint: end, panel: panel))
        panel.sendEvent(try event(.leftMouseUp, screenPoint: end, panel: panel))
    }
    private func hoverTrackers(_ view: NSView) -> [QuickToolHoverNSView] {
        ((view as? QuickToolHoverNSView).map { [$0] } ?? []) + view.subviews.flatMap(hoverTrackers)
    }

    func testVisibleDetailBordersDragWithoutActivationAndControlsRemainClickable() throws {
        let clock = try clock()
        var modelClicks = 0
        let weather = WeatherInfo(emoji: "☀️", temperature: 23, cityName: "Fixture city")
        let root = VStack(spacing: 0) {
            DetailDropdownView(tools: [], weather: weather, localizedCityName: "Fixture city", onModelDetect: { modelClicks += 1 })
            Color.clear.frame(height: FloatingPanel.resizeGripHeight)
        }
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        let panel = DropdownPanel(); panel.alphaValue = 0; panel.isReleasedWhenClosed = false
        panel.contentView = PanelResizeEdgesView.wrapping(host, horizontalInset: FloatingPanel.detailHorizontalInset)
        panel.show(below: clock, activeToolCount: 0, showsWeather: true)
        defer { panel.orderOut(nil); panel.close() }
        settle(host)
        let edges = try XCTUnwrap(PanelResizeEdgesView.install(on: panel))
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertEqual(edges.horizontalInset, FloatingPanel.detailHorizontalInset)
        let original = panel.frame
        let right = NSPoint(x: original.maxX - FloatingPanel.detailHorizontalInset - 1, y: original.midY)
        XCTAssertTrue(panel.contentView?.hitTest(panel.convertPoint(fromScreen: right)) === edges)
        try drag(panel, from: right, to: NSPoint(x: right.x + 40, y: right.y))
        XCTAssertEqual(panel.frame.width, original.width + 40, accuracy: 0.01)
        XCTAssertEqual(panel.frame.minX, original.minX, accuracy: 0.01)
        let widened = panel.frame
        let left = NSPoint(x: widened.minX + FloatingPanel.detailHorizontalInset + 1, y: widened.midY)
        try drag(panel, from: left, to: NSPoint(x: left.x - 25, y: left.y))
        XCTAssertEqual(panel.frame.width, widened.width + 25, accuracy: 0.01)
        XCTAssertEqual(panel.frame.maxX, widened.maxX, accuracy: 0.01)
        let finalWidth = panel.frame.width
        panel.hide(); panel.show(below: clock.offsetBy(dx: 10, dy: 0), activeToolCount: 0, showsWeather: true)
        XCTAssertEqual(panel.frame.width, finalWidth, accuracy: 0.01)
        settle(host)
        let tracker = try XCTUnwrap(hoverTrackers(host).first)
        let model = try XCTUnwrap(tracker.regions.first { $0.tool == .model })
        let buttonPoint = panel.convertPoint(toScreen: tracker.convert(NSPoint(x: model.rect.midX, y: model.rect.midY), to: nil))
        XCTAssertFalse(panel.contentView?.hitTest(panel.convertPoint(fromScreen: buttonPoint)) === edges)
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            panel.sendEvent(try event(type, screenPoint: buttonPoint, panel: panel))
        }
        settle(host)
        XCTAssertEqual(modelClicks, 1)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testNotificationSideAndCornerUseWindowEventRoutingAndRetainDimensions() throws {
        let clock = try clock(), panel = NotificationPanel()
        panel.alphaValue = 0; panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: VStack { Text("Notifications"); Spacer(); Text("Fixture notice") }
            .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.gray.opacity(0.3)))
        content.frame = NSRect(x: 0, y: 0, width: 280, height: 240)
        panel.contentView = PanelResizeEdgesView.wrapping(content)
        panel.show(near: clock)
        defer { panel.orderOut(nil); panel.close() }
        settle(content)
        let edges = try XCTUnwrap(PanelResizeEdgesView.install(on: panel))
        let initial = panel.frame
        let right = NSPoint(x: initial.maxX - 2, y: initial.midY)
        XCTAssertTrue(panel.contentView?.hitTest(panel.convertPoint(fromScreen: right)) === edges)
        try drag(panel, from: right, to: NSPoint(x: right.x + 30, y: right.y))
        XCTAssertEqual(panel.frame.width, initial.width + 30, accuracy: 0.01)
        let beforeCorner = panel.frame
        let corner = NSPoint(x: beforeCorner.maxX - 2, y: beforeCorner.minY + 2)
        try drag(panel, from: corner, to: NSPoint(x: corner.x + 20, y: corner.y - 25))
        XCTAssertEqual(panel.frame.width, beforeCorner.width + 20, accuracy: 0.01)
        XCTAssertEqual(panel.frame.height, beforeCorner.height + 25, accuracy: 0.01)
        let size = panel.frame.size
        panel.hide(); panel.show(near: clock)
        XCTAssertEqual(panel.frame.size, size)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testInactiveCursorTracksVisibleSidesCornersAndReturnsToArrowInside() throws {
        let clock = try clock(), panel = DropdownPanel()
        panel.alphaValue = 0; panel.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 300))
        panel.contentView = PanelResizeEdgesView.wrapping(content, horizontalInset: FloatingPanel.detailHorizontalInset)
        panel.show(below: clock, activeToolCount: 1, showsWeather: true)
        let previousCursor = NSCursor.current
        defer { previousCursor.set(); panel.orderOut(nil); panel.close() }
        let edges = try XCTUnwrap(PanelResizeEdgesView.install(on: panel))
        edges.updateTrackingAreas()
        XCTAssertTrue(panel.acceptsMouseMovedEvents)
        XCTAssertTrue(edges.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseMoved) })
        XCTAssertTrue(edges.trackingAreas.contains { $0.options.contains(.activeInActiveApp) && $0.options.contains(.cursorUpdate) })
        XCTAssertFalse(edges.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.cursorUpdate) })
        NSCursor.arrow.set()
        for point in [NSPoint(x: panel.frame.minX + 9, y: panel.frame.midY),
                      NSPoint(x: panel.frame.maxX - 9, y: panel.frame.midY),
                      NSPoint(x: panel.frame.maxX - 9, y: panel.frame.maxY - 2)] {
            panel.sendEvent(try event(.mouseMoved, screenPoint: point, panel: panel))
            XCTAssertFalse(NSCursor.current === NSCursor.arrow)
            XCTAssertFalse(panel.areCursorRectsEnabled)
            // Model a late reset by the hosting view; the end-of-dispatch correction must win.
            NSCursor.arrow.set()
            settle(content)
            XCTAssertFalse(NSCursor.current === NSCursor.arrow)
        }
        edges.mouseMoved(with: try event(.mouseMoved, screenPoint: NSPoint(x: panel.frame.midX, y: panel.frame.midY), panel: panel))
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        XCTAssertTrue(panel.areCursorRectsEnabled)
        let edgePoint = NSPoint(x: panel.frame.maxX - 9, y: panel.frame.midY)
        panel.sendEvent(try event(.mouseMoved, screenPoint: edgePoint, panel: panel))
        XCTAssertFalse(panel.areCursorRectsEnabled)
        panel.hide()
        settle(content)
        XCTAssertTrue(panel.areCursorRectsEnabled)
        XCTAssertTrue(NSCursor.current === NSCursor.arrow)
        XCTAssertFalse(panel.isKeyWindow)
    }
    func testHoverHintInInactivePanelAppearsWrapsAndClosesWithoutTakingClicks() throws {
        _ = NSApplication.shared
        let hint = String(repeating: "Complete tooltip text with words to wrap. ", count: 6)
        let host = NSHostingView(rootView: Text("Hint target").padding(20).instantHint(hint))
        host.frame = NSRect(x: 0, y: 0, width: 220, height: 90)
        let panel = DropdownPanel(); panel.alphaValue = 0; panel.isReleasedWhenClosed = false
        panel.setFrame(NSRect(x: -10_000, y: -10_000, width: 220, height: 90), display: false)
        panel.contentView = host; panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        settle(host)
        func find(_ view: NSView) -> PassiveHoverNSView? {
            if let tracker = view as? PassiveHoverNSView { return tracker }
            return view.subviews.lazy.compactMap(find).first
        }
        let tracker = try XCTUnwrap(find(host))
        tracker.updateTrackingAreas()
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(tracker.trackingAreas.contains { $0.options.contains(.activeAlways) })
        XCTAssertNil(tracker.hitTest(.zero))
        func hover(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        }
        tracker.mouseEntered(with: try hover(.mouseEntered))
        settle(host)
        let popup = try XCTUnwrap(panel.childWindows?.first)
        popup.alphaValue = 0
        XCTAssertTrue(popup.isVisible)
        XCTAssertLessThanOrEqual(popup.frame.width, 280)
        let label = try XCTUnwrap(popup.contentView?.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(label.stringValue, hint)
        XCTAssertGreaterThan(label.frame.height, 30)
        XCTAssertFalse(panel.isKeyWindow)
        tracker.mouseExited(with: try hover(.mouseExited))
        settle(host)
        XCTAssertTrue(panel.childWindows?.isEmpty ?? true)
    }

}
#endif

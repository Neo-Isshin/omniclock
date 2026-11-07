#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import TokenClock

@MainActor final class QuickToolHoverTests: XCTestCase {
    private func settle(_ host: NSView, for seconds: TimeInterval = 0.38) {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: min(end, Date().addingTimeInterval(0.02)))
        } while Date() < end
        host.layoutSubtreeIfNeeded()
    }
    private func trackers(in view: NSView) -> [QuickToolHoverNSView] {
        ((view as? QuickToolHoverNSView).map { [$0] } ?? []) + view.subviews.flatMap { trackers(in: $0) }
    }
    private func event(_ type: NSEvent.EventType, at point: NSPoint, window: NSWindow) throws -> NSEvent {
        if type == .mouseExited {
            return try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
        }
        return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    func testInactiveDropdownExpandsAndResetsWithoutRunningToolsAndStillAcceptsClicks() throws {
        _ = NSApplication.shared
        var clicked: [QuickTool] = []
        let items = QuickToolPreferences.defaults
        let host = NSHostingView(rootView: QuickToolHoverStrip(items: items, color: .primary) { clicked.append($0) })
        let panel = DropdownPanel()
        panel.setFrame(NSRect(x: -10_000, y: -10_000, width: 320, height: 46), display: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = PanelResizeEdgesView.wrapping(host)
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        settle(host, for: 0.08)
        let tracking = try XCTUnwrap(trackers(in: host).first)
        tracking.updateTrackingAreas()
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertTrue(panel.acceptsMouseMovedEvents)
        XCTAssertTrue(tracking.trackingAreas.contains { $0.options.contains(.activeAlways) && $0.options.contains(.mouseMoved) })
        XCTAssertEqual(tracking.regions.count, items.count)

        func point(_ item: QuickTool) throws -> NSPoint {
            let rect = try XCTUnwrap(tracking.regions.first { $0.tool == item }?.rect)
            return tracking.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        }
        func move(_ item: QuickTool) throws {
            tracking.mouseMoved(with: try event(.mouseMoved, at: point(item), window: panel))
        }
        func width(_ item: QuickTool) throws -> CGFloat {
            try XCTUnwrap(tracking.regions.first { $0.tool == item }?.rect.width)
        }
        XCTAssertGreaterThan(try width(.model), try width(.notebook))
        try move(.notebook)
        settle(host)
        XCTAssertGreaterThan(try width(.notebook), try width(.model))
        XCTAssertTrue(clicked.isEmpty, "Hovering must not start a check or open a tool")

        try move(.network)
        try move(.quota)
        settle(host)
        XCTAssertGreaterThan(try width(.quota), try width(.network), "Only the latest hover should expand")
        XCTAssertTrue(clicked.isEmpty)
        let click = try point(.quota)
        XCTAssertNil(tracking.hitTest(tracking.convert(click, from: nil)), "Native tracking must leave clicks to SwiftUI")
        // These events go only to this offscreen fixture, never to the user's cursor or another app.
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            panel.sendEvent(try event(type, at: click, window: panel))
        }
        settle(host, for: 0.08)
        XCTAssertEqual(clicked, [.quota])
        tracking.mouseExited(with: try event(.mouseExited, at: click, window: panel))
        settle(host)
        XCTAssertGreaterThan(try width(.model), try width(.quota))
        XCTAssertEqual(clicked, [.quota])
    }

    func testResizingUsesTheSameHoverBoundsAndKeepsAllToolsReachable() throws {
        _ = NSApplication.shared
        let items = QuickTool.allCases
        let host = NSHostingView(rootView: QuickToolHoverStrip(items: items, color: .primary) { _ in XCTFail("Hover must not invoke actions") })
        let panel = DropdownPanel()
        panel.isReleasedWhenClosed = false
        panel.contentView = PanelResizeEdgesView.wrapping(host)
        panel.orderFront(nil)
        defer { panel.orderOut(nil); panel.close() }
        for width: CGFloat in [320, 500] {
            panel.setFrame(NSRect(x: -10_000, y: -10_000, width: width, height: 46), display: false)
            settle(host, for: 0.08)
            let tracking = try XCTUnwrap(trackers(in: host).first)
            let share = try XCTUnwrap(tracking.regions.first { $0.tool == .share })
            XCTAssertEqual(tracking.regions.first?.rect.minX, 0)
            XCTAssertEqual(tracking.regions.last!.rect.maxX, tracking.bounds.width, accuracy: 1)
            let point = tracking.convert(NSPoint(x: share.rect.midX, y: share.rect.midY), to: nil)
            tracking.mouseMoved(with: try event(.mouseMoved, at: point, window: panel))
            settle(host)
            let expanded = try XCTUnwrap(tracking.regions.first { $0.tool == .share })
            XCTAssertGreaterThan(expanded.rect.width, tracking.regions.first!.rect.width)
            XCTAssertEqual(expanded.rect.maxX, tracking.bounds.width, accuracy: 1)
            XCTAssertFalse(panel.isKeyWindow)
        }
    }
}
#endif

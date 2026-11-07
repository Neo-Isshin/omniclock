#if os(macOS)
import AppKit
import SwiftUI

/// Hover feedback in a floating panel must work while another application is active.
/// This view never handles clicks and does not install a global event monitor.
struct PassiveHoverTracking: NSViewRepresentable {
    let onHover: (Bool) -> Void
    func makeNSView(context: Context) -> PassiveHoverNSView { PassiveHoverNSView(onHover: onHover) }
    func updateNSView(_ view: PassiveHoverNSView, context: Context) { view.onHover = onHover }
    static func dismantleNSView(_ view: PassiveHoverNSView, coordinator: ()) { view.onHover = { _ in } }
}

final class PassiveHoverNSView: NSView {
    var onHover: (Bool) -> Void
    private var area: NSTrackingArea?
    private var hovering = false
    init(onHover: @escaping (Bool) -> Void) {
        self.onHover = onHover
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(next); area = next
    }
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        onHover(true)
    }
    override func mouseExited(with event: NSEvent) {
        guard hovering else { return }
        hovering = false
        onHover(false)
    }
}

extension View {
    func passiveHover(_ onHover: @escaping (Bool) -> Void) -> some View {
        background(PassiveHoverTracking(onHover: onHover).allowsHitTesting(false))
    }
}
#endif

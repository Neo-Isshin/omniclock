#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import TokenClock

@MainActor final class NetworkToolboxLayoutTests: XCTestCase {
    private func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
    func testEveryResultCardHasSixRowsOfSpaceRegardlessOfItsContent() throws {
        _ = NSApplication.shared
        for width: CGFloat in [280, 368, 408] {
            for count in [0, 1, 6, 20] {
                let text = (0..<count).map { "203.0.113.\($0) · Example location with a long display name" }.joined(separator:"\n")
                let card = NetworkToolboxPresentation.Card(id:"dns",title:"",status:"",text:text,state:"review")
                XCTAssertEqual(card.detailLines.count, max(1, count))
                let host = NSHostingView(rootView: NetworkToolboxResultCard(card:card,icon:"server.rack").frame(width:width))
                host.frame=NSRect(x:0,y:0,width:width,height:NetworkToolboxCardLayout.cardHeight)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.fittingSize.height,NetworkToolboxCardLayout.cardHeight,accuracy:1)
                XCTAssertEqual(NetworkToolboxCardLayout.detailsHeight/NetworkToolboxCardLayout.rowHeight,6)
                if count == 20 {
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    defer { window.close() }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                    host.layoutSubtreeIfNeeded()
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: bitmap) }
                    let scroll = try XCTUnwrap(scrollViews(in: host).first)
                    let document = try XCTUnwrap(scroll.documentView)
                    XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
                    let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "All twenty rows must be reachable by scrolling")
                }
            }
        }
        let model = MainlandReachabilityModel()
        let host = NSHostingView(rootView:MainlandReachabilityCard(model:model,observedExitIP:nil).frame(width:368))
        host.frame=NSRect(x:0,y:0,width:368,height:NetworkToolboxCardLayout.cardHeight)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height,NetworkToolboxCardLayout.cardHeight,accuracy:1)
        XCTAssertFalse(model.running)
    }
    func testUniformNetworkToolboxRendersWithoutStartingChecks() throws {
        guard let output=ProcessInfo.processInfo.environment["TOKENCLOCK_NETWORK_PREVIEW_DIR"] else {throw XCTSkip("Opt-in UI artifacts")}
        _ = NSApplication.shared
        let model=NetworkToolboxPresentation()
        model.cards=[
            .init(id:"exit",title:"",status:"",text:"203.0.113.10 · HTTPS",state:"observed"),
            .init(id:"dns",title:"",status:"",text:"203.0.113.20 · United States\n203.0.113.21 · Singapore",state:"review"),
            .init(id:"rtc",title:"",status:"",text:"203.0.113.10 · Public IP",state:"match"),
            .init(id:"consistency",title:"",status:"",text:"Ailyre · 203.0.113.10\nCloudflare · 203.0.113.10",state:"match"),
            .init(id:"ipv6",title:"",status:"",text:"IPv6 · No response",state:"notObserved"),
            .init(id:"ai",title:"",status:"",text:["ChatGPT","Claude","Gemini","OpenAI API","Anthropic API","xAI API"].map{$0+" · Exit not confirmed"}.joined(separator:"\n"),state:"partial"),
            .init(id:"doh",title:"",status:"",text:"Cloudflare · Encrypted DNS works\nGoogle · Encrypted DNS works",state:"partial")
        ]
        let host=NSHostingView(rootView:NetworkToolboxView(model:model,onRun:{XCTFail("Preview must not run probes")},onStop:{},onBrowser:{XCTFail("Preview must not open a browser")},onOptions:{}))
        host.frame=NSRect(x:0,y:0,width:780,height:1250);host.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds));host.cacheDisplay(in:host.bounds,to:bitmap)
        let directory=URL(fileURLWithPath:output);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("network-toolbox-preview.png"))
        XCTAssertFalse(model.running)
        XCTAssertFalse(model.mainland.running)
    }
}
#endif

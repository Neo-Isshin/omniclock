#if os(macOS)
import AppKit
import WebKit
import XCTest
@testable import TokenClock

final class NetworkLeakLiveTests: XCTestCase {
    @MainActor func testRealWebKitCheckAndWindowTeardown() async throws {
        guard ProcessInfo.processInfo.environment["TOKENCLOCK_NETWORK_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt-in live DNS/STUN service check")
        }
        _ = NSApplication.shared
        let controller = NetworkLeakWindow()
        controller.show()
        defer { controller.window?.close() }
        XCTAssertTrue(controller.hasActiveProbe)
        let browser = try XCTUnwrap(controller.probeView)
        var state = ""
        for _ in 0..<150 {
            try await Task.sleep(nanoseconds: 200_000_000)
            state = await text(browser, "document.getElementById('idle')?.textContent || ''")
            if state.contains("finished") || state.contains("检测完成") || state.contains("could not") || state.contains("未能完成") { break }
        }
        XCTAssertTrue(state.contains("finished") || state.contains("检测完成"), state)
        let resolvers = await text(browser, "String(document.querySelectorAll('#dnsAddresses code').length)")
        XCTAssertGreaterThan(Int(resolvers) ?? 0, 0)
        let totalResolvers = await text(browser, "String(window.TokenClockLeak.snapshot()?.resolvers.length || 0)")
        XCTAssertEqual(resolvers, totalResolvers, "The six-row viewport must retain every DNS result")
        let verdict = await text(browser, "document.getElementById('rtcBadge')?.dataset.state || ''")
        XCTAssertTrue(["match", "review", "risk", "incomplete"].contains(verdict), "Unexpected WebRTC classification: " + verdict)
        print("Native WebKit live check: DNS observed; WebRTC verdict=" + verdict)
        let aiCount = await text(browser, "String(document.querySelectorAll('#aiAddresses .diagnostic-row').length)")
        XCTAssertEqual(aiCount, "6")
        let consistency = await text(browser, "String(document.querySelectorAll('#consistencyAddresses .diagnostic-row').length)")
        XCTAssertGreaterThanOrEqual(Int(consistency) ?? 0, 3)
        let v6 = await text(browser, "document.getElementById('ipv6Badge')?.dataset.state || ''")
        XCTAssertTrue(["match", "review", "risk", "notObserved"].contains(v6))
        print("Native diagnostics: six AI domains, exit/country observations, IPv6 verdict=" + v6)
        XCTAssertEqual(controller.presentedCards.count,7)
        for card in controller.presentedCards {
            XCTAssertFalse(card.text.replacingOccurrences(of:"·",with:"").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,"Hidden WebKit text must reach native cards: "+card.id)
        }
        XCTAssertFalse(controller.presentedSummary.isEmpty)
        let doh = await text(browser,"document.getElementById('dohBadge')?.dataset.state || ''")
        XCTAssertTrue(["match","partial","review","risk","incomplete"].contains(doh))
        XCTAssertTrue(controller.presentedCards.allSatisfy { !$0.resultSummary.isEmpty })
        if let output = ProcessInfo.processInfo.environment["TOKENCLOCK_NETWORK_LIVE_REPORT"] {
            let report = await text(browser,"JSON.stringify({probe:window.TokenClockLeak?.snapshot(),diagnostics:window.TokenClockDiagnostics?.snapshot(),cards:['exit','dns','rtc','consistency','ipv6','ai','doh'].map(id=>({id,state:document.getElementById(id+'Badge')?.dataset.state,reason:document.getElementById(id+'Badge')?.dataset.reason,summary:document.getElementById(id+'Summary')?.textContent}))})")
            let url = URL(fileURLWithPath: output)
            try Data(report.utf8).write(to:url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        }
        // An explicit second run is cancelled by closing the containing window.
        _ = await text(browser, "document.getElementById('start').click(); 'started'")
        controller.window?.close()
        XCTAssertFalse(controller.hasActiveProbe)
    }

    @MainActor private func text(_ browser: WKWebView, _ script: String) async -> String {
        await withCheckedContinuation { continuation in
            browser.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }
}
#endif

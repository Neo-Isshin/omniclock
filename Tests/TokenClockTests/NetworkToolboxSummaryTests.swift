#if os(macOS)
import XCTest
@testable import TokenClock

@MainActor final class NetworkToolboxSummaryTests: XCTestCase {
    func testMatchingDNSLocationsAreReportedWithoutAnUnknownDNSVerdict() {
        let model=NetworkToolboxPresentation()
        model.update(["running":false,"cards":[["id":"dns","state":"observed","reason":"sameDNSCity","text":"Los Angeles"],["id":"ai","state":"match","reason":"exitChecksComplete"]]])
        let card=model.cards[0]
        XCTAssertTrue(card.dnsLocationMatches)
        XCTAssertFalse(card.localizedStatus.contains("determine"))
        XCTAssertFalse(model.pendingSummary.contains("DNS"))
        XCTAssertFalse(model.issueSummary.contains("暂无法判断"))
        XCTAssertTrue(model.cards[1].resultSummary.contains("Gemini"))
    }
    func testUnknownAndDNSWithoutExpectationAreNotClaimedSafeOrLeaking() {
        let model = NetworkToolboxPresentation()
        model.cards = [.init(id:"dns",title:"DNS",status:"Review",text:"",state:"review"),.init(id:"rtc",title:"WebRTC",status:"",text:"",state:"incomplete")]
        XCTAssertFalse(model.issueSummary.contains("possible leak"))
        XCTAssertFalse(model.issueSummary.contains("可能泄漏"))
        XCTAssertFalse(model.issueSummary.contains("未检出"))
        XCTAssertFalse(model.issueSummary.contains("No leak"))
        XCTAssertTrue(model.pendingSummary.contains("DNS"))
        XCTAssertTrue(model.pendingSummary.contains("WebRTC"))
    }
    func testSummaryNamesOnlyRisksAndKeepsUnknownSeparate() {
        let model = NetworkToolboxPresentation()
        model.cards = [.init(id:"dns",title:"DNS",status:"",text:"",state:"risk"),.init(id:"rtc",title:"WebRTC",status:"",text:"",state:"match"),.init(id:"doh",title:"DoH",status:"",text:"",state:"incomplete")]
        XCTAssertTrue(model.issueSummary.contains("DNS"))
        XCTAssertFalse(model.issueSummary.contains("WebRTC"))
        XCTAssertFalse(model.issueSummary.contains("DoH"))
        XCTAssertTrue(model.pendingSummary.contains("DoH"))
        model.running = true
        XCTAssertFalse(model.issueSummary.contains("DNS"))
    }
}
#endif

#if os(macOS)
extension NetworkToolboxSummaryTests {
    @MainActor func testWebExitAndReachableSitesCannotMakeUnknownLeakChecksLookSafe() {
        let model = NetworkToolboxPresentation()
        model.cards = [
            .init(id:"exit",title:"",status:"",text:"1.1.1.1",state:"observed"),
            .init(id:"dns",title:"",status:"",text:"",state:"review"),
            .init(id:"rtc",title:"",status:"",text:"",state:"incomplete"),
            .init(id:"ipv6",title:"",status:"",text:"",state:"notObserved"),
            .init(id:"ai",title:"",status:"",text:"",state:"partial"),
            .init(id:"doh",title:"",status:"",text:"",state:"partial")
        ]
        XCTAssertFalse(model.issueSummary.contains("No leak"))
        XCTAssertFalse(model.issueSummary.contains("未发现异常"))
        XCTAssertTrue(model.pendingSummary.contains("DNS"))
        XCTAssertTrue(model.pendingSummary.contains("IPv6"))
        XCTAssertFalse(model.pendingSummary.contains("incomplete"))
        XCTAssertFalse(model.pendingSummary.contains("未完成"))
    }
    @MainActor func testEachResultHasAPlainConclusionAndLocalExposureIsExplicit() {
        let model = NetworkToolboxPresentation()
        model.update(["running":false,"cards":[
            ["id":"rtc","state":"review","reason":"localAddressExposed","text":"192.168.1.10"],
            ["id":"dns","state":"match","text":"1.1.1.1 · Australia"],
            ["id":"doh","state":"match","reason":"sameDoHExit","text":"Cloudflare · connected"]
        ]])
        XCTAssertEqual(model.cards.first?.reason,"localAddressExposed")
        XCTAssertTrue(model.issueSummary.contains("WebRTC"))
        XCTAssertTrue(model.cards.allSatisfy { !$0.resultSummary.isEmpty })
        XCTAssertFalse(model.cards[2].localizedStatus.contains("verified"))
    }
}
#endif

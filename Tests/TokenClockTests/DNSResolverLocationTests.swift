#if os(macOS)
import Foundation
import XCTest
@testable import TokenClock

final class DNSResolverLocationTests: XCTestCase {
    func testLocationsOnlyUseDistinctPublicSourcesWithinTheObservationLimit() {
        let sources = ["127.0.0.1", "10.0.0.1", "::1", "1.1.1.1", "1.1.1.1", "8.8.8.8", "bad/host", "2001:4860::8888"]
        XCTAssertEqual(DNSResolverLocations.addresses(sources), ["1.1.1.1", "8.8.8.8", "2001:4860::8888"])
        XCTAssertEqual(DNSResolverLocations.addresses((1...40).map { "8.8.4.\($0)" }).count, 32)
    }
    func testLocationBelongsToTheRequestedResolverAndUnknownRemainsUnknown() throws {
        func reply(_ json: String, status: Int = 200) -> NetworkDiagnosticReply {
            .init(data: Data(json.utf8), status: status, limited: false)
        }
        let value = try XCTUnwrap(DNSResolverLocations.parse(reply(#"{"ip":"8.8.8.8","success":true,"country_code":"US","city":"Mountain View"}"#), ip: "8.8.8.8", source: "fixture"))
        XCTAssertEqual(value.category, "dnsGeo")
        XCTAssertEqual(value.country, "US")
        XCTAssertEqual(value.city, "Mountain View")
        XCTAssertNil(DNSResolverLocations.parse(reply(#"{"ip":"1.1.1.1","country":"AU"}"#), ip: "8.8.8.8", source: "fixture"))
        XCTAssertNil(DNSResolverLocations.parse(reply(#"{"ip":"8.8.8.8","country":"XX"}"#), ip: "8.8.8.8", source: "fixture"))
        XCTAssertNil(DNSResolverLocations.parse(reply(#"{"ip":"8.8.8.8","country":"US"}"#, status: 403), ip: "8.8.8.8", source: "fixture"))
    }
    func testEmptyOrPrivateAddressesDoNotStartLocationRequests() async {
        let rows = await DNSResolverLocations.lookup(["127.0.0.1", "10.0.0.1", "invalid"])
        XCTAssertTrue(rows.isEmpty)
    }
}
#endif

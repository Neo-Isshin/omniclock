#if os(Windows)
import Foundation
import XCTest
import Win32Shim
@testable import TokenClock
final class WindowsTimeZoneTests: XCTestCase {
    func testWindowsZoneMapsToTheActualSystemOffsetWithoutChangingTheClock() throws {
        let identifier=try XCTUnwrap(WindowsTimeZone.systemIdentifier())
        let zone=try XCTUnwrap(TimeZone(identifier:identifier))
        XCTAssertEqual(zone.secondsFromGMT(for:Date()),Int(win_system_timezone_offset()))
    }
    func testNamedZonesKeepDaylightSavingRulesRatherThanOneFixedOffset() throws {
        let zone=try XCTUnwrap(TimeZone(identifier:"America/Los_Angeles"))
        let winter=try XCTUnwrap(DateHelper.parseISO8601("2026-01-15T12:00:00Z"))
        let summer=try XCTUnwrap(DateHelper.parseISO8601("2026-07-15T12:00:00Z"))
        XCTAssertEqual(zone.secondsFromGMT(for:winter),-8*3600)
        XCTAssertEqual(zone.secondsFromGMT(for:summer),-7*3600)
    }
}
#endif

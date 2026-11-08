#if os(Windows)
import Foundation
import XCTest
@testable import TokenClock

final class WindowsToolboxContractTests: XCTestCase {
    func testRemoteChecksCannotInvokeLocalNotebookOrCredentialActions() {
        XCTAssertFalse(WindowsToolboxMessageScope.permitsLocalCommand(page:"network"))
        XCTAssertFalse(WindowsToolboxMessageScope.permitsLocalCommand(page:"model"))
        XCTAssertTrue(WindowsToolboxMessageScope.permitsLocalCommand(page:"details"))
        XCTAssertTrue(WindowsToolboxMessageScope.permitsLocalCommand(page:"local"))
    }
    func testWindowsInterpreterDiscoveryUsesTheActualPathEnvironmentSpelling() {
        XCTAssertEqual(ModelIntegrityLauncher.windowsSearchPath(["Path":"C:\\Python;D:\\Tools"]),["C:\\Python","D:\\Tools"])
        XCTAssertEqual(ModelIntegrityLauncher.windowsSearchPath(["PATH":"C:\\Python"]),["C:\\Python"])
    }
    func testDurableFeatureDefaultsPreserveBinaryJSONDatesAndSelections() throws {
        let store=WindowsDurableDefaults.persistent,key="FeatureFixture."+UUID().uuidString
        defer {store.removeObject(forKey:key)}
        let bytes=Data("{\"fixture\":true}".utf8)
        store.set(bytes,forKey:key);XCTAssertEqual(store.data(forKey:key),bytes)
        store.set(["network","local","notebook"],forKey:key)
        XCTAssertEqual(store.stringArray(forKey:key),["network","local","notebook"])
        store.set(true,forKey:key);XCTAssertTrue(store.bool(forKey:key))
        store.set(3,forKey:key);XCTAssertEqual(store.integer(forKey:key),3)
        let date=Date(timeIntervalSince1970:123456)
        store.set(date,forKey:key);XCTAssertEqual(store.object(forKey:key) as? Date,date)
    }
    func testNativeAddressParsingKeepsDNSAndIPv6ResultsComparable() {
        XCTAssertEqual(NetworkDiagnosticParser.address("2606:4700:4700:0:0:0:0:1111"),"2606:4700:4700::1111")
        XCTAssertNil(NetworkDiagnosticParser.address("https://1.1.1.1"))
        XCTAssertNil(MainlandReachabilityTarget.parse(ip:"127.0.0.1",port:"443"))
        XCTAssertNil(MainlandReachabilityTarget.parse(ip:"192.168.1.1",port:"443"))
        XCTAssertNotNil(MainlandReachabilityTarget.parse(ip:"2606:4700:4700::1111",port:"443"))
        let target=NetworkDiagnostics.targets.first{$0.id=="ipv6"}!
        let reply=NetworkDiagnosticReply(data:Data("{\"ip\":\"fd00::1\"}".utf8),status:200,limited:false)
        XCTAssertNil(NetworkDiagnostics.parse(reply,target:target).ip)
    }
    func testCredentialResultsSeparateBillingRegionAndInvalidKeys() {
        XCTAssertTrue(LocalConfigReader.classify(status:402,body:Data()).contains("💸"))
        XCTAssertTrue(LocalConfigReader.classify(status:401,body:Data()).contains("❌"))
        XCTAssertTrue(LocalConfigReader.classify(status:403,body:Data("unsupported_country".utf8)).contains("🌍"))
        XCTAssertFalse(LocalConfigReader.classify(status:nil,body:Data()).contains("❌"))
    }
}
#endif

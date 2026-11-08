#if os(Windows)
import Foundation
import XCTest
@testable import TokenClock

final class WindowsGrokCredentialTests: XCTestCase {
    private func token(_ subject: String) throws -> String {
        func encode(_ data: Data) -> String {data.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")}
        return encode(Data("{\"alg\":\"none\"}".utf8))+"."+encode(try JSONSerialization.data(withJSONObject:["sub":subject]))+".fixture"
    }
    func testOnlyActiveAccountIsDecodedAndScopeMismatchIsRejected() throws {
        let jwt=try token("auth0|fixture-user"),other=try token("auth0|other-user")
        let scope=GrokBotNativeCredentialStore.accountScope(for:jwt)
        let envelope=String(data:try JSONSerialization.data(withJSONObject:["active":scope,"accounts":[scope:["cursor-access-token":"token"],"other":["cursor-access-token":"other"]]]),encoding:.utf8)!
        let data=try JSONSerialization.data(withJSONObject:["cursor-accounts":envelope,"cursor-machine-id":"machine"])
        let value=WindowsGrokCredential.decode(data,localState:Data()){cipher,_ in cipher=="token" ? jwt:cipher=="machine" ? "fixture-machine":nil}
        XCTAssertEqual(value?.accessToken,jwt)
        XCTAssertEqual(value?.machineID,"fixture-machine")
        XCTAssertNil(WindowsGrokCredential.decode(data,localState:Data()){cipher,_ in cipher=="token" ? other:"fixture-machine"})
    }
    func testUnknownEncryptedFormatsAndForeignScopesAreNotReinterpreted() {
        XCTAssertNil(WindowsGrokCredential.decrypt(Data("v20unsupported".utf8).base64EncodedString(),localState:Data(),scope:nil))
        XCTAssertNil(WindowsGrokCredential.decrypt("scoped:v1:"+String(repeating:"a",count:64)+":YWJj",localState:Data(),scope:String(repeating:"b",count:64)))
        XCTAssertNil(WindowsGrokCredential.decode(Data("{\"cursor-accounts\":\"{}\"}".utf8),localState:Data()))
    }
}
#endif

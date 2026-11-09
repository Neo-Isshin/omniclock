#if os(macOS)
import XCTest
import Foundation
import CommonCrypto
@testable import TokenClock

final class ClaudeDesktopOAuthTests: XCTestCase {
    let owner="11111111-1111-4111-8111-111111111111"
    let org="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let other="22222222-2222-4222-8222-222222222222"
    let client="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    let now=Date(timeIntervalSince1970:1_900_000_000)
    let password="synthetic-test-only"
    func key(owner:String?=nil,org:String?=nil,host:String="https://api.anthropic.com",scopes:String="user:inference user:profile") -> String {
        "acct:\(owner ?? self.owner)|\(client):\(org ?? self.org):\(host):\(scopes)"
    }
    func data(_ value:Any) throws -> Data {try JSONSerialization.data(withJSONObject:value,options:.sortedKeys)}
    func token(_ name:String="synthetic-app-token",age:TimeInterval=3600) -> [String:Any] {
        ["token":name,"expiresAt":(now.timeIntervalSince1970+age)*1000]
    }
    func candidates(_ v2:[String:Any],v1:[String:Any]=[:],organization:String?=nil) throws -> [ClaudeDesktopOAuthReader.Candidate] {
        ClaudeDesktopOAuthReader.candidates(v2:try data(v2),v1:try data(v1),accountID:owner,organizationID:organization,now:now)
    }
    func encrypt(_ bytes:Data) throws -> String {
        let salt=Array("saltysalt".utf8);var key=[UInt8](repeating:0,count:16)
        let derived=password.withCString {CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),$0,password.utf8.count,salt,salt.count,CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),1003,&key,16)}
        XCTAssertEqual(derived,Int32(kCCSuccess))
        let iv=[UInt8](repeating:0x20,count:16);var result=[UInt8](repeating:0,count:bytes.count+16),length=0
        let status=bytes.withUnsafeBytes {CCCrypt(CCOperation(kCCEncrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(kCCOptionPKCS7Padding),key,16,iv,$0.baseAddress,bytes.count,&result,result.count,&length)}
        XCTAssertEqual(status,Int32(kCCSuccess))
        return (Data("v10".utf8)+Data(result.prefix(length))).base64EncodedString()
    }
    func fixture(_ cache:[String:Any]) throws -> (URL,URL) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeAppOAuth-"+UUID().uuidString)
        let desktop=URL(fileURLWithPath:ClaudeDesktopData.homes(home:root.path).first!)
        try FileManager.default.createDirectory(at:desktop,withIntermediateDirectories:true)
        let config=desktop.appendingPathComponent("config.json")
        try data(["lastKnownAccountUuid":owner,"oauth:tokenCacheV2":encrypt(data(cache))]).write(to:config)
        addTeardownBlock {try? FileManager.default.removeItem(at:root)}
        return (root,config)
    }
    func testPrefersCurrentAppCacheAndDoesNotReviveRevokedOrExpiredLegacyEntries() throws {
        let k=key(),old=try candidates([k:NSNull()],v1:[k:token()])
        XCTAssertTrue(old.isEmpty)
        XCTAssertTrue(try candidates([k:token(age:-1)],v1:[k:token()]).isEmpty)
        let current=try candidates([k:token("current")],v1:[k:token("legacy",age:7200)])
        XCTAssertEqual(current.map(\.credential.accessToken),["current"])
        XCTAssertEqual(try candidates([:],v1:[k:token()]).count,1)
    }
    func testChecksAccountScopeProductionHostAndRealExpiry() throws {
        let rows:[String:Any]=[key():token(),key(owner:other):token("other"),key(host:"https://untrusted.invalid"):token("wrong-host"),key(scopes:"user:inference"):token("no-profile")]
        XCTAssertEqual(try candidates(rows).map(\.credential.accessToken),["synthetic-app-token"])
        XCTAssertTrue(try candidates([key():["token":"bad\nheader","expiresAt":(now.timeIntervalSince1970+100)*1000]]).isEmpty)
        XCTAssertTrue(try candidates([key():["token":"synthetic","expiresAt":true]]).isEmpty)
        XCTAssertTrue(try candidates([key():token(age:0)]).isEmpty)
    }
    func testMultipleOrganizationsNeedTheSelectedOrganizationAndRequestsStayBounded() throws {
        let second="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        XCTAssertTrue(try candidates([key():token(),key(org:second):token("second")]).isEmpty)
        XCTAssertTrue(try candidates([key():token(age:-1),key(org:second):token("second")]).isEmpty)
        XCTAssertEqual(try candidates([key():token(),key(org:second):token("second")],organization:org).count,1)
        let rows=Dictionary(uniqueKeysWithValues:(1...4).map{(key(scopes:"user:profile user:inference extra\($0)"),token("candidate-\($0)",age:Double($0)*100))})
        XCTAssertEqual(try candidates(rows).map(\.credential.accessToken),["candidate-4","candidate-3"])
        XCTAssertTrue(ClaudeDesktopOAuthReader.candidates(v2:Data("broken".utf8),v1:try data([key():token()]),accountID:owner,now:now).isEmpty)
    }
    func testReadsEncryptedAppCacheWithoutCLIFilesAndNeverWritesIt() throws {
        let (_,config)=try fixture([key():token()]),before=try Data(contentsOf:config)
        let result=ClaudeDesktopOAuthReader.read(homes:[config.deletingLastPathComponent().path],now:now,password:{self.password})
        let candidate=try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(candidate.identity,.init(accountID:owner,organizationID:org))
        XCTAssertTrue(ClaudeDesktopOAuthReader.isCurrent(candidate))
        XCTAssertEqual(try Data(contentsOf:config),before)
        var changed=try XCTUnwrap(JSONSerialization.jsonObject(with:before) as? [String:Any]);changed["lastKnownAccountUuid"]=other
        try data(changed).write(to:config)
        XCTAssertFalse(ClaudeDesktopOAuthReader.isCurrent(candidate))
    }
    func testEmptyCacheDoesNotAskForAKeyAndAccountChangesDuringReadAreDiscarded() throws {
        let (_,config)=try fixture([:]);var keyReads=0
        let empty=ClaudeDesktopOAuthReader.read(homes:[config.deletingLastPathComponent().path],now:now,password:{keyReads+=1;return self.password})
        XCTAssertTrue(empty.candidates.isEmpty);XCTAssertEqual(keyReads,0)
        let (_,active)=try fixture([key():token()])
        let value=ClaudeDesktopOAuthReader.read(homes:[active.deletingLastPathComponent().path],now:now,password:{
            var changed=(try? JSONSerialization.jsonObject(with:Data(contentsOf:active))) as? [String:Any] ?? [:]
            changed["lastKnownAccountUuid"]=self.other
            try? self.data(changed).write(to:active)
            return self.password
        })
        XCTAssertTrue(value.candidates.isEmpty);XCTAssertTrue(value.sourceChanged)
    }
    func testWrongPasswordCannotFallBackToLegacyAndNonProductionTokensAreNotQueried() throws {
        let (_,config)=try fixture([key():token()])
        let result=ClaudeDesktopOAuthReader.read(homes:[config.deletingLastPathComponent().path],now:now,password:{"wrong-password"})
        XCTAssertTrue(result.decryptionFailed);XCTAssertTrue(result.candidates.isEmpty)
    }
    func testAppOnlyInstallationQueriesRealUsageSchemaWithoutCookieOrCLI() throws {
        let (root,config)=try fixture([key():token()]);let before=try Data(contentsOf:config)
        let calls=Requests();let account=owner,organization=org,password=self.password
        let service=ClaudeQuotaService(claudeHome:root.appendingPathComponent("no-cli").path,environment:[:],homeDirectory:root.path,oauthTransport:{request in
            calls.record(request)
            if request.url?.path.hasSuffix("/profile")==true {
                let value:[String:Any]=["account":["uuid":account],"organization":["uuid":organization,"organization_type":"claude_pro"]]
                return .init(statusCode:200,body:try! JSONSerialization.data(withJSONObject:value))
            }
            return .init(statusCode:200,body:Data(#"{"five_hour":{"utilization":12},"seven_day":{"utilization":34}}"#.utf8))
        },appPasswordReader:{password})
        let snapshot=service.fetch(connectedSession:nil,connectionSelected:false,now:now)
        XCTAssertEqual(snapshot.status,.available);XCTAssertEqual(snapshot.source,.desktopOAuth)
        XCTAssertEqual(snapshot.buckets.map(\.remainingPercent),[88,66])
        XCTAssertEqual(snapshot.verifiedIdentity,.init(accountID:owner,organizationID:org))
        XCTAssertFalse(snapshot.requiresConnection);XCTAssertFalse(snapshot.localAuthorizationRequired)
        XCTAssertEqual(calls.paths,["/api/oauth/profile","/api/oauth/usage"])
        XCTAssertTrue(calls.requests.allSatisfy{$0.httpMethod=="GET" && $0.url?.host=="api.anthropic.com"})
        XCTAssertEqual(try Data(contentsOf:config),before)
    }
    func testRateLimitStopsBeforeWebOrOtherCredentials() throws {
        let (root,_)=try fixture([key():token()]);let calls=Requests(),password=self.password
        let service=ClaudeQuotaService(claudeHome:root.appendingPathComponent("no-cli").path,environment:[:],homeDirectory:root.path,oauthTransport:{request in
            calls.record(request);return .init(statusCode:429,body:Data())
        },appPasswordReader:{password})
        let result=service.fetch(connectedSession:nil,connectionSelected:false,now:now)
        XCTAssertEqual(result.readFailure,.rateLimited);XCTAssertEqual(calls.paths,["/api/oauth/profile"])
    }
    func testLegacyUnprefixedGrantRequiresSameIdentityAndV2TombstoneWins() throws {
        let modern=key(),legacy=String(modern.split(separator:"|",maxSplits:1)[1])
        XCTAssertEqual(try candidates([:],v1:[legacy:token()]).first?.identity.accountID,owner)
        XCTAssertTrue(try candidates([modern:NSNull()],v1:[legacy:token()]).isEmpty)
    }
    func testMismatchedAppAndCodeAccountsCannotReturnAnotherAccountsQuota() throws {
        let (root,_)=try fixture([key():token()]);let calls=Requests(),other=self.other,organization=org,password=self.password
        let code=root.appendingPathComponent(".claude");try FileManager.default.createDirectory(at:code,withIntermediateDirectories:true)
        try data(["claudeAiOauth":["accessToken":"synthetic-other-code-token"]]).write(to:code.appendingPathComponent(".credentials.json"))
        let service=ClaudeQuotaService(claudeHome:code.path,environment:[:],homeDirectory:root.path,oauthTransport:{request in
            calls.record(request)
            return .init(statusCode:200,body:try! JSONSerialization.data(withJSONObject:["account":["uuid":other],"organization":["uuid":organization]]))
        },appPasswordReader:{password})
        var previous=ClaudeQuotaSnapshot(status:.available,buckets:[.init(id:"weekly",name:"Claude",usedPercent:99,windowMinutes:10080,resetsAt:nil)],planType:"pro",refreshedAt:now,source:.oauthAPI,message:nil)
        previous.verifiedIdentity = .init(accountID:other,organizationID:org)
        let result=service.fetch(connectedSession:nil,connectionSelected:false,previous:previous,now:now)
        XCTAssertEqual(result.status,.unavailable);XCTAssertEqual(result.readFailure,.wrongAccount)
        XCTAssertFalse(result.isCachedFallback);XCTAssertTrue(result.buckets.isEmpty)
        XCTAssertFalse(calls.paths.contains("/api/oauth/usage"))
    }
    func testExpiredCodeFileDoesNotMaskTheNextFreshCredential() throws {
        let (root,_)=try fixture([:]);let code=root.appendingPathComponent("expired-code"),fresh=root.appendingPathComponent(".claude")
        for p in [code,fresh]{try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true)}
        try data(["claudeAiOauth":["accessToken":"expired-synthetic","expiresAt":1000]]).write(to:code.appendingPathComponent(".credentials.json"))
        try data(["claudeAiOauth":["accessToken":"fresh-synthetic","expiresAt":now.addingTimeInterval(3600).timeIntervalSince1970*1000]]).write(to:fresh.appendingPathComponent(".credentials.json"))
        let calls=Requests(),account=owner,organization=org
        let service=ClaudeQuotaService(claudeHome:code.path,environment:[:],homeDirectory:root.path,oauthTransport:{request in
            calls.record(request)
            if request.url?.path.hasSuffix("/profile")==true{return .init(statusCode:200,body:try! JSONSerialization.data(withJSONObject:["account":["uuid":account],"organization":["uuid":organization]]))}
            return .init(statusCode:200,body:Data(#"{"five_hour":{"utilization":10},"seven_day":{"utilization":20}}"#.utf8))
        },appPasswordReader:{nil})
        let result=service.fetch(connectedSession:nil,connectionSelected:false,now:now)
        XCTAssertEqual(result.status,.available)
        XCTAssertTrue(calls.requests.allSatisfy{$0.value(forHTTPHeaderField:"Authorization")=="Bearer fresh-synthetic"})
    }
    func testAccountSwitchDuringRequestNeverDisplaysPreviousSnapshot() throws {
        let (root,config)=try fixture([key():token()]);let account=owner,organization=org,password=self.password,other=self.other
        let service=ClaudeQuotaService(claudeHome:root.appendingPathComponent("no-cli").path,environment:[:],homeDirectory:root.path,oauthTransport:{request in
            if request.url?.path.hasSuffix("/profile")==true {
                return .init(statusCode:200,body:try! JSONSerialization.data(withJSONObject:["account":["uuid":account],"organization":["uuid":organization]]))
            }
            var changed=(try! JSONSerialization.jsonObject(with:Data(contentsOf:config))) as! [String:Any]
            changed["lastKnownAccountUuid"]=other
            try! JSONSerialization.data(withJSONObject:changed).write(to:config)
            return .init(statusCode:200,body:Data(#"{"five_hour":{"utilization":10},"seven_day":{"utilization":20}}"#.utf8))
        },appPasswordReader:{password})
        var previous=ClaudeQuotaSnapshot(status:.available,buckets:[.init(id:"weekly",name:"Claude",usedPercent:20,windowMinutes:10080,resetsAt:nil)],planType:"pro",refreshedAt:now,source:.desktopOAuth,message:nil)
        previous.verifiedIdentity = .init(accountID:owner,organizationID:org)
        let result=service.fetch(connectedSession:nil,connectionSelected:false,previous:previous,now:now)
        XCTAssertEqual(result.readFailure,.sourceChanged);XCTAssertEqual(result.status,.unavailable)
        XCTAssertFalse(result.isCachedFallback);XCTAssertTrue(result.buckets.isEmpty)
        XCTAssertFalse(result.requiresConnection)
    }
    func testCredentialExpiryUsesStoredDeadlineWithoutReadingARefreshToken() throws {
        let result=try XCTUnwrap(ClaudeQuotaService.decodeCredentialPayload(try data(["claudeAiOauth":["accessToken":"synthetic","expiresAt":1_900_000_000_000,"refreshToken":"never-use"]])))
        XCTAssertEqual(result.expiresAt,now)
        XCTAssertNil(ClaudeQuotaService.decodeCredentialPayload(try data(["claudeAiOauth":["accessToken":"synthetic","expiresAt":true]])))
    }
    final class Requests: @unchecked Sendable {
        let lock=NSLock();private var values:[URLRequest]=[]
        func record(_ request:URLRequest){lock.lock();values.append(request);lock.unlock()}
        var requests:[URLRequest]{lock.lock();defer{lock.unlock()};return values}
        var paths:[String]{requests.compactMap{$0.url?.path}}
    }
}
#endif

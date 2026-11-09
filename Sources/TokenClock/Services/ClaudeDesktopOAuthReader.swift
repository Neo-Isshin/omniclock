#if os(macOS)
import Foundation
import CryptoKit
import CoreFoundation

/// Claude Desktop's own OAuth cache, also used by its embedded Code engine.
/// Reads only config.json; never starts Code, refreshes tokens, or writes App state.
enum ClaudeDesktopOAuthReader {
    struct Candidate: Equatable, Sendable {
        let credential: ClaudeQuotaService.CredentialInfo
        let identity: ClaudeQuotaIdentity
        fileprivate var configPath: String = ""
        fileprivate var fingerprint: Data = Data()
    }
    struct ReadResult {
        var candidates: [Candidate] = []
        var decryptionFailed = false
        var sourceChanged = false
    }
    private static let maximumBytes = 1_048_576
    private static let cacheKeys = ["oauth:tokenCacheV2", "oauth:tokenCache"]

    static func read(homes: [String], expected: ClaudeQuotaIdentity? = nil, now: Date = Date(),
                     password: () -> String?) -> ReadResult {
        for home in homes {
            let path = (home as NSString).appendingPathComponent("config.json")
            guard let config = configuration(path), let owner = account(config),
                  expected == nil || expected?.accountID == owner else { continue }
            if cacheKeys.contains(where:{config[$0] != nil && !(config[$0] is String)}) {return ReadResult()}
            let encrypted = cacheKeys.map { config[$0] as? String }
            // An encrypted empty object has one AES block. There cannot be a token entry in it.
            guard encrypted.contains(where: { value in
                guard let value, let bytes = Data(base64Encoded: value) else { return false }
                return bytes.count > 19 && bytes.prefix(3) == Data("v10".utf8)
            }), let key = password() else { return ReadResult() }
            var caches: [String: Data] = [:]
            for (index, value) in encrypted.enumerated() {
                guard let value,!value.isEmpty else {continue}
                guard let bytes = Data(base64Encoded: value), bytes.count <= maximumBytes,
                      let text = ClaudeAppCookieReader.decrypt(bytes, password:key, host:"", schema:23) else {
                    return ReadResult(decryptionFailed:true)
                }
                caches[cacheKeys[index]] = Data(text.utf8)
            }
            let stamp = fingerprint(config)
            guard let current = configuration(path), fingerprint(current) == stamp else { return ReadResult(sourceChanged:true) }
            let choices = candidates(v2:caches[cacheKeys[0]], v1:caches[cacheKeys[1]], accountID:owner,
                              organizationID:expected?.organizationID, now:now).map {
                var value=$0;value.configPath=path;value.fingerprint=stamp;return value
            }
            return ReadResult(candidates:choices)
        }
        return ReadResult()
    }

    static func isCurrent(_ candidate: Candidate) -> Bool {
        guard let config=configuration(candidate.configPath) else{return false}
        return account(config)==candidate.identity.accountID && fingerprint(config)==candidate.fingerprint
    }

    /// The official App keys entries by account, client, organization, API host and scope.
    /// Keep v2 tombstones/expired entries authoritative over an older copy in v1.
    static func candidates(v2: Data?, v1: Data?, accountID: String, organizationID: String? = nil,
                           now: Date) -> [Candidate] {
        guard UUID(uuidString:accountID) != nil else{return []}
        func object(_ data: Data?) -> [String:Any]? {
            guard let data,data.count<=maximumBytes,
                  let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any],value.count<=256 else{return nil}
            return value
        }
        // A malformed current cache must not revive a legacy credential.
        if v2 != nil && object(v2)==nil{return []}
        let current=object(v2) ?? [:],legacy=object(v1) ?? [:]
        // An expired grant can still identify another App organization. Do not
        // silently substitute a different organization just because its token is fresh.
        if organizationID == nil {
            let organizations=Set((Array(current.keys)+Array(legacy.keys)).compactMap { raw -> String? in
                guard let value=route(raw,accountID:accountID),value.identity.accountID==accountID.lowercased() else{return nil}
                return value.identity.organizationID
            })
            guard organizations.count<=1 else{return []}
        }
        let shadowed=Set(current.keys.compactMap{route($0,accountID:accountID)?.grantKey})
        var rows:[(Candidate,Int)]=[]
        for (cache,priority) in [(current,0),(legacy,1)] {
            for (raw,value) in cache {
                guard let route=route(raw,accountID:accountID) else{continue}
                if priority==1 && shadowed.contains(route.grantKey) {continue}
                guard route.identity.accountID==accountID.lowercased(),
                      organizationID == nil || route.identity.organizationID==organizationID?.lowercased(),
                      route.scopes.contains("user:profile"),let entry=value as? [String:Any],
                      let token=entry["token"] as? String,!token.isEmpty,token.utf8.count<=16_384,
                      !token.unicodeScalars.contains(where:{$0.value<=32 || $0.value==127}),
                      let expires=entry["expiresAt"] as? NSNumber,
                      CFGetTypeID(expires) != CFBooleanGetTypeID(),expires.doubleValue.isFinite,
                      expires.doubleValue/1000 > now.timeIntervalSince1970 else{continue}
                let credential=ClaudeQuotaService.CredentialInfo(accessToken:token,
                    subscriptionType:entry["subscriptionType"] as? String,
                    rateLimitTier:entry["rateLimitTier"] as? String,
                    expiresAt:Date(timeIntervalSince1970:expires.doubleValue/1000))
                rows.append((Candidate(credential:credential,identity:route.identity),priority))
            }
        }
        // One App account can belong to several organizations with different quotas.
        guard Set(rows.map{$0.0.identity.organizationID}).count<=1 else{return []}
        rows.sort { lhs,rhs in
            if lhs.1 != rhs.1 {return lhs.1<rhs.1}
            return (lhs.0.credential.expiresAt ?? .distantPast) > (rhs.0.credential.expiresAt ?? .distantPast)
        }
        var seen=Set<String>()
        return Array(rows.compactMap { seen.insert($0.0.credential.accessToken).inserted ? $0.0:nil }.prefix(2))
    }

    private static func route(_ key: String, accountID: String) -> (identity:ClaudeQuotaIdentity,scopes:Set<String>,grantKey:String)? {
        guard key.utf8.count<=1024 else{return nil}
        let owner:String,suffix:String
        if key.hasPrefix("acct:") {
            guard let pipe=key.firstIndex(of:"|") else{return nil}
            owner=String(key[key.index(key.startIndex,offsetBy:5)..<pipe])
            suffix=String(key[key.index(after:pipe)...])
        } else {
            // Before account-prefixed caches, the selected App account supplied this
            // hint. The API profile must still confirm both identifiers before use.
            owner=accountID;suffix=key
        }
        let marker=":https://api.anthropic.com:"
        guard let split=suffix.range(of:marker),UUID(uuidString:owner) != nil else{return nil}
        let ids=suffix[..<split.lowerBound].split(separator:":",omittingEmptySubsequences:false)
        guard ids.count==2,UUID(uuidString:String(ids[0])) != nil,UUID(uuidString:String(ids[1])) != nil else{return nil}
        let scopes=Set(suffix[split.upperBound...].split(separator:" ").map(String.init))
        let identity=ClaudeQuotaIdentity(accountID:owner,organizationID:String(ids[1]))
        let grantKey=identity.key+"|"+ids[0].lowercased()+"|"+scopes.sorted().joined(separator:" ")
        return (identity,scopes,grantKey)
    }
    private static func account(_ value:[String:Any]) -> String? {
        guard let text=value["lastKnownAccountUuid"] as? String,UUID(uuidString:text) != nil else{return nil}
        return text.lowercased()
    }
    private static func configuration(_ path:String) -> [String:Any]? {
        guard let attributes=try? FileManager.default.attributesOfItem(atPath:path),
              let size=attributes[.size] as? NSNumber,size.intValue<=maximumBytes,
              let data=FileManager.default.contents(atPath:path),data.count<=maximumBytes else{return nil}
        return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
    }
    private static func fingerprint(_ config:[String:Any]) -> Data {
        let selected=["account":account(config) ?? "","v2":config[cacheKeys[0]] as? String ?? "","v1":config[cacheKeys[1]] as? String ?? ""]
        return Data(SHA256.hash(data:(try? JSONSerialization.data(withJSONObject:selected,options:.sortedKeys)) ?? Data()))
    }
}
#endif

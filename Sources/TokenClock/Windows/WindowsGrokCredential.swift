import Foundation
import Win32Shim

/// Electron's documented Windows DPAPI/AES-GCM storage; never reads or changes
/// another Windows user's key material or bypasses app-bound encryption.
enum WindowsGrokCredential {
    static func decode(_ data: Data, localState: Data, decrypt: ((String, String?) -> String?)? = nil) -> GrokBotNativeCredential? {
        guard data.count<=4_194_304,let root=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return nil}
        let account:[String:Any],scope:String?
        if let text=root["cursor-accounts"] as? String {
            guard let envelope=(try? JSONSerialization.jsonObject(with:Data(text.utf8))) as? [String:Any],let active=envelope["active"] as? String,
                  let accounts=envelope["accounts"] as? [String:Any],let selected=accounts[active] as? [String:Any] else{return nil}
            account=selected;scope=active
        } else if root["cursor-accounts"]==nil {account=root;scope=nil} else{return nil}
        let decode=decrypt ?? { secret,scope in self.decrypt(secret,localState:localState,scope:scope) }
        guard let cipher=account["cursor-access-token"] as? String,let token=decode(cipher,scope),
              scope == nil || GrokBotNativeCredentialStore.accountScope(for:token)==scope,
              let userID=CursorQuotaService.userID(from:token),let machineCipher=root["cursor-machine-id"] as? String,
              let machine=decode(machineCipher,scope),!machine.isEmpty else{return nil}
        var email:String?
        if let cipher=account["cursor-account-profile"] as? String,let value=decode(cipher,scope),
           let profile=(try? JSONSerialization.jsonObject(with:Data(value.utf8))) as? [String:Any] {email=profile["email"] as? String}
        return .init(accessToken:token,userID:userID,email:email,machineID:machine)
    }
    static func decrypt(_ value: String, localState: Data, scope: String?) -> String? {
        var payload=value
        if payload.hasPrefix("scoped:v1:") {
            let parts=payload.split(separator:":",maxSplits:3,omittingEmptySubsequences:false)
            guard parts.count==4,let scope,parts[2]==scope,scope.count==64,scope.allSatisfy({$0.isHexDigit && !$0.isUppercase}) else{return nil}
            payload=String(parts[3])
        }
        guard let cipher=Data(base64Encoded:payload),!cipher.isEmpty,cipher.count<=65536 else{return nil}
        var key=Data()
        if localState.count<=4_194_304,let state=(try? JSONSerialization.jsonObject(with:localState)) as? [String:Any],
           let crypto=state["os_crypt"] as? [String:Any],let encoded=crypto["encrypted_key"] as? String,let bytes=Data(base64Encoded:encoded),bytes.count<=65536 {key=bytes}
        var output=[UInt8](repeating:0,count:cipher.count),written:Int32=0
        defer {output.withUnsafeMutableBytes{$0.initializeMemory(as:UInt8.self,repeating:0)}}
        let success=cipher.withUnsafeBytes { input in key.withUnsafeBytes { key in
            win_decrypt_electron_secret(input.bindMemory(to:UInt8.self).baseAddress,Int32(input.count),key.bindMemory(to:UInt8.self).baseAddress,Int32(key.count),&output,Int32(output.count),&written)
        }}
        guard success != 0,written>0,Int(written)<=output.count,let text=String(bytes:output.prefix(Int(written)),encoding:.utf8),!text.isEmpty else{return nil}
        return text
    }
}

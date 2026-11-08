import Foundation
import WinWebView
import Win32Shim

/// Windows 入口（镜像 Linux/LinuxMain.swift）。
@main
struct TokenClockWindowsMain {
    static func main() {
        WindowsTimeZone.configure()
        omni_web_initialize()
        let arguments = CommandLine.arguments
        if let i=arguments.firstIndex(of:"--restart-wait"),arguments.indices.contains(i+1),let pid=UInt32(arguments[i+1]),win_wait_for_parent(pid)==0 {exit(2)}
        if let i=arguments.firstIndex(of:"--time-zone-report"),arguments.indices.contains(i+1){
            let report:[String:Any]=["systemIdentifier":WindowsTimeZone.systemIdentifier() ?? "","foundationIdentifier":TimeZone.current.identifier,"defaultIdentifier":NSTimeZone.default.identifier,"today":DateHelper.todayKey(),"hour":DateHelper.currentHourKey(),"display":Date().formatted(date:.numeric,time:.shortened)]
            do{try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:URL(fileURLWithPath:arguments[i+1]),options:.atomic)}catch{exit(2)}
            return
        }
        if let i=arguments.firstIndex(of:"--grok-native-report"),arguments.indices.contains(i+1) {
            let store=GrokBotNativeCredentialStore.shared
            let present=store.hasSignedInInstance,read=store.currentCredential != nil
            let metadata=WindowsQuotaProbeMetadata()
            let quota=GrokBotQuotaService(transport:{ request in
                guard let url=request.url else{return nil}
                do {
                    let response=try WindowsNativeHTTP.request(url:url.absoluteString,method:request.httpMethod ?? "POST",headers:request.allHTTPHeaderFields ?? [:],body:request.httpBody,connectTimeout:8,sendTimeout:8,receiveTimeout:15)
                    metadata.record(status:response.statusCode,mime:response.mimeType,error:nil)
                    return GrokBotQuotaService.HTTPResponse(statusCode:response.statusCode,data:response.body)
                } catch {metadata.record(status:nil,mime:nil,error:String(describing:error));return nil}
            }).fetch()
            var report:[String:Any] = ["signedIn":present,"credentialReadable":read,"status":String(describing:quota.status),"source":quota.source,"message":quota.message ?? "","requests":metadata.values(),"authorizationRequired":quota.requiresLocalAuthorization,"sharedSubscription":XSubscriptionQuota.contains(quota.groups),"buckets":quota.groups.flatMap(\.buckets).map{["name":$0.name,"remaining":$0.remainingPercent,"windowMinutes":$0.windowMinutes] as [String:Any]}]
            if let token=store.currentCredential?.accessToken {
                report["hasUserPrefix"]=token.contains("::")
                let pieces=token.components(separatedBy:".")
                if pieces.count==3 {
                    var body=pieces[1].replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
                    while body.count%4 != 0 {body+="="}
                    if let bytes=Data(base64Encoded:body),let claims=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],let expiration=(claims["exp"] as? NSNumber)?.doubleValue {
                        report["tokenExpired"]=expiration<Date().timeIntervalSince1970
                        report["expiresAt"]=ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:expiration))
                    }
                }
            }
            do {try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:URL(fileURLWithPath:arguments[i+1]),options:.atomic)}catch{exit(2)}
            return
        }
        if let flag = arguments.firstIndex(of: "--catalog-report"), arguments.indices.contains(flag + 1) {
            do {
                try WindowsProviderCatalog.writeDiagnosticReport(to: arguments[flag + 1])
            } catch {
                // GUI-subsystem builds do not have a reliable console, so use a deterministic
                // nonzero exit status; smoke tests inspect the requested output file as well.
                exit(2)
            }
            return
        }
        WindowsApp.shared.run()
    }
}

private final class WindowsQuotaProbeMetadata: @unchecked Sendable {
    private let lock=NSLock()
    private var rows:[[String:Any]]=[]
    func record(status:Int?,mime:String?,error:String?){lock.lock();defer{lock.unlock()};rows.append(["status":status as Any? ?? NSNull(),"contentType":mime ?? "","error":error ?? ""])}
    func values()->[[String:Any]]{lock.lock();defer{lock.unlock()};return rows}
}

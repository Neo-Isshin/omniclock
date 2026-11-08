#if os(Windows)
import Foundation
import Win32Shim
import WinWebView

enum WindowsToolboxMessageScope {
    static func permitsLocalCommand(page: String) -> Bool {
        ["details","summary","local","notebook","quick","notifications","notices","news","share","modelError"].contains(page)
    }
}
@MainActor final class WindowsToolboxes {
    let content: UserContentCenter
    let local: LocalToolboxModel
    private var newsWindow: String?
    init() {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? NSHomeDirectory()).appendingPathComponent("TokenClock")
        content = UserContentCenter(defaults: WindowsDurableDefaults.persistent, notebookURL: root.appendingPathComponent("notebook.json"))
        local = LocalToolboxModel(directory: root)
        content.news.isPresentationVisible = { [weak self] in guard let self,let key=self.newsWindow else{return false};return self.isVisible(key) }
    }
    let mainland = MainlandReachabilityModel()
    var stateProvider: () -> [String: Any] = { [:] }
    var navigate: (String, [String: Any]) -> Void = { _, _ in }
    var onContentChange: (() -> Void)?
    private var windows: [String: UnsafeMutableRawPointer] = [:]
    private var lastJSON: [String: String] = [:]
    private var networkTask: Task<Void, Never>?
    private var networkFetcher: NetworkDiagnosticFetcher?
    private var networkID: String?
    private var historyTask: Task<Void, Never>?
    private var hourly = StatusSummaryHourlyData.empty(day: "")
    private var previous = StatusSummaryHourlyData.empty(day: "")
    private var comparison = StatusSummaryComparisonData()
    private var lastHistoryReload = Date.distantPast
    private var lastMainland = ""
    private var shareData: [String: Any] = [:]
    private var modelError = ""
    private var exportStatus = ""
    private var selectedNote: UUID?
    private var showCompleted = false
    private var tools: [ToolUsage] = []
    private var quotas: [StatusSummaryQuota] = []
    private var summaryModels = false
    private var expandedHours = false
    private var shareTask: Task<Void, Never>?
    private var shareGeneration = UUID()
    private let profile = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? NSHomeDirectory()).appendingPathComponent("TokenClock/WebView2")
    private var assets: URL { Bundle.module.resourceURL!.appendingPathComponent("WindowsUI") }
    private lazy var callbackContext = Unmanaged.passUnretained(self).toOpaque()

    func start() { content.onChange = { [weak self] in self?.onContentChange?(); self?.publish() }; content.start() }
    func stop() {
        content.stop(); local.stop(); mainland.stop(); networkTask?.cancel(); networkFetcher?.cancel(); historyTask?.cancel(); shareTask?.cancel()
        ModelIntegrityLauncher.shared.stop()
        for handle in Array(windows.values) { omni_web_close(handle) }; windows.removeAll()
    }
    func refreshLocalization() {
        let visible=windows.keys.filter{isVisible($0)}
        content.notebook.flush()
        for key in Array(windows.keys){hide(key)}
        for key in visible{show(key)}
    }
    func isVisible(_ key: String) -> Bool { windows[key].map { omni_web_visible($0) != 0 } ?? false }
    func hide(_ key: String) { if let handle = windows[key] { omni_web_close(handle) }; windows.removeValue(forKey: key); lastJSON.removeValue(forKey: key) }
    func show(_ key: String) {
        if key == "model" { showModel(); return }
        if let handle = windows[key] { omni_web_show(handle,1); publish(); return }
        let zh = L10n.shared.language.rawValue.hasPrefix("zh")
        let title = title(key)
        let url = key == "network" ? "https://www.ailyre.com/tokenclock/network-check/?lang=\(zh ? "zh-CN":"en")&embedded=1#run" : "https://omniclock.local/index.html?page=\(key)&lang=\(zh ? "zh-CN":"en")"
        let script = key == "network" ? ((try? String(contentsOf: assets.appendingPathComponent("network-bridge.js"), encoding:.utf8)) ?? "") : ""
        let preferred: (Int32, Int32) = key == "details" ? (380,640) : key == "summary" ? (760,720) : key == "notebook" ? (760,620) : (800,700)
        let store=WindowsPreferences.shared
        let savedWidth=store.integer(forKey:"window."+key+".width"),savedHeight=store.integer(forKey:"window."+key+".height")
        let dimensions=(savedWidth>0 ? Int32(clamping:max(320,savedWidth)):preferred.0,savedHeight>0 ? Int32(clamping:max(320,savedHeight)):preferred.1)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories:true)
        if let handle = omni_web_open(key,title,assets.path,profile.path,url,script,dimensions.0,dimensions.1,windowsToolboxMessage,callbackContext) {
            windows[key]=handle
            if key == "details" || key == "summary" { omni_web_anchor(handle,win_self()) }
        }
        if key == "summary" { reloadHistory() }
        if key == "share" { loadShare([:]) }
        if key == "news" { newsWindow=key;content.news.setViewing(true) }
        publish()
    }
    private func title(_ key: String) -> String {
        switch key {
        case "details":return "OmniClock"
        case "summary":return toolboxText("今日总结", "Today at a glance")
        case "network":return toolboxText("网络工具箱", "Network Toolbox")
        case "local":return toolboxText("本地工具箱", "Local Tools")
        case "notebook":return toolboxText("行事本", "Notebook")
        case "quick":return toolboxText("快捷按钮", "Quick actions")
        case "notices":return toolboxText("通知", "Notifications")
        case "notifications":return toolboxText("通知设置", "Notification settings")
        case "news":return toolboxText("Ailyre AI 速递", "Ailyre AI digest")
        case "share":return toolboxText("分享用量", "Share usage")
        default:return toolboxText("模型检测", "Model Detect")
        }
    }
    func update(tools: [ToolUsage], quotas: [StatusSummaryQuota]) {
        self.tools=tools;self.quotas=quotas
        if isVisible("summary"), Date().timeIntervalSince(lastHistoryReload)>60 { reloadHistory() }
        publish(); publishMainland()
    }
    private func date(_ value: Date?) -> String { value.map { $0.formatted(Date.FormatStyle(date:.abbreviated,time:.shortened).locale(Locale(identifier:L10n.shared.language.rawValue))) } ?? "—" }
    private func resetDate(_ value: Date?) -> String {
        guard let value else{return "—"}
        let formatter=DateFormatter();formatter.locale=Locale(identifier:L10n.shared.language.rawValue);formatter.timeZone=TimeZone.current;formatter.dateFormat="MM/dd HH:mm"
        return formatter.string(from:value)
    }
    private func payload() -> [String: Any] {
        var result=stateProvider()
        result["language"]=L10n.shared.language.rawValue
        result["title"]="OmniClock"
        result["quickOrder"]=QuickToolPreferences.shared.order.map(\.rawValue)
        result["allQuick"]=QuickTool.allCases.map { ["id":$0.rawValue,"title":$0.title,"hint":$0.hint] }
        result["news"]=content.news.items.map { item in
            ["id":item.id,"title":item.title,"summary":item.summary,"url":item.url.absoluteString,"logo":item.logoURL?.absoluteString ?? "","track":item.track?.rawValue ?? "","date":date(item.publishedAt)]
        }
        result["newsStatus"]=(content.news.loading ? toolboxText("正在更新…", "Updating…") : content.news.errorMessage)
        result["notebook"]=content.notebook.entries.filter { showCompleted || !$0.completed }.map { item -> [String:Any] in
            ["id":item.id.uuidString,"title":item.title,"body":item.body,"completed":item.completed,"reminder":item.remindAt?.timeIntervalSince1970 as Any? ?? NSNull(),"updated":date(item.updatedAt)]
        }
        result["selectedNote"]=selectedNote?.uuidString ?? content.notebook.selectedID?.uuidString ?? ""
        result["noteError"]=content.notebook.errorMessage
        result["showCompleted"]=showCompleted
        result["notificationEnabled"]=content.preferences.configuration.enabled
        result["categories"]=NotificationCategory.allCases.map { ["id":$0.rawValue,"title":$0.title,"enabled":content.preferences.configuration.categories.contains($0)] as [String:Any] }
        result["local"]=["mode":local.selectedMode,"busy":local.busy,"status":LocalToolboxResultText.status(local.status),"checked":date(local.checkedAt),"error":local.cacheError,
            "findings":local.findings.map { ["title":$0.localizedTitle,"detail":$0.localizedDetail,"path":$0.path ?? ""] },
            "keys":local.keys.map { ["source":$0.source,"endpoint":$0.endpoint,"masked":$0.masked,"status":$0.localizedStatus] },
            "files":local.files.map { ["path":$0.path,"tool":$0.tool,"size":ByteCountFormatter.string(fromByteCount:$0.size,countStyle:.file),"eligible":$0.eligible] as [String:Any] }]
        let includes=UserDefaults.standard.bool(for:.usageIncludesCacheRead)
        let snapshot=StatusSummarySnapshot(tools:tools,includesCache:includes)
        let change=comparison.compare(to:snapshot.rankedTools,includesCache:includes)
        let hours=hourly.chartHours(expanded:expandedHours,currentHour:Calendar.current.component(.hour,from:Date()),previous:previous)
        let partialHours=hourly.hours.reduce(0){$0+$1.displayedTokens(includingCache:includes)} != snapshot.totalTokens || (includes && hours.contains{!$0.usage.cacheIsExact})
        let summaryRows:[[String:Any]]
        if summaryModels {
            summaryRows=UsageAggregator.groupedByModel(snapshot.rankedTools,unknownLabel:L10n.shared.tr("detail.unknownModel")).map { ["name":$0.name,"tokens":TokenFormat.compact($0.totalTokens+(includes ? $0.totalCacheReadTokens:0)),"cost":CostFormat.estimate($0.totalCost),"speed":$0.generationSpeed.formatted] }
        } else {
            summaryRows=snapshot.rankedTools.map { ["name":$0.name,"tokens":TokenFormat.compact(snapshot.tokens(for:$0)),"cost":CostFormat.estimate($0.todayCost),"speed":GenerationSpeedStore.shared.summary(provider:$0.name).formatted] }
        }
        result["summary"]=["tokens":TokenFormat.compact(snapshot.totalTokens),"messages":snapshot.totalMessages,"cache":snapshot.cacheShare.map { String(format:"%.0f%%",$0*100) } ?? "—",
            "comparison":change.tokenDelta?.percent.map { String(format:"%+.1f%%",$0) } ?? "—","comparisonPartial":change.isPartial,"partialHours":partialHours,"cacheIncluded":includes,"expandedHours":expandedHours,"models":summaryModels,
            "hours":hours.map { ["hour":$0.usage.hour,"tokens":$0.usage.displayedTokens(includingCache:includes)] },"rows":summaryRows,
            "quotas":quotas.map { quota -> [String:Any] in
                ["provider":quota.provider.rawValue,"name":quota.displayName,"account":quota.accountName ?? "","outer":quota.indicator.outerRemainingPercent,"inner":quota.indicator.innerRemainingPercent as Any? ?? NSNull(),"third":quota.indicator.thirdRemainingPercent as Any? ?? NSNull(),"resets":quota.resets.map { ["title":$0.title.replacingOccurrences(of:"5-hour",with:"5h"),"date":resetDate($0.resetsAt),"at":$0.resetsAt?.timeIntervalSince1970 as Any? ?? NSNull()] as [String:Any] },"details":quota.details.map { ["title":L10n.shared.tr($0.labelKey),"percent":$0.remainingPercent] as [String:Any] }]
            }]
        result["share"]=shareData;result["exportStatus"]=exportStatus;result["modelError"]=modelError
        return result
    }
    func setDetailOpacity(_ value: Double) {
        if let window=windows["details"] {omni_web_opacity(window,value)}
    }
    func publish() {
        guard windows.keys.contains(where: { $0 != "network" && $0 != "model" }) else { return }
        guard let bytes=try? JSONSerialization.data(withJSONObject:payload(),options:[.sortedKeys]),let json=String(data:bytes,encoding:.utf8) else { return }
        for (key,handle) in windows where key != "network" && key != "model" && omni_web_visible(handle) != 0 {
            if lastJSON[key] != json { lastJSON[key]=json;omni_web_send(handle,json) }
        }
    }
    private func reloadHistory() {
        lastHistoryReload=Date();historyTask?.cancel();let names=Set(tools.map(\.name));let day=DateHelper.todayKey()
        historyTask=Task { [weak self] in
            let rows=await Task.detached(priority:.utility) { () -> (StatusSummaryHourlyData,StatusSummaryHourlyData,StatusSummaryComparisonData) in
                let previous=StatusSummaryComparisonData.previousDay(day) ?? ""
                let today=HourlyHistoryStore.shared.query(day:day),yesterday=HourlyHistoryStore.shared.query(day:previous)
                return (.build(today,day:day,tools:names),.build(yesterday,day:previous,tools:names),.build(day:day,today:today,yesterday:yesterday,daily:HistoryStore.shared.query(from:previous,through:previous)))
            }.value
            guard let self,!Task.isCancelled else{return};self.hourly=rows.0;self.previous=rows.1;self.comparison=rows.2;self.publish()
        }
    }
    private func showModel() {
        modelError=toolboxText("正在启动模型检测…", "Starting model detection…")
        ModelIntegrityLauncher.shared.start { [weak self] result in Task { @MainActor in
            guard let self else{return}
            switch result {
            case .success(let url):
                if let handle=self.windows["model"]{omni_web_show(handle,1);return}
                if let handle=omni_web_open("model",self.title("model"),self.assets.path,self.profile.path,url.absoluteString,"",1040,780,windowsToolboxMessage,self.callbackContext){self.windows["model"]=handle}
            case .failure(let error):self.modelError=error.localizedDescription;self.show("modelError")
            }
        }}
    }
    func handle(key: String, message: [String:Any], fromPage: Bool = false) {
        if !fromPage, let event=message["event"] as? String {
            if event=="sizeChanged",let width=message["width"] as? Int,let height=message["height"] as? Int {
                WindowsPreferences.shared.set(width,forKey:"window."+key+".width");WindowsPreferences.shared.set(height,forKey:"window."+key+".height");return
            }
            if event=="ready" { lastJSON.removeValue(forKey:key);lastMainland="";publish();publishMainland();return }
            if event=="hidden" || event=="closed" {
                if key=="network" { networkTask?.cancel();networkFetcher?.cancel();networkID=nil;mainland.stop() }
                if key=="news" || key=="details" { content.news.setViewing(false) }
                if key=="local" { local.stop() }
                if key=="summary" { historyTask?.cancel() }
                if key=="notebook" {content.notebook.flush()}
                if event=="hidden" { hide(key) } else { windows.removeValue(forKey:key);lastJSON.removeValue(forKey:key) }
                navigate("closed",["key":key]);return
            }
            if event=="error" { modelError=message["message"] as? String ?? "WebView2 unavailable";return }
        }
        if key=="network" {
            guard let channel=message["channel"] as? String else{return}
            if channel=="network",let body=message["body"] as? [String:Any] { diagnostic(body) }
            if channel=="mainland" {
                if message["action"] as? String=="stop" { mainland.stop() }
                else { mainland.targetIP=message["ip"] as? String ?? "";mainland.targetPort=message["port"] as? String ?? "443";mainland.start() }
                publishMainland()
            }
            if channel=="browser" { win_open_url("https://www.ailyre.com/tokenclock/network-check/?lang="+L10n.shared.language.rawValue) }
            return
        }
        guard WindowsToolboxMessageScope.permitsLocalCommand(page:key),let command=message["command"] as? String else{return}
        let data=message["data"] as? [String:Any] ?? [:]
        switch command {
        case "open":
            let tool=data["tool"] as? String ?? ""
            if ["network","local","model","notebook","share","quick","notifications","news","summary"].contains(tool){show(tool)}else{navigate(tool,data)}
        case "quickToggle":if let tool=QuickTool(rawValue:data["id"] as? String ?? ""){QuickToolPreferences.shared.toggle(tool)}
        case "quickMove":if let tool=QuickTool(rawValue:data["id"] as? String ?? ""){QuickToolPreferences.shared.move(tool,by:data["step"] as? Int ?? 0)}
        case "quickMoveTo":if let item=QuickTool(rawValue:data["id"] as? String ?? ""),let target=QuickTool(rawValue:data["target"] as? String ?? ""){QuickToolPreferences.shared.move(item,to:target)}
        case "quickReset":QuickToolPreferences.shared.order=QuickToolPreferences.defaults
        case "notificationEnabled":content.preferences.setEnabled(data["enabled"] as? Bool ?? true)
        case "notificationCategory":if let category=NotificationCategory(rawValue:data["id"] as? String ?? ""){content.preferences.set(category,enabled:data["enabled"] as? Bool ?? true)}
        case "noteAdd":selectedNote=content.notebook.add();show("notebook")
        case "noteSelect":selectedNote=(data["id"] as? String).flatMap(UUID.init(uuidString:));show("notebook")
        case "noteEdit":if let id=(data["id"] as? String).flatMap(UUID.init(uuidString:)){content.notebook.update(id,title:data["title"] as? String,body:data["body"] as? String)}
        case "noteComplete":if let id=(data["id"] as? String).flatMap(UUID.init(uuidString:)){content.notebook.setCompleted(id,data["completed"] as? Bool ?? false)}
        case "noteDelete":if let id=(data["id"] as? String).flatMap(UUID.init(uuidString:)){content.notebook.delete(id);selectedNote=nil}
        case "noteReminder":if let id=(data["id"] as? String).flatMap(UUID.init(uuidString:)){content.notebook.setReminder(id,(data["time"] as? Double).map(Date.init(timeIntervalSince1970:)))}
        case "notesCompleted":showCompleted=data["value"] as? Bool ?? false
        case "localMode":let mode=data["mode"] as? String ?? "environment";if ["environment","disk","secrets","clock","keys"].contains(mode){local.selectMode(mode)}
        case "localRun":local.run(local.selectedMode,pattern:String((data["pattern"] as? String ?? "").prefix(160)),full:data["full"] as? Bool ?? false)
        case "localStop":local.stop()
        case "reveal":if let path=data["path"] as? String,local.files.contains(where:{$0.path==path}) || local.findings.contains(where:{$0.path==path}) { win_open_url(URL(fileURLWithPath:path).deletingLastPathComponent().absoluteString) }
        case "recycle":if let path=data["path"] as? String,let file=local.files.first(where:{$0.path==path && $0.eligible}){do{try LocalLogScanner.recycle(file);local.run("disk")}catch{exportStatus=error.localizedDescription}}
        case "newsViewing":newsWindow=(data["visible"] as? Bool ?? false) ? key:nil;content.news.setViewing(data["visible"] as? Bool ?? false)
        case "newsOpen":if let id=data["id"] as? String,let item=content.news.items.first(where:{$0.id==id}) { content.news.markRead(ids:[id]);win_open_url(item.url.absoluteString) }
        case "newsWebsite":win_open_url("https://www.ailyre.com/news/")
        case "summaryHours":expandedHours.toggle()
        case "summaryModels":summaryModels.toggle()
        case "sharePeriod":loadShare(data)
        case "shareExport":export(data)
        default:navigate(command,data)
        }
        publish()
    }
    private func diagnostic(_ body: [String:Any]) {
        guard let run=body["runID"] as? String,NetworkDiagnosticParser.runID(run) else{return}
        if body["action"] as? String=="cancel" {if networkID==run{networkTask?.cancel();networkFetcher?.cancel();networkID=nil};return}
        guard let action=body["action"] as? String,["start","dnsLocations"].contains(action) else{return}
        networkTask?.cancel();networkFetcher?.cancel();networkID=run
        let fetcher=NetworkDiagnosticFetcher();networkFetcher=fetcher
        let addresses=Array((body["addresses"] as? [String] ?? []).prefix(32));let baseline=NetworkDiagnosticParser.address(body["baselineIP"] as? String)
        let token=body["dnsToken"] as? String;let timeout=min(12,max(0.2,(body["timeoutMilliseconds"] as? Double ?? 10000)/1000))
        networkTask=Task { [weak self] in
            let result: NetworkDiagnosticsResult
            if action=="dnsLocations" {result=await .init(runID:run,rows:DNSResolverLocations.lookup(addresses,timeout:timeout))}
            else {result=await NetworkDiagnostics.run(runID:run,baselineIP:baseline,fetcher:fetcher,dnsToken:token)}
            fetcher.cancel();guard let self,!Task.isCancelled,self.networkID==run,let handle=self.windows["network"],let bytes=try? JSONEncoder().encode(result),let text=String(data:bytes,encoding:.utf8) else{return}
            omni_web_send(handle,text);self.networkTask=nil;self.networkFetcher=nil;self.networkID=nil
        }
    }
    private func publishMainland() {
        guard let window=windows["network"] else{return}
        var result:[String:Any] = ["kind":"mainland","running":mainland.running,"error":mainland.inputError]
        if let report=mainland.report {
            let summary:String
            switch report.verdict {case .reachable:summary=toolboxText("已检测的大陆线路均可连接。","All tested mainland routes connected.");case .partial:summary=toolboxText("部分大陆线路可连接。","Some mainland routes connected.");case .suspectedRestriction:summary=toolboxText("大陆线路可能受限，尚不能确认封锁。","Mainland routes may be restricted; blocking is not confirmed.");case .unavailable:summary=toolboxText("大陆与境外均未连通，请检查目标服务。","Both mainland and foreign checks failed; check the target service.");case .inconclusive:summary=toolboxText("暂无法判断大陆可达性。","Mainland reachability could not be determined.")}
            result["summary"]=summary;result["rows"]=report.observations.map { ["country":$0.country,"carrier":$0.carrier ?? $0.network,"state":$0.outcome.rawValue] }
        }
        guard let bytes=try? JSONSerialization.data(withJSONObject:result,options:.sortedKeys),let json=String(data:bytes,encoding:.utf8),json != lastMainland else{return}
        lastMainland=json;omni_web_script(window,"window.OmniMainland?.update(\(json))")
    }
    private func loadShare(_ input: [String:Any]) {
        let anchor=(input["date"] as? String).flatMap(BillingText.parseDate) ?? Date()
        let period:UsageSharePeriod
        switch input["mode"] as? String {case "month":period = .month(containing:anchor);case "week":period = .weekOfMonth(containing:anchor,index:max(1,min(6,input["week"] as? Int ?? 1)));default:period = .recent(days:max(1,min(366,input["days"] as? Int ?? 7)),ending:anchor)}
        let cache=input["cache"] as? Bool ?? false;let generation=UUID();shareGeneration=generation;shareTask?.cancel()
        shareTask=Task { [weak self] in
            let data=await Task.detached(priority:.utility){UsageShareBuilder.load(period:period,includingCacheRead:cache)}.value
            guard let self,!Task.isCancelled,self.shareGeneration==generation else{return}
            self.shareData=["from":data.dateKey,"through":data.endDateKey,"tokens":TokenFormat.compact(data.totalTokens),"messages":data.messages,"cacheIncluded":cache,"quote":L10n.shared.tr(data.quoteKey),"rows":data.rows.map{["name":$0.name,"tokens":TokenFormat.compact($0.tokens),"fraction":$0.fraction] as [String:Any]}];self.publish()
        }
    }
    private func export(_ input: [String:Any]) {
        guard let image=input["image"] as? String,image.hasPrefix("data:image/png;base64,"),image.count<12*1024*1024,let bytes=Data(base64Encoded:String(image.dropFirst(22))),bytes.starts(with:[137,80,78,71,13,10,26,10]) else{return}
        var path=[CChar](repeating:0,count:4096)
        guard win_pick_save_file(windows["share"],toolboxText("保存分享图片","Save share image"),"OmniClock-usage.png",&path,Int32(path.count)) != 0 else{return}
        do {try bytes.write(to:URL(fileURLWithPath:String(cString:path)),options:.atomic);exportStatus=toolboxText("图片已保存","Image saved")}
        catch {exportStatus=error.localizedDescription}
    }
}
private let windowsToolboxMessage: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = { context, key, raw in
    guard let context,let key,let raw else{return}
    let owner=Unmanaged<WindowsToolboxes>.fromOpaque(context).takeUnretainedValue()
    let text=String(cString:raw)
    guard let data=text.data(using:.utf8),let message=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return}
    let name=String(cString:key)
    if let pageMessage=message["__pageMessage"] as? [String:Any] {MainActor.assumeIsolated {owner.handle(key:name,message:pageMessage,fromPage:true)}}
    else {MainActor.assumeIsolated { owner.handle(key:name,message:message) }}
}
#endif

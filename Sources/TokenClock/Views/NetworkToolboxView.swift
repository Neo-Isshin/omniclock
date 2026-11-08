#if os(macOS)
import SwiftUI

@MainActor final class NetworkToolboxPresentation: ObservableObject {
    struct Card: Identifiable {
        let id: String
        var title: String
        var status: String
        var text: String
        var state: String
        var reason: String = ""
        var summaryText: String = ""
        var localizedTitle: String {
            switch id {
            case "exit": return toolboxText("网页出口", "Web exit IP")
            case "dns": return toolboxText("DNS 泄漏检测", "DNS leak check")
            case "rtc": return toolboxText("WebRTC 泄漏检测", "WebRTC leak check")
            case "consistency": return toolboxText("出口与地区", "Exit & location")
            case "ipv6": return toolboxText("IPv6 泄漏检测", "IPv6 leak check")
            case "ai": return toolboxText("AI 域名分流", "AI domain routing")
            case "doh": return toolboxText("加密 DNS（DoH）", "Encrypted DNS (DoH)")
            default: return title
            }
        }
        var shortName: String { ["dns":"DNS", "rtc":"WebRTC", "ipv6":"IPv6", "doh":"DoH"][id] ?? localizedTitle }
        var isLeakCheck: Bool { ["dns", "rtc", "ipv6", "doh"].contains(id) }
        var localAddressExposed: Bool { id == "rtc" && reason == "localAddressExposed" }
        var localizedStatus: String {
            if localAddressExposed { return toolboxText("本地地址暴露", "Local IP exposed") }
            switch state {
            case "risk": return isLeakCheck ? toolboxText("可能泄漏", "Possible leak") : toolboxText("需要关注", "Needs attention")
            case "review":
                if id == "consistency" { return toolboxText("存在差异", "Different results") }
                if id == "ai" { return toolboxText("不同出口", "Different exits") }
                return toolboxText("暂无法判断", "Cannot determine")
            case "match": return isLeakCheck ? toolboxText("未发现泄漏", "No leak found") : toolboxText("一致", "Consistent")
            case "observed": return toolboxText("已获取", "Available")
            case "partial": return toolboxText("部分确认", "Partly confirmed")
            case "notObserved": return toolboxText("未检测到 IPv6", "No IPv6 detected")
            case "incomplete": return toolboxText("暂无法判断", "Cannot determine")
            case "running": return toolboxText("检测中", "Checking")
            case "idle", "": return toolboxText("尚未检测", "Not checked")
            case "invalid": return toolboxText("请检查设置", "Check settings")
            default: return status
            }
        }
        var resultSummary: String {
            if state == "running" { return toolboxText("正在检测，请稍候。", "Checking this connection…") }
            if state == "idle" || state.isEmpty { return toolboxText("点击开始检测后显示结果。", "Run a check to see the result.") }
            switch id {
            case "exit":
                return state == "observed" ? toolboxText("这是网站目前看到的公网出口。", "This is the public IP currently seen by websites.") : toolboxText("暂未取得网页出口。", "The web exit could not be obtained.")
            case "dns":
                if reason == "partialDNSCheck" { return toolboxText("DNS 结果不完整，暂无法判断是否泄漏。", "Some DNS results are missing; a leak cannot be determined.") }
                switch state {
                case "risk": return toolboxText("发现预期之外的 DNS，可能存在泄漏。", "Unexpected DNS sources were found; a leak is possible.")
                case "match": return toolboxText("DNS 查询来源符合预期，未发现泄漏。", "DNS sources match your expectation; no leak was found.")
                case "review": return toolboxText("已检测到 DNS，但未指定预期 DNS，暂无法判断是否泄漏。", "DNS was detected; without expected DNS, a leak cannot be determined.")
                case "invalid": return toolboxText("预期 DNS 格式有误，请修正后再判断。", "Correct the expected DNS addresses to finish the comparison.")
                default: return toolboxText("未取得 DNS 结果，暂无法判断是否泄漏。", "No DNS result was received; a leak cannot be determined.")
                }
            case "rtc":
                if localAddressExposed { return toolboxText("WebRTC 暴露了本地网络地址。", "WebRTC exposed a local network address.") }
                if reason == "unexpectedIPv6" { return toolboxText("预期只使用 IPv4，但 WebRTC 暴露了 IPv6 地址。", "WebRTC exposed IPv6 although IPv4-only was expected.") }
                if state == "risk" { return toolboxText("WebRTC 暴露了不同的公网 IP，可能泄漏。", "WebRTC exposed a different public IP; a leak is possible.") }
                if state == "match" { return toolboxText("WebRTC 公网出口与网页一致，未发现泄漏。", "WebRTC uses the same public exit as web traffic.") }
                return toolboxText("暂未取得足够的可比对结果，无法判断是否泄漏。", "There is not enough comparable information to determine a leak.")
            case "ipv6":
                if state == "notObserved" { return toolboxText("本次未检测到 IPv6 出口。", "No IPv6 exit was detected in this check.") }
                if state == "risk" { return toolboxText("发现预期之外的 IPv6 出口，可能泄漏。", "Unexpected IPv6 access was found; a leak is possible.") }
                if state == "match" { return toolboxText("已核对的 IPv6 出口一致，未发现泄漏。", "The tested IPv6 exits match; no leak was found.") }
                return toolboxText("已检测到的 IPv6 信息不足，暂无法判断是否泄漏。", "The IPv6 information is insufficient to determine a leak.")
            case "doh":
                if reason == "differentDoHRoute" { return toolboxText("加密 DNS 与主要网页出口不同，请核对分流。", "Encrypted DNS differs from the main web exit; review routing.") }
                if state == "risk" { return toolboxText("加密 DNS 使用了不同公网出口，可能泄漏。", "Encrypted DNS used a different public exit; a leak is possible.") }
                if state == "review" { return toolboxText("加密 DNS 可能未经过预期代理。", "Encrypted DNS may bypass the expected proxy.") }
                if state == "match" { return toolboxText("已核对的加密 DNS 出口与网页一致。", "The checked encrypted DNS exit matches web traffic.") }
                if state == "partial" { return toolboxText("加密 DNS 可连接，部分出口或检测结果尚未确认。", "Encrypted DNS works; some exit or test results remain unconfirmed.") }
                return toolboxText("本次未能确认加密 DNS 的连接与出口。", "Encrypted DNS could not be verified in this check.")
            case "consistency":
                if state == "match" { return toolboxText("网页出口与地区信息一致。", "Web exits and location look consistent.") }
                if state == "review" { return toolboxText("不同检测站看到的出口或地区不一致，请检查分流。", "Some web exits or locations differ; check your routing.") }
                return toolboxText("部分出口或地区信息尚无法确认。", "Some exit or location information could not be checked.")
            case "ai":
                if state == "match" { return toolboxText("已核对的 AI 站点出口符合预期。", "The checked AI sites use the expected exit.") }
                if state == "review" { return toolboxText("部分 AI 站点使用了不同出口，请检查分流。", "Some AI sites use a different exit; review routing.") }
                if state == "partial" { return toolboxText("部分站点出口已确认，其余未返回出口 IP。", "Some site exits are confirmed; others did not return an IP.") }
                return toolboxText("AI 站点暂未提供足够的出口信息。", "The AI sites did not provide enough exit information.")
            default: return summaryText.isEmpty ? localizedStatus : summaryText
            }
        }
        var detailLines: [String] {
            let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return lines.isEmpty ? [toolboxText("暂无检测数据", "No result yet")] : lines
        }
    }
    @Published var status = ""
    @Published var summary = ""
    @Published var running = false
    @Published var cards: [Card] = []
    @Published var expectedDNS = ""
    @Published var ipv4Only = false
    @Published var observedExitIP: String?
    let mainland = MainlandReachabilityModel()
    private var leakCards: [Card] { cards.filter(\.isLeakCheck) }
    var issueSummary: String {
        if running { return toolboxText("正在检查是否存在泄漏…", "Checking for leaks…") }
        guard cards.contains(where: { !["", "idle"].contains($0.state) }) else {
            return toolboxText("点击开始检测，检查当前连接是否存在泄漏。", "Run checks to look for leaks in this connection.")
        }
        let issues = leakCards.compactMap { card -> String? in
            if card.localAddressExposed { return toolboxText("WebRTC：本地地址已暴露", "WebRTC: local address exposed") }
            return card.state == "risk" ? card.shortName + toolboxText("：可能泄漏", ": possible leak") : nil
        }
        if !issues.isEmpty { return issues.joined(separator: toolboxText("；", "; ")) + toolboxText("。", ".") }
        return leakCards.contains(where: { $0.state == "match" })
            ? toolboxText("已核对的泄漏项目未发现异常。", "No leak found in the checks that could be verified.")
            : toolboxText("暂无法判断是否存在泄漏。", "A leak verdict is not yet available.")
    }
    var pendingSummary: String {
        guard !running else { return "" }
        let pending = leakCards.filter { !["risk", "match", "idle", ""].contains($0.state) && !$0.localAddressExposed }
        var parts: [String] = []
        if !pending.isEmpty { parts.append(toolboxText("暂无法判断是否泄漏：", "Leak verdict unavailable: ") + pending.map(\.shortName).joined(separator: toolboxText("、", ", "))) }
        if let ai = cards.first(where: { $0.id == "ai" }), ["partial", "incomplete"].contains(ai.state) {
            parts.append(toolboxText("AI 分流：部分站点未返回出口信息", "AI routing: some sites did not return an exit IP"))
        }
        if let consistency = cards.first(where: { $0.id == "consistency" }), consistency.state == "review" {
            parts.append(toolboxText("网页出口或地区不一致", "Web exits or locations differ"))
        }
        if let ai = cards.first(where: { $0.id == "ai" }), ai.state == "review" {
            parts.append(toolboxText("AI 站点存在不同出口", "AI sites use different exits"))
        }
        return parts.joined(separator: toolboxText("；", "; "))
    }
    func update(_ data: [String: Any]) {
        status = String((data["status"] as? String ?? "").prefix(400))
        running = data["running"] as? Bool ?? false
        if let items = data["cards"] as? [[String: String]] {
            cards = items.prefix(7).map { Card(id: $0["id"] ?? "", title: $0["title"] ?? "", status: $0["status"] ?? "",
                text: String(($0["text"] ?? "").prefix(10000)), state: $0["state"] ?? "", reason: $0["reason"] ?? "", summaryText: $0["summary"] ?? "") }
        }
        summary = issueSummary
    }
}

@MainActor enum NetworkToolboxCardLayout {
    static let headerHeight: CGFloat = 22
    static let summaryHeight: CGFloat = 32
    static let rowHeight: CGFloat = 20
    static let visibleRows = 6
    static let detailsHeight: CGFloat = rowHeight * CGFloat(visibleRows)
    static let contentHeight: CGFloat = headerHeight + summaryHeight + detailsHeight + 18
    static let cardHeight: CGFloat = contentHeight + 28
}

struct NetworkToolboxResultCard: View {
    let card: NetworkToolboxPresentation.Card
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label(card.localizedTitle, systemImage: icon).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text(card.localizedStatus).font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(card.state == "risk" || card.localAddressExposed ? Color.orange : card.state == "match" ? Color.green : Color.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.045), in: Capsule())
            }.frame(height: NetworkToolboxCardLayout.headerHeight)
            Text(card.resultSummary).font(.system(size: 11.5, weight: .medium)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: NetworkToolboxCardLayout.summaryHeight, maxHeight: NetworkToolboxCardLayout.summaryHeight, alignment: .topLeading)
                .instantHint(card.resultSummary)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(card.detailLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).frame(maxWidth: .infinity, minHeight: NetworkToolboxCardLayout.rowHeight,
                                maxHeight: NetworkToolboxCardLayout.rowHeight, alignment: .leading).instantHint(line)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: NetworkToolboxCardLayout.detailsHeight).clipped()
        }
        .frame(height: NetworkToolboxCardLayout.contentHeight, alignment: .topLeading)
        .toolboxCard().accessibilityIdentifier("network-result-card." + card.id)
    }
}

struct NetworkToolboxView: View {
    @ObservedObject var model: NetworkToolboxPresentation
    @ObservedObject private var mainland: MainlandReachabilityModel
    let onRun: () -> Void
    let onStop: () -> Void
    let onBrowser: () -> Void
    let onOptions: () -> Void

    init(model: NetworkToolboxPresentation, onRun: @escaping () -> Void, onStop: @escaping () -> Void,
         onBrowser: @escaping () -> Void, onOptions: @escaping () -> Void) {
        self.model = model
        self.mainland = model.mainland
        self.onRun = onRun; self.onStop = onStop; self.onBrowser = onBrowser; self.onOptions = onOptions
    }
    private var combinedSummary: String {
        [model.issueSummary, mainland.report.flatMap { $0.verdict == .suspectedRestriction ? toolboxText("大陆线路可能受限，尚不能确认封锁。", "Mainland routes may be restricted; blocking is not confirmed.") : nil }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private func cardIcon(_ id: String) -> String {
        switch id {
        case "dns": return "server.rack"
        case "rtc": return "video"
        case "consistency": return "globe"
        case "ipv6": return "network"
        case "ai": return "point.3.connected.trianglepath.dotted"
        case "doh": return "lock.shield"
        default: return "wifi"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(toolboxText("网络工具箱", "Network Toolbox")).font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(toolboxText("点击检测当前连接的泄漏风险", "On-demand checks for leaks in this connection")).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onBrowser) { Image(systemName: "safari") }.instantHint(toolboxText("在默认浏览器中单独检测", "Check the default browser separately"))
                if model.running { Button(toolboxText("停止", "Stop"), action: onStop).instantHint(toolboxText("立即取消本次探测", "Cancel this check immediately")) }
                else { Button(toolboxText("开始检测", "Run checks"), action: onRun).instantHint(toolboxText("检测一次，完成后停止", "Run once, then stop")) }
            }.buttonStyle(.bordered).padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            HStack(spacing: 7) {
                if model.running { ProgressView().controlSize(.mini) }
                VStack(alignment:.leading,spacing:3) {
                    if !combinedSummary.isEmpty {Text(combinedSummary).font(.system(size:12,weight:.semibold)).fixedSize(horizontal:false,vertical:true)}
                    if !model.pendingSummary.isEmpty { Text(model.pendingSummary).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    Text(model.status.isEmpty ? toolboxText("等待检测", "Ready") : model.status).font(.system(size:10)).foregroundStyle(.secondary)
                }
                Spacer()
            }.toolboxCard().padding(.horizontal,16).padding(.top,12)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(model.cards) { card in
                        NetworkToolboxResultCard(card: card, icon: cardIcon(card.id))
                    }
                    MainlandReachabilityCard(model: mainland, observedExitIP: model.observedExitIP)
                }.padding(16)
                DisclosureGroup(toolboxText("检测预期（可选）", "Expected policy (optional)")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(toolboxText("预期查询来源 IP（可与本机 DNS 地址不同）", "Expected DNS IPs, comma-separated"), text: $model.expectedDNS)
                            .textFieldStyle(.roundedBorder).onChange(of: model.expectedDNS) { _ in onOptions() }
                        Toggle(toolboxText("预期只使用 IPv4", "Expect IPv4 only"), isOn: $model.ipv4Only).onChange(of: model.ipv4Only) { _ in onOptions() }
                        Text(toolboxText("地址或地区不同仅提示核对。无响应不代表安全；应用内结果不代表浏览器扩展规则。", "Address/location differences need review. No response does not prove safety; app results do not cover browser extension rules.")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }.font(.system(size: 11)).padding(.horizontal, 20).padding(.bottom, 16)
            }
        }.frame(minWidth: 440, minHeight: 420).background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MainlandReachabilityCard: View {
    @ObservedObject var model: MainlandReachabilityModel
    let observedExitIP: String?

    @State private var showsDetails = false
    private var compactSummary: String {
        if model.running { return toolboxText("正在检查大陆与境外的连接。", "Checking mainland and foreign connections.") }
        if !model.inputError.isEmpty { return model.inputError }
        guard let report = model.report else { return toolboxText("填入目标 IP 和端口后，可单独检测大陆可达性。", "Enter an IP and port to check mainland reachability separately.") }
        switch report.verdict {
        case .reachable: return toolboxText("已检测的大陆线路均可连接。", "All tested mainland routes connected.")
        case .partial: return toolboxText("部分大陆线路可连接，部分尚未确认。", "Some mainland routes connected; others remain unconfirmed.")
        case .suspectedRestriction: return toolboxText("大陆线路可能受限，尚不能确认封锁。", "Mainland routes may be restricted; blocking is not confirmed.")
        case .unavailable: return toolboxText("大陆与境外均未连通，请检查目标服务。", "Both mainland and foreign checks failed; check the target service.")
        case .inconclusive: return toolboxText("暂无法判断大陆可达性。", "Mainland reachability could not be determined.")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Label(toolboxText("大陆可达性", "Mainland reachability"), systemImage: "globe")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Text(model.running ? toolboxText("检测中", "Checking") : model.report == nil ? toolboxText("尚未检测", "Not checked") : toolboxText("已完成", "Finished"))
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.045), in: Capsule())
            }.frame(height: NetworkToolboxCardLayout.headerHeight)
            Text(compactSummary).font(.system(size: 11.5, weight: .medium)).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: NetworkToolboxCardLayout.summaryHeight, maxHeight: NetworkToolboxCardLayout.summaryHeight, alignment: .topLeading)
                .instantHint(compactSummary)
            VStack(alignment: .leading, spacing: 0) {
                targetFields.controlSize(.mini).frame(height: NetworkToolboxCardLayout.rowHeight)
                controls.frame(height: NetworkToolboxCardLayout.rowHeight)
                ForEach(["China Telecom", "China Unicom", "China Mobile"], id: \.self) { carrier in
                    let rows = model.report?.observations.filter { $0.carrier == carrier } ?? []
                    let label = carrier == "China Telecom" ? toolboxText("电信", "Telecom") : carrier == "China Unicom" ? toolboxText("联通", "Unicom") : toolboxText("移动", "Mobile")
                    let result = rows.contains(where: { $0.outcome == .reachable }) ? toolboxText("可连接", "Connected") : rows.isEmpty ? "—" : toolboxText("未连接成功", "Not connected")
                    Text(label + " · " + result).font(.system(size: 10.5)).lineLimit(1)
                        .frame(height: NetworkToolboxCardLayout.rowHeight, alignment: .leading)
                }
                HStack(spacing: 4) {
                    Link("Globalping", destination: URL(string: "https://globalping.io/")!)
                    Text(toolboxText("· 公开测量", "· public test")).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button(toolboxText("详情", "Details")) { showsDetails = true }.buttonStyle(.plain)
                        .popover(isPresented: $showsDetails) { ScrollView { expandedContent }.frame(width: 560, height: 540).padding(12) }
                }.font(.system(size: 9.5)).frame(height: NetworkToolboxCardLayout.rowHeight)
                    .instantHint(toolboxText("点击检测会将目标 IP、端口发送给 Globalping，测量结果可能公开。超时不等于封锁。", "Running a check sends the target IP and port to Globalping; results may be public. A timeout does not prove blocking."))
            }.frame(height: NetworkToolboxCardLayout.detailsHeight, alignment: .topLeading)
        }.frame(height: NetworkToolboxCardLayout.contentHeight, alignment: .topLeading)
            .toolboxCard().accessibilityIdentifier("network-result-card.mainland")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(toolboxText("大陆可达性 / GFW 参考", "Mainland reachability / GFW reference"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if model.running { ProgressView().controlSize(.small) }
                else { Text(model.report == nil ? toolboxText("尚未检测", "Not checked") : toolboxText("检测完成", "Finished"))
                    .font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            Text(toolboxText("填写已开放的服务端口。大陆三网多点与境外对照；出口 IP 可能不接受入站连接。", "Use an open service port. Compare mainland carrier probes with foreign controls; an exit IP may not accept inbound connections."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if #available(macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { targetFields; controls }
                    VStack(alignment: .leading, spacing: 8) { targetFields; controls }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) { targetFields; controls }
            }
            if !model.inputError.isEmpty {
                Text(model.inputError).font(.system(size: 10)).foregroundStyle(.orange)
            }
            if model.running {
                Text(toolboxText("请求大陆三网及境外节点；必要时复用同一批探针核对参考地址，最多等待 40 秒。", "Requesting mainland and foreign probes; reusing the same probes for a reference check when needed. Up to 40 seconds."))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let report = model.report {
                Text(report.target.display).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(report.summary).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(report.verdict == .suspectedRestriction ? Color.orange : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], alignment: .leading, spacing: 9) {
                    ForEach(report.observations) { row in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nodeTitle(row)).font(.system(size: 10, weight: .medium)).lineLimit(2)
                                Text("AS\(String(row.asn)) · \(row.city)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                                if let reference = row.referenceReachable {
                                    Text(reference ? toolboxText("同探针对照：可达", "Same-probe reference: reachable") : toolboxText("同探针对照：未连通", "Same-probe reference: no connection"))
                                        .font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 2)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(outcomeText(row.outcome)).font(.system(size: 10))
                                if let rtt = row.milliseconds { Text(String(format: "%.0f ms", rtt)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary) }
                            }
                        }.padding(8).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                HStack {
                    Text(report.checkedAt, format: .dateTime.year().month().day().hour().minute().second())
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Divider()
            HStack(spacing: 5) {
                Text(toolboxText("探测服务：", "Measurements: "))
                Link("Globalping ↗", destination: URL(string: "https://globalping.io/")!)
                Spacer()
                Link(toolboxText("条款与隐私", "Terms & privacy"), destination: URL(string: "https://globalping.io/terms")!)
            }.font(.system(size: 10))
            Text(toolboxText("点击检测会将目标 IP、端口及测量参数发送给 Globalping；参数和结果可能公开。超时不等于封锁。", "Running a check sends the target IP, port and measurement options to Globalping; parameters and results may be public. A timeout does not prove blocking."))
                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(toolboxText("仅验证 TCP 连接，不覆盖域名、TLS/SNI 或代理协议。", "TCP reachability only; this does not test domain, TLS/SNI or proxy-protocol filtering."))
                .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.toolboxCard()
    }

    private var targetFields: some View {
        HStack(spacing: 7) {
            TextField(toolboxText("公网 IPv4 / IPv6", "Public IPv4 / IPv6"), text: $model.targetIP)
                .textFieldStyle(.roundedBorder).frame(minWidth: 140)
                .accessibilityLabel(toolboxText("检测目标 IP", "Target IP"))
            TextField(toolboxText("端口", "Port"), text: $model.targetPort)
                .textFieldStyle(.roundedBorder).frame(width: 65)
                .accessibilityLabel(toolboxText("检测目标端口", "Target port"))
        }.disabled(model.running)
    }
    private var controls: some View {
        HStack(spacing: 7) {
            Button(toolboxText("当前出口", "Use exit IP")) { model.targetIP = observedExitIP ?? "" }
                .disabled(model.running || observedExitIP == nil)
                .instantHint(toolboxText("仅填入本次检测观测到的出口；请确认该 IP 上有开放端口。", "Fill the observed exit only; confirm that this IP has an open port."))
            if model.running {
                Button(toolboxText("停止", "Stop")) { model.stop() }
                    .instantHint(toolboxText("取消本地等待；已下发的远端探测可能仍会完成。", "Cancel local waiting; already submitted remote tests may still finish."))
            } else {
                Button(toolboxText("检测可达性", "Check reachability")) { model.start() }
                    .instantHint(toolboxText("发起一次 Globalping 公开测量，不会后台定时运行。", "Run one public Globalping measurement; no background schedule."))
            }
        }.buttonStyle(.bordered).controlSize(.small).fixedSize(horizontal: true, vertical: false)
    }
    private func nodeTitle(_ row: MainlandProbeObservation) -> String {
        if let carrier = row.carrier {
            if carrier == "China Telecom" { return toolboxText("大陆 · 电信", "Mainland · Telecom") }
            if carrier == "China Unicom" { return toolboxText("大陆 · 联通", "Mainland · Unicom") }
            return toolboxText("大陆 · 移动", "Mainland · Mobile")
        }
        return toolboxText("境外对照 · ", "Foreign control · ") + row.country
    }
    private func outcomeText(_ value: MainlandProbeOutcome) -> String {
        switch value {
        case .reachable: return toolboxText("可达", "Connected")
        case .noResponse: return toolboxText("无响应", "No response")
        case .refused: return toolboxText("连接被拒绝", "Refused")
        case .unavailable: return toolboxText("未取得结果", "Unavailable")
        }
    }
}
#endif

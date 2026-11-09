import Foundation
#if canImport(Combine)
import Combine
#endif
@MainActor final class NetworkToolboxPresentation: ObservableObject {
    struct Card: Identifiable, Codable {
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

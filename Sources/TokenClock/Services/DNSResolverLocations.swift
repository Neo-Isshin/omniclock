#if os(macOS)
import Foundation

private actor DNSResolverLocationCache {
    static let shared = DNSResolverLocationCache()
    private var values: [String: (Date, NetworkDiagnosticRow)] = [:]
    func get(_ ip: String, now: Date = Date()) -> NetworkDiagnosticRow? {
        guard let value = values[ip], now.timeIntervalSince(value.0) < 6 * 3600 else { return nil }
        return value.1
    }
    func put(_ row: NetworkDiagnosticRow, now: Date = Date()) {
        guard let ip = row.ip, row.state == "observed" else { return }
        if values.count >= 128, let key = values.min(by: { $0.value.0 < $1.value.0 })?.key { values.removeValue(forKey: key) }
        values[ip] = (now, row)
    }
}

/// Resolve the six DNS sources shown on the card. This is location information,
/// never evidence that a resolver is allowed or that DNS traffic stayed in a VPN.
enum DNSResolverLocations {
    static func addresses(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { MainlandReachabilityTarget.parse(ip: $0, port: "443")?.ip }
            .filter { seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    static func parse(_ reply: NetworkDiagnosticReply, ip: String, source: String) -> NetworkDiagnosticRow? {
        guard reply.status == 200, !reply.limited,
              let body = NetworkDiagnosticParser.json(reply.data), body["success"] as? Bool != false,
              NetworkDiagnosticParser.address(body["ip"] as? String) == ip,
              let country = NetworkDiagnosticParser.country((body["country_code"] ?? body["country"]) as? String) else { return nil }
        return .init(id: "dns-geo-" + ip, category: "dnsGeo", label: source, host: "", state: "observed", ip: ip,
            country: country, region: (body["region"] as? String).map { String($0.prefix(100)) },
            city: (body["city"] as? String).map { String($0.prefix(100)) })
    }

    static func run(token: String?) async -> [NetworkDiagnosticRow] {
        guard let token, token.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { return [] }
        // A separate short-lived transport keeps a failed lookup from cancelling
        // the actual DNS, WebRTC, or connection checks.
        let fetcher = NetworkDiagnosticFetcher(requestTimeout: 1.5, resourceTimeout: 3)
        defer { fetcher.cancel() }
        var selected: [String] = []
        for attempt in 0..<4 {
            guard !Task.isCancelled else { return [] }
            let reply = await fetcher.fetch(URL(string: "https://www.ailyre.com/tokenclock/network-check/result/" + token)!)
            if reply.status == 200, let body = NetworkDiagnosticParser.json(reply.data), let raw = body["resolvers"] as? [String] {
                selected = addresses(raw)
                if !selected.isEmpty, (body["probesObserved"] as? Int ?? 0) >= 3 || attempt == 3 { break }
            }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 400_000_000) }
        }
        guard !Task.isCancelled else { return [] }
        return await withTaskGroup(of: NetworkDiagnosticRow.self) { group in
            for ip in selected {
                group.addTask {
                    if let cached = await DNSResolverLocationCache.shared.get(ip) { return cached }
                    let first = URL(string: "https://ipwho.is/" + ip + "?fields=ip,success,country_code,region,city")!
                    let second = URL(string: "https://api.country.is/" + ip)!
                    async let who = fetcher.fetch(first)
                    async let country = fetcher.fetch(second)
                    let replies = await (who, country)
                    let row = parse(replies.0, ip: ip, source: "IPWhois") ?? parse(replies.1, ip: ip, source: "Country.is")
                        ?? NetworkDiagnosticRow(id: "dns-geo-" + ip, category: "dnsGeo", label: "DNS location", host: "", state: "unavailable", ip: ip)
                    await DNSResolverLocationCache.shared.put(row)
                    return row
                }
            }
            var rows: [NetworkDiagnosticRow] = []
            for await row in group { rows.append(row) }
            return rows.sorted { ($0.ip ?? "") < ($1.ip ?? "") }
        }
    }
}
#endif

#if os(Windows)
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

/// Resolve all observed DNS sources after the DNS probe finishes. This is location information,
/// never evidence that a resolver is allowed or that DNS traffic stayed in a VPN.
enum DNSResolverLocations {
    static func addresses(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { MainlandReachabilityTarget.parse(ip: $0, port: "443")?.ip }
            .filter { seen.insert($0).inserted }.prefix(32).map { $0 }
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

    static func lookup(_ values: [String], timeout: TimeInterval = 10) async -> [NetworkDiagnosticRow] {
        let selected = addresses(values)
        guard !selected.isEmpty, !Task.isCancelled else { return [] }
        let fetcher = NetworkDiagnosticFetcher(requestTimeout: 3, resourceTimeout: 4)
        let deadline = Task {
            try? await Task.sleep(nanoseconds: UInt64(min(12, max(0.2, timeout)) * 1_000_000_000))
            if !Task.isCancelled { fetcher.cancel() }
        }
        defer { deadline.cancel(); fetcher.cancel() }
        // Bound concurrency so a large resolver set cannot exhaust the location
        // service or make queued requests time out before they reach the network.
        return await withTaskGroup(of: NetworkDiagnosticRow.self) { group in
            var iterator = selected.makeIterator()
            func enqueue(_ ip: String) {
                group.addTask {
                    if let cached = await DNSResolverLocationCache.shared.get(ip) { return cached }
                    let first = URL(string: "https://ipwho.is/" + ip + "?fields=ip,success,country_code,region,city")!
                    let second = URL(string: "https://api.country.is/" + ip)!
                    var row = parse(await fetcher.fetch(first), ip: ip, source: "IPWhois")
                    if row == nil, !Task.isCancelled {
                        row = parse(await fetcher.fetch(second), ip: ip, source: "Country.is")
                    }
                    let result = row ?? NetworkDiagnosticRow(id: "dns-geo-" + ip, category: "dnsGeo", label: "DNS location", host: "", state: "unavailable", ip: ip)
                    await DNSResolverLocationCache.shared.put(result)
                    return result
                }
            }
            for _ in 0..<4 { if let ip = iterator.next() { enqueue(ip) } }
            var rows: [NetworkDiagnosticRow] = []
            for await row in group {
                rows.append(row)
                if !Task.isCancelled, let ip = iterator.next() { enqueue(ip) }
            }
            return rows.sorted { ($0.ip ?? "") < ($1.ip ?? "") }
        }
    }
}
#endif

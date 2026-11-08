import Foundation

/// UserDefaults-compatible storage for shared feature services on Windows.
/// Keeps their existing keys in the same durable settings file as native menus.
final class WindowsDurableDefaults: UserDefaults {
    nonisolated(unsafe) static let persistent = WindowsDurableDefaults(suiteName: "OmniClock.SharedFeatures")!
    override func object(forKey key: String) -> Any? {
        let value = WindowsPreferences.shared.object(forKey: key)
        if let marker = value as? [String: String], marker.count == 1, let encoded = marker["$binary"] { return Data(base64Encoded: encoded) }
        if let marker = value as? [String: Double], marker.count == 1, let seconds = marker["$date"] { return Date(timeIntervalSince1970: seconds) }
        return value
    }
    override func set(_ value: Any?, forKey key: String) {
        if let data = value as? Data { WindowsPreferences.shared.set(["$binary": data.base64EncodedString()], forKey: key) }
        else if let date = value as? Date { WindowsPreferences.shared.set(["$date": date.timeIntervalSince1970], forKey: key) }
        else { WindowsPreferences.shared.set(value, forKey: key) }
    }
    override func removeObject(forKey key: String) { WindowsPreferences.shared.removeObject(forKey: key) }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func bool(forKey key: String) -> Bool { (object(forKey: key) as? NSNumber)?.boolValue ?? false }
    override func integer(forKey key: String) -> Int { (object(forKey: key) as? NSNumber)?.intValue ?? 0 }
    override func double(forKey key: String) -> Double { (object(forKey: key) as? NSNumber)?.doubleValue ?? 0 }
}

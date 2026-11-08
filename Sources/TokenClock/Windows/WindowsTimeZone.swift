import Foundation
import Win32Shim

enum WindowsTimeZone {
    static func systemIdentifier() -> String? {
        var name=[CChar](repeating:0,count:128)
        guard win_system_timezone(&name,128) != 0 else{return nil}
        let identifier=String(cString:name)
        return TimeZone(identifier:identifier)==nil ? nil:identifier
    }
    static func configure() {
        let explicit=ProcessInfo.processInfo.environment["TZ"].flatMap(TimeZone.init(identifier:))
        guard let zone=explicit ?? systemIdentifier().flatMap(TimeZone.init(identifier:)) else{return}
        win_set_process_timezone(zone.identifier)
        NSTimeZone.resetSystemTimeZone()
        // On this Swift Windows runtime ICU formatters otherwise keep GMT even
        // when Calendar/TimeZone.current already sees the process TZ setting.
        NSTimeZone.default=zone
    }
}

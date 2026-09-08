import Foundation
import IOKit
import IOKit.ps

struct Battery: Codable, Identifiable {
    var id: String
    var name: String
    var model: String
    var connection: String
    var date = Date()
    var percent: Double?
    var full: Double?
    var design: Double?
    var cycles: Double?
    var temperature: Double?
    var voltage: Double?
    var amperage: Double?
    var charging: Bool?
    var external: Bool?
    var minutes: Double?
    var details: [String: String] = [:]
    var note: String = ""
    var available: Bool? = true
    var components: [String: Double]? = nil
    var isLive: Bool { available != false }
    var health: Double? { guard let full, let design, full > 0, design > 0 else { return nil }; return full / design * 100 }
    var watts: Double? { guard let voltage, let amperage else { return nil }; return voltage * amperage / 1000 }
    var symbol: String {
        let text = (model + name).lowercased()
        if id == "mac" { return "desktopcomputer" }
        if text.contains("ipad") { return "ipad" }
        if text.contains("trackpad") { return "trackpad" }
        if text.contains("keyboard") { return "keyboard" }
        if text.contains("mouse") { return "computermouse" }
        if text.contains("airpods") || text.contains("headphone") { return "airpodspro" }
        if text.contains("watch") { return "applewatch" }
        if text.contains("tv") { return "appletv" }
        return "iphone"
    }
}

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

enum Command {
    static func path(_ name: String) -> String? {
        ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/", "/usr/sbin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func run(_ name: String, _ args: [String], timeout: TimeInterval = 12) throws -> Data {
        guard let path = path(name) else { throw ReaderError.message("Не найдена системная утилита \(name).") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = args
        process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ReaderError.message("\(name): устройство не ответило за \(Int(timeout)) с")
        }
        let data = try Data(contentsOf: url)
        guard process.terminationStatus == 0 else { throw ReaderError.message(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Ошибка \(name)") }
        return data
    }
    static func plist(_ name: String, _ args: [String]) throws -> Any {
        var data = try run(name, args)
        if let range = data.range(of: Data("<?xml".utf8)) { data = data.subdata(in: range.lowerBound..<data.endIndex) }
        return try PropertyListSerialization.propertyList(from: data, format: nil)
    }

}

enum BatteryParser {
    static func number(_ d: [String: Any], _ keys: String...) -> Double? {
        for key in keys { if let n = d[key] as? NSNumber { return n.doubleValue }; if let s = d[key] as? String, let n = Double(s) { return n } }
        return nil
    }
    static func signedCurrent(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber else { return nil }
        if n.doubleValue > Double(Int64.max) { return Double(Int64(bitPattern: n.uint64Value)) }
        return n.doubleValue
    }
    static func parse(_ d: [String: Any], id: String, name: String, model: String, connection: String) -> Battery {
        var b = Battery(id: id, name: name, model: model, connection: connection)
        let nested = d["BatteryData"] as? [String: Any] ?? [:]
        b.full = number(d, "AppleRawMaxCapacity", "NominalChargeCapacity") ?? number(nested, "NominalChargeCapacity", "FullChargeCapacity")
        b.design = number(d, "DesignCapacity") ?? number(nested, "DesignCapacity")
        // MaxCapacity is a percentage on recent Macs, but mAh on some iOS/Intel devices.
        if b.full == nil, let max = number(d, "MaxCapacity"), max > 100 { b.full = max }
        if let raw = number(d, "AppleRawCurrentCapacity"), let full = b.full, full > 0 { b.percent = min(100, max(0, raw / full * 100)) }
        else if let current = number(d, "CurrentCapacity"), let max = number(d, "MaxCapacity"), max > 0 { b.percent = min(100, Swift.max(0, current / max * 100)) }
        b.cycles = number(d, "CycleCount") ?? number(nested, "CycleCount")
        if let t = number(d, "Temperature"), t > 0 { b.temperature = t / 100 }
        if let v = number(d, "Voltage"), v > 0 { b.voltage = v / 1000 }
        b.amperage = signedCurrent(d["Amperage"] ?? d["InstantAmperage"])
        b.charging = d["IsCharging"] as? Bool; b.external = d["ExternalConnected"] as? Bool
        if let t = number(d, "TimeRemaining"), t > 0 && t < 65535 { b.minutes = t }
        b.details = flatten(d)
        return b
    }
    static func flatten(_ value: Any, prefix: String = "") -> [String: String] {
        var result: [String: String] = [:]
        if let d = value as? [String: Any] {
            for (key, value) in d { result.merge(flatten(value, prefix: prefix.isEmpty ? key : prefix + "." + key), uniquingKeysWith: { _, b in b }) }
        } else if let a = value as? [Any] {
            for (i, v) in a.enumerated() { result.merge(flatten(v, prefix: "\(prefix)[\(i)]"), uniquingKeysWith: { _, b in b }) }
        } else if !(value is Data) { result[prefix] = String(describing: value) }
        return result
    }

}

struct ScanResult { var devices: [Battery]; var messages: [String] }

enum BatteryReader {
    static func mac() -> Battery {
        var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1)); sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let model = String(cString: bytes)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        var props: Unmanaged<CFMutableDictionary>?
        var d: [String: Any] = [:]
        if service != 0, IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS { d = props?.takeRetainedValue() as? [String: Any] ?? [:] }
        var b = BatteryParser.parse(d, id: "mac", name: Host.current().localizedName ?? "Этот Mac", model: model, connection: "Этот Mac")
        var hasInternalBattery = d["BatteryInstalled"] as? Bool == true
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                guard let desc = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any], desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                hasInternalBattery = true
                if let current = desc[kIOPSCurrentCapacityKey] as? Double, let max = desc[kIOPSMaxCapacityKey] as? Double, max > 0 { b.percent = current / max * 100 }
                b.charging = desc[kIOPSIsChargingKey] as? Bool ?? b.charging
                b.external = (desc[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue } ?? b.external
                let timeKey = b.charging == true ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
                b.minutes = (desc[timeKey] as? NSNumber).flatMap { $0.doubleValue > 0 ? $0.doubleValue : nil }
            }
        }
        if !hasInternalBattery { b.note = "Встроенная батарея не обнаружена. На настольных Mac показатели аккумулятора недоступны."; b.percent = nil; b.cycles = nil; b.amperage = nil }
        return b
    }
    static func scan() -> ScanResult {
        ScanResult(devices: [mac()], messages: [])
    }
}

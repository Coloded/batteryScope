import Foundation

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
        if let remaining = number(d, "AppleRawCurrentCapacity"), remaining.isFinite, remaining >= 0 { b.remainingCapacity = remaining }
        b.cycles = number(d, "CycleCount") ?? number(nested, "CycleCount")
        if let t = number(d, "Temperature"), t > 0 { b.temperature = t / 100 }
        if let v = number(d, "Voltage"), v > 0 { b.voltage = v / 1000 }
        for key in ["InstantAmperage", "Amperage"] {
            if let current = signedCurrent(d[key]), current.isFinite, abs(current) <= 20000 {
                b.amperage = current; b.currentSource = key; break
            }
        }
        b.charging = d["IsCharging"] as? Bool; b.external = d["ExternalConnected"] as? Bool
        if let t = number(d, "TimeRemaining"), t > 0 && t < 65535 { b.minutes = t }
        b.power = PowerReadings.read(d, external: b.external)
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

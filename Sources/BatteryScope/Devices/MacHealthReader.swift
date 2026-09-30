import Foundation

/// Reads the same maximum-capacity field exposed by System Information.
/// Kept off the five-second power polling path; missing fields remain optional.
enum MacHealthReader {
    private static let lock = NSLock()
    private static var lastAttempt = Date.distantPast
    private static var cached: (Double, Date)?

    static func parse(_ json: Any) -> Double? {
        if let dictionary = json as? [String: Any] {
            if let health = dictionary["sppower_battery_health_info"] as? [String: Any],
               let raw = health["sppower_battery_health_maximum_capacity"] {
                let text = String(describing: raw).replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Double(text), value.isFinite, (0...100).contains(value) { return value }
            }
            for value in dictionary.values { if let result = parse(value) { return result } }
        } else if let list = json as? [Any] {
            for value in list { if let result = parse(value) { return result } }
        }
        return nil
    }
    static func refreshIfNeeded() {
        lock.lock()
        guard Date().timeIntervalSince(lastAttempt) >= 600 else { lock.unlock(); return }
        lastAttempt = Date()
        lock.unlock()
        let value: Double?
        do {
            value = parse(try JSONSerialization.jsonObject(with: Command.run("system_profiler", ["SPPowerDataType", "-json"], timeout: 20)))
        } catch { value = nil }
        lock.lock(); cached = value.map { ($0, Date()) }; lock.unlock()
    }
    static func apply(to battery: inout Battery) {
        lock.lock(); let reading = cached; lock.unlock()
        guard let reading, Date().timeIntervalSince(reading.1) < 1200 else { return }
        battery.systemMaximumCapacity = reading.0
        battery.systemMaximumCapacityDate = reading.1
    }
}

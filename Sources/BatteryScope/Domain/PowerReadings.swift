import Foundation

/// Optional telemetry: old history remains decodable, unknown readings never become zero.
struct PowerReadings: Codable {
    var inputWatts: Double?
    var systemWatts: Double?
    var reportedBatteryWatts: Double?
    var adapterRatingWatts: Double?

    static func read(_ properties: [String: Any], external: Bool?) -> PowerReadings {
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        func watts(_ key: String, signed: Bool = false) -> Double? {
            guard let raw = BatteryParser.signedCurrent(telemetry[key]), raw.isFinite,
                  abs(raw) <= 1_000_000, signed || raw >= 0 else { return nil }
            return raw / 1000
        }
        let adapter = properties["AdapterDetails"] as? [String: Any] ?? [:]
        let rating = BatteryParser.number(adapter, "Watts")
        return PowerReadings(inputWatts: external == true ? watts("SystemPowerIn") : nil,
                             systemWatts: watts("SystemLoad"), reportedBatteryWatts: watts("BatteryPower", signed: true),
                             adapterRatingWatts: external == true && (rating ?? 0) > 0 && (rating ?? 0) <= 1000 ? rating : nil)
    }
}

struct LivePowerSample: Identifiable {
    let id = UUID()
    let date: Date
    let battery: Double?
    let input: Double?
    let system: Double?
}

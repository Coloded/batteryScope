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
    var power: PowerReadings? = nil
    var currentSource: String? = nil
    var remainingCapacity: Double? = nil
    var systemMaximumCapacity: Double? = nil
    var systemMaximumCapacityDate: Date? = nil
    var batteryHealth: String? = nil
    var batteryCondition: String? = nil
    var summary: [String: String]? = nil
    var hasInternalBattery: Bool? = nil
    var isAccessory: Bool { id.hasPrefix("bt:") }
    var isDesktop: Bool { (id == "mac" || id.hasPrefix("mac:")) && hasInternalBattery == false }
    var snapshotPowerState: String {
        if charging == true { return "Заряжается" }
        if external == true { return "Питание подключено" }
        if external == false { return "От аккумулятора" }
        return "Состояние питания неизвестно"
    }
    var isLive: Bool { available != false }
    var rawCapacityRatio: Double? {
        guard let full, let design, full.isFinite, design.isFinite, full > 0, design > 0 else { return nil }
        let ratio = full / design * 100
        return ratio.isFinite ? ratio : nil
    }
    var validSystemMaximumCapacity: Double? {
        guard let value = systemMaximumCapacity, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
    var health: Double? { validSystemMaximumCapacity ?? rawCapacityRatio.map { min(100, max(0, $0)) } }
    var healthSource: String { validSystemMaximumCapacity != nil ? "По данным macOS" : "Оценка по ёмкостям, не более 100%" }

    var watts: Double? {
        // Prefer the same telemetry block as system/input power. Reject a cached
        // charging value after unplugging; retain signed current as the fallback.
        if let reported = power?.reportedBatteryWatts, reported.isFinite, abs(reported) <= 1000,
           (reported > 0 && charging == true && external != false)
            || (reported < 0 && charging != true)
            || (reported == 0 && charging == false && external == true) {
            return reported
        }
        guard let voltage, let amperage, voltage.isFinite, voltage > 0,
              amperage.isFinite, abs(amperage) <= 20000 else { return nil }
        return voltage * amperage / 1000
    }

}

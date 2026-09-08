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
    var isLive: Bool { available != false }
    var health: Double? { guard let full, let design, full > 0, design > 0 else { return nil }; return full / design * 100 }
    var watts: Double? { guard let voltage, let amperage, voltage.isFinite, amperage.isFinite, abs(amperage) <= 20000 else { return nil }; return voltage * amperage / 1000 }

}

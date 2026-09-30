import Foundation
import Metal
import IOKit

/// A small, explicit configuration summary suitable for private history sync.
/// Raw diagnostics and serial numbers remain outside this payload.
enum DeviceSummary {
    static let configuration: [String: String] = {
        var fields: [String: String] = [:]
        fields["Процессор"] = SystemCapabilities.string("machdep.cpu.brand_string")
        if let cores = SystemCapabilities.integer("hw.physicalcpu") { fields["Ядра"] = String(cores)
            fields["Ядра CPU"] = String(cores) }
        if let memory = SystemCapabilities.integer("hw.memsize") { fields["Память"] = ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory) }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let count = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber, count.intValue > 0 {
                fields["Ядра GPU"] = count.stringValue
            }
        }
        let graphics = MTLCopyAllDevices().map(\.name).joined(separator: ", ")
        if !graphics.isEmpty { fields["Графика"] = graphics }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        fields["macOS"] = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return fields
    }()
    static func local() -> [String: String] {
        var result = configuration
        let states: [ProcessInfo.ThermalState: String] = [.nominal: "Нормальное", .fair: "Повышенное", .serious: "Серьёзное", .critical: "Критическое"]
        result["Тепловое состояние"] = states[ProcessInfo.processInfo.thermalState] ?? "Неизвестно"
        result["Энергосбережение"] = ProcessInfo.processInfo.isLowPowerModeEnabled ? "Включено" : "Выключено"
        return result
    }
    static func measurements(_ b: Battery) -> [String: String] {
        var values: [String: String] = [:]
        func add(_ key: String, _ value: Double?, _ unit: String, digits: Int = 1) {
            if let value { values[key] = b.value(value, suffix: unit, digits: digits) }
        }
        add("Заряд", b.percent, "%", digits: 0)
        add("Максимальная ёмкость · " + b.healthSource, b.health, "%")
        add("Отношение полной ёмкости к проектной (исходное)", b.rawCapacityRatio, "%")
        add("Остаток заряда", b.remainingCapacity, " мА·ч", digits: 0)
        add("Циклы", b.cycles, "", digits: 0)
        add("Полная ёмкость", b.full, " мА·ч", digits: 0)
        add("Проектная ёмкость", b.design, " мА·ч", digits: 0)
        add("Температура батареи", b.temperature, " °C")
        add("Напряжение", b.voltage, " В")
        add("Ток", b.amperage, " мА", digits: 0)
        add("Поток батареи", b.watts, " Вт")
        add("Потребление системы", b.power?.systemWatts, " Вт")
        add("Входная мощность", b.power?.inputWatts, " Вт")
        add("Мощность адаптера", b.power?.adapterRatingWatts, " Вт")
        for (key, value) in b.components ?? [:] { add(key, value, "%", digits: 0) }
        if let charging = b.charging { values["Заряжается"] = charging ? "Да" : "Нет" }
        if let external = b.external { values["Внешнее питание"] = external ? "Да" : "Нет" }
        if let date = b.systemMaximumCapacityDate { values["Время чтения максимальной ёмкости macOS"] = date.formatted() }
        values["Состояние батареи по macOS"] = b.batteryHealth
        values["Условие обслуживания по macOS"] = b.batteryCondition
        return values
    }
}

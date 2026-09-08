import Foundation
import Metal

/// Documented capability queries with missing-key fallbacks for Intel and older systems.
enum SystemCapabilities {
    static func integer(_ key: String) -> UInt64? {
        var bytes: UInt64 = 0; var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return bytes
    }
    static func string(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 1024 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
    static func sections() -> [String: [String: String]] {
        var cpu: [String: String] = [:]
        for (key, label) in [("hw.physicalcpu", "Физические ядра"), ("hw.logicalcpu", "Логические ядра"), ("hw.memsize", "Оперативная память, байт"), ("hw.l1icachesize", "Кэш инструкций L1, байт"), ("hw.l1dcachesize", "Кэш данных L1, байт"), ("hw.l2cachesize", "Кэш L2, байт"), ("hw.l3cachesize", "Кэш L3, байт")] {
            if let n = integer(key) { cpu[label] = String(n) }
        }
        let levels = min(integer("hw.nperflevels") ?? 0, 8)
        for index in 0..<levels {
            let prefix = "hw.perflevel\(index)"
            let name = string(prefix + ".name") ?? "Уровень \(index)"
            for (key, label) in [("physicalcpu", "физические ядра"), ("logicalcpu", "логические ядра"), ("l2cachesize", "кэш L2, байт")] {
                if let n = integer(prefix + "." + key) { cpu[name + " · " + label] = String(n) }
            }
        }
        var result = ["Возможности процессора и памяти": cpu]
        for (index, gpu) in MTLCopyAllDevices().enumerated() {
            var fields = ["Имя GPU": gpu.name, "Общая память с CPU": gpu.hasUnifiedMemory ? "Да" : "Нет", "Рекомендуемый бюджет ресурсов GPU, байт": String(gpu.recommendedMaxWorkingSetSize), "Съёмный GPU": gpu.isRemovable ? "Да" : "Нет"]
            var families: [String] = []
            for (family, name) in [(MTLGPUFamily.mac2, "Mac 2"), (.apple7, "Apple 7"), (.apple8, "Apple 8"), (.metal3, "Metal 3")] {
                if gpu.supportsFamily(family) { families.append(name) }
            }
            if #available(macOS 14, *), gpu.supportsFamily(.apple9) { families.append("Apple 9") }
            if #available(macOS 26, *), gpu.supportsFamily(.apple10) { families.append("Apple 10") }
            fields["Поддерживаемые семейства Metal"] = families.joined(separator: ", ")
            result["Возможности GPU \(index + 1)"] = fields
        }
        return result
    }
}

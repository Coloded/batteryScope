import Foundation

struct TechnicalRecord: Codable {
    var deviceID: String
    var date = Date()
    var sections: [String: [String: String]]
    var notes: [String] = []
}

enum TechnicalReader {
    // Lockdown also exposes account/telephony data; those are not hardware specifications.
    static func hardwareFields(_ input: [String: Any]) -> [String: String] {
        BatteryParser.flatten(input).filter { key, _ in
            let k = key.lowercased()
            return !["phonenumber", "subscriber", "integratedcircuitcard", "keyhash", "masterkey", "ticket", "nonvolatileram", "pkhash", "carrierbundle", "postponement"].contains { k.contains($0) }
        }
    }
    static func read(_ b: Battery) -> TechnicalRecord {
        var record = TechnicalRecord(deviceID: b.id, sections: ["Устройство": ["Имя": b.name, "Модель": b.model, "Соединение": b.connection], "Аккумулятор и диагностика": b.details])
        guard b.isLive else { record.notes = ["Устройство отключено. Доступны только ранее полученные сведения; свежие запросы не выполнялись."]; return record }
        if b.id == "mac" {
            do {
                let data = try Command.run("system_profiler", ["SPHardwareDataType", "SPSoftwareDataType", "SPMemoryDataType", "SPDisplaysDataType", "SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType", "SPThunderboltDataType", "SPAudioDataType", "SPPowerDataType", "-json"], timeout: 45)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let labels = ["SPHardwareDataType": "Процессор и аппаратная платформа", "SPSoftwareDataType": "Операционная система", "SPMemoryDataType": "Оперативная память", "SPDisplaysDataType": "Графика и дисплеи", "SPNVMeDataType": "Накопители NVMe", "SPSerialATADataType": "Накопители SATA", "SPUSBDataType": "USB", "SPThunderboltDataType": "Thunderbolt", "SPAudioDataType": "Аудио", "SPPowerDataType": "Питание"]
                for (key, value) in json { record.sections[labels[key] ?? key] = BatteryParser.flatten(value) }
            } catch { record.notes.append(error.localizedDescription) }
        } else if b.id.hasPrefix("bt:") {
            record.sections["Bluetooth и прошивка"] = b.details
            record.sections.removeValue(forKey: "Аккумулятор и диагностика")
            record.notes.append("Аксессуары раскрывают только характеристики, доступные macOS. Проектная ёмкость, циклы и внутренние компоненты часто не предоставляются.")
        } else {
            let args = ["-u", b.id] + (b.connection == "Wi-Fi" ? ["-n"] : [])
            do {
                let info = try Command.plist("ideviceinfo", args + ["-x"]) as? [String: Any] ?? [:]
                record.sections["Аппаратная платформа, ОС и прошивки"] = hardwareFields(info)
            } catch { record.notes.append(error.localizedDescription) }
            for (domain, label) in [("com.apple.disk_usage", "Накопитель и свободное место"), ("com.apple.disk_usage.factory", "Разделы накопителя")] {
                do {
                    let info = try Command.plist("ideviceinfo", args + ["-q", domain, "-x"]) as? [String: Any] ?? [:]
                    let flat = hardwareFields(info)
                    if !flat.isEmpty { record.sections[label] = flat } else { record.notes.append("\(label): ОС не предоставила сведения.") }
                } catch { record.notes.append("\(label): \(error.localizedDescription)") }
            }
            record.notes.append("Показаны все полученные технические поля. Если iOS не раскрывает размер RAM, параметры дисплея или камеры, они не добавляются из предположений. Телефонный номер, данные SIM и служебные ключи исключены из характеристик.")
        }
        return record
    }
}

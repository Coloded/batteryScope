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
        if !b.isLive && !b.isAccessory {
            record.date = b.date
            record.sections.removeValue(forKey: "Аккумулятор и диагностика")
            if let summary = b.summary, !summary.isEmpty { record.sections["Конфигурация и состояние"] = summary }
            let measurements = DeviceSummary.measurements(b)
            if !measurements.isEmpty { record.sections["Питание · сохранённое измерение"] = measurements }
            record.notes = ["Сохранённый снимок от \(b.date.formatted()). Новые сведения поступят после обновления и обмена на исходном Mac."]
            if b.summary == nil { record.notes.append("Этот снимок создан без конфигурации. Для её передачи установите новую версию на исходном Mac и сохраните новый снимок.") }
            return record
        }
        if b.id.hasPrefix("bt:") {
            record.date = b.date
            let power = b.details.filter { $0.key.localizedCaseInsensitiveContains("battery") || $0.key == "HasBattery" }
            record.sections["Питание аксессуара"] = power.filter { !$0.key.hasSuffix("NotificationType") }
            record.sections["Системные уведомления · не текущие ошибки"] = power.filter { $0.key.hasSuffix("NotificationType") }
            record.sections["Bluetooth и прошивка"] = b.details.filter { power[$0.key] == nil }
            record.sections.removeValue(forKey: "Аккумулятор и диагностика")
            record.notes = [b.isLive
                ? "Последние данные macOS. Время чтения не является временем измерения заряда: macOS может хранить последнее сообщённое значение."
                : "Устройство отключено. Показан кэш macOS; время измерения заряда неизвестно."]
            return record
        }
        guard b.isLive else { record.notes = ["Устройство отключено. Доступны только ранее полученные сведения; свежие запросы не выполнялись."]; return record }
        if b.id == "mac" {
            record.sections.merge(SystemCapabilities.sections(), uniquingKeysWith: { _, fresh in fresh })
            do {
                let data = try Command.run("system_profiler", ["SPHardwareDataType", "SPSoftwareDataType", "SPMemoryDataType", "SPDisplaysDataType", "SPNVMeDataType", "SPSerialATADataType", "SPUSBDataType", "SPThunderboltDataType", "SPAudioDataType", "SPPowerDataType", "-json"], timeout: 45)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let labels = ["SPHardwareDataType": "Процессор и аппаратная платформа", "SPSoftwareDataType": "Операционная система", "SPMemoryDataType": "Оперативная память", "SPDisplaysDataType": "Графика и дисплеи", "SPNVMeDataType": "Накопители NVMe", "SPSerialATADataType": "Накопители SATA", "SPUSBDataType": "USB", "SPThunderboltDataType": "Thunderbolt", "SPAudioDataType": "Аудио", "SPPowerDataType": "Питание"]
                for (key, value) in json { record.sections[labels[key] ?? key] = BatteryParser.flatten(value) }
            } catch { record.notes.append(error.localizedDescription) }
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

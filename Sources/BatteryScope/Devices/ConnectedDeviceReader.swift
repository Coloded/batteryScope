import Foundation
import IOKit

enum DeviceParser {
    static func batteryDictionary(_ value: Any) -> [String: Any]? {
        if let d = value as? [String: Any] {
            if d["CycleCount"] != nil || d["DesignCapacity"] != nil || d["AppleRawMaxCapacity"] != nil { return d }
            for key in d.keys.sorted() { if let result = batteryDictionary(d[key]!) { return result } }
        } else if let a = value as? [Any] { for child in a { if let result = batteryDictionary(child) { return result } } }
        return nil
    }
    static func mobile(id: String, info: [String: Any], basic: [String: Any], diagnostics: Any, network: Bool) -> Battery {
        let d = batteryDictionary(diagnostics) ?? [:]
        var b = BatteryParser.parse(d, id: id, name: info["DeviceName"] as? String ?? "Apple-устройство", model: info["ProductType"] as? String ?? "iOS / iPadOS", connection: network ? "Wi-Fi" : "USB")
        if let level = BatteryParser.number(basic, "BatteryCurrentCapacity"), (0...100).contains(level) { b.percent = level }
        b.charging = basic["BatteryIsCharging"] as? Bool ?? b.charging
        b.external = basic["ExternalConnected"] as? Bool ?? b.external
        for key in ["ProductVersion", "BuildVersion", "ProductType", "DeviceClass", "HardwareModel", "SerialNumber"] { if let v = info[key] { b.details[key] = String(describing: v) } }
        if b.health == nil { b.note = "Устройство не предоставило данные об износе. Доступные показатели показаны ниже." }
        if basic["HasBattery"] as? Bool == false { b.note = "Устройство сообщает, что встроенной батареи нет." }
        return b
    }
    static func address(_ text: String) -> String { text.lowercased().replacingOccurrences(of: "-", with: ":") }
    static func percentage(_ value: Any?) -> Double? {
        guard let value else { return nil }
        let text = String(describing: value).filter { "0123456789.".contains($0) }
        guard let n = Double(text), (0...100).contains(n) else { return nil }; return n
    }
    static func bluetooth(_ json: Any, hid: [[String: Any]]) -> [Battery] {
        var result: [Battery] = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for key in ["device_connected", "device_not_connected"] {
                    guard let entries = dict[key] as? [[String: Any]] else { continue }
                    let live = key == "device_connected"
                    for entry in entries {
                        for (name, value) in entry {
                            guard let fields = value as? [String: Any], let addr = fields["device_address"] as? String else { continue }
                            guard (fields["device_vendorID"] as? String)?.hasPrefix("0x004C") == true else { continue }
                            let type = fields["device_minorType"] as? String ?? "Apple accessory"
                            // Phones and other Macs belong to the USB/network provider, not cached Bluetooth discovery.
                            guard ["Keyboard", "Magic Trackpad", "Mouse", "Headphones"].contains(type) || name.contains("AirPods") || name.contains("Magic") || name.contains("Beats") else { continue }
                            let normalized = address(addr)
                            var b = Battery(id: "bt:" + normalized, name: name, model: type, connection: live ? "Bluetooth" : "Не подключено")
                            b.available = live
                            b.details = BatteryParser.flatten(fields)
                            var parts: [String: Double] = [:]
                            for (key, title) in [("device_batteryLevelLeft", "Левый наушник"), ("device_batteryLevelRight", "Правый наушник"), ("device_batteryLevelCase", "Футляр"), ("device_batteryLevelMain", "Аккумулятор")] {
                                if let level = percentage(fields[key]) { parts[title] = level }
                            }
                            b.components = parts.isEmpty ? nil : parts
                            if live {
                                let match = hid.first { address($0["DeviceAddress"] as? String ?? $0["SerialNumber"] as? String ?? "") == normalized }
                                b.percent = percentage(match?["BatteryPercent"]) ?? percentage(fields["device_batteryLevelMain"])
                                if let match { b.details.merge(BatteryParser.flatten(match), uniquingKeysWith: { _, new in new }) }
                                b.note = "Последние данные macOS. Значение заряда может быть сохранённым; время самого измерения неизвестно."
                            } else {
                                b.note = "Устройство отключено. Показания ниже — кэш macOS; время измерения неизвестно. Они не сохраняются в историю и не вызывают уведомлений."
                            }
                            result.append(b)
                        }
                    }
                }
                for (key, child) in dict where key != "device_connected" && key != "device_not_connected" { walk(child) }
            } else if let list = value as? [Any] { for child in list { walk(child) } }
        }
        walk(json)
        return result.sorted { a, b in a.isLive != b.isLive ? a.isLive : a.name < b.name }
    }
}

enum DeviceReader {
    static func mobile(network: Bool) -> ScanResult {
        var result = ScanResult(devices: [], messages: [])
        guard ["idevice_id", "ideviceinfo", "idevicediagnostics"].allSatisfy({ Command.path($0) != nil }) else {
            result.messages = ["Не найдены встроенные утилиты iPhone/iPad. Переустановите последнюю версию BatteryScope из официального релиза."]
            return result
        }
        var seen = Set<String>()
        for wireless in network ? [false, true] : [false] {
            do {
                let data = try Command.run("idevice_id", [wireless ? "-n" : "-l"])
                let ids = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
                for id in ids where !seen.contains(id) {
                    let args = ["-u", id] + (wireless ? ["-n"] : [])
                    do {
                        let info = try Command.plist("ideviceinfo", args + ["-x"]) as? [String: Any] ?? [:]
                        let basic = (try? Command.plist("ideviceinfo", args + ["-q", "com.apple.mobile.battery", "-x"])) as? [String: Any] ?? [:]
                        var diagnostics: Any = [:]
                        var diagnosticError: String?
                        do {
                            diagnostics = try Command.plist("idevicediagnostics", args + ["ioregentry", "AppleSmartBattery"])
                            if DeviceParser.batteryDictionary(diagnostics) == nil { diagnostics = try Command.plist("idevicediagnostics", args + ["diagnostics", "GasGauge"]) }
                        } catch { diagnosticError = error.localizedDescription }
                        var b = DeviceParser.mobile(id: id, info: info, basic: basic, diagnostics: diagnostics, network: wireless)
                        if let diagnosticError { b.note = "Подробная диагностика недоступна: \(diagnosticError)" }
                        result.devices.removeAll { $0.id == id }; result.devices.append(b); seen.insert(id)
                    } catch {
                        if !result.devices.contains(where: { $0.id == id }) {
                            var b = Battery(id: id, name: "Apple-устройство", model: "Ожидает доступа", connection: wireless ? "Wi-Fi" : "USB")
                            b.available = false
                            b.note = "Разблокируйте устройство и подтвердите «Доверять этому компьютеру», затем обновите. \(error.localizedDescription)"
                            result.devices.append(b)
                        }
                    }
                }
            } catch { result.messages.append("\(wireless ? "Wi-Fi" : "USB"): \(error.localizedDescription)") }
        }
        return result
    }
    static func accessories() -> ScanResult {
        do {
            let json = try JSONSerialization.jsonObject(with: Command.run("system_profiler", ["SPBluetoothDataType", "-json"], timeout: 20))
            var hid: [[String: Any]] = []
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                while case let service = IOIteratorNext(iterator), service != 0 {
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS, let d = props?.takeRetainedValue() as? [String: Any] { hid.append(d) }
                    IOObjectRelease(service)
                }
            }
            return ScanResult(devices: DeviceParser.bluetooth(json, hid: hid), messages: [])
        } catch { return ScanResult(devices: [], messages: ["Bluetooth: \(error.localizedDescription)"]) }
    }
    static func scan(network: Bool, bluetooth: Bool) async -> ScanResult {
        let generation = CommandActivity.shared.generation
        async let mobileResult = Task.detached(priority: .utility) {
            Command.$generation.withValue(generation) { mobile(network: network) }
        }.value
        async let accessoryResult = Task.detached(priority: .utility) {
            Command.$generation.withValue(generation) { bluetooth ? accessories() : ScanResult(devices: [], messages: []) }
        }.value
        let local = await Task.detached(priority: .utility) {
            Command.$generation.withValue(generation) {
                var battery = BatteryReader.mac()
                if battery.hasInternalBattery == true {
                    MacHealthReader.refreshIfNeeded()
                    MacHealthReader.apply(to: &battery)
                }
                return battery
            }
        }.value
        let (phones, peripherals) = await (mobileResult, accessoryResult)
        return ScanResult(devices: [local] + phones.devices + peripherals.devices, messages: phones.messages + peripherals.messages)
    }
}

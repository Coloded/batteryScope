import Foundation
import IOKit
import IOKit.ps

struct ScanResult { var devices: [Battery]; var messages: [String] }

enum BatteryReader {
    static func mac() -> Battery {
        var size = 0; sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1)); sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let model = String(cString: bytes)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { if service != 0 { IOObjectRelease(service) } }
        var props: Unmanaged<CFMutableDictionary>?
        var d: [String: Any] = [:]
        if service != 0, IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS { d = props?.takeRetainedValue() as? [String: Any] ?? [:] }
        var b = BatteryParser.parse(d, id: "mac", name: Host.current().localizedName ?? "Этот Mac", model: model, connection: "Этот Mac")
        var hasInternalBattery = d["BatteryInstalled"] as? Bool == true
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                guard let desc = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any], desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                hasInternalBattery = true
                if let current = desc[kIOPSCurrentCapacityKey] as? Double, let max = desc[kIOPSMaxCapacityKey] as? Double, max > 0 { b.percent = current / max * 100 }
                b.charging = desc[kIOPSIsChargingKey] as? Bool ?? b.charging
                b.external = (desc[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue } ?? b.external
                let timeKey = b.charging == true ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
                b.minutes = (desc[timeKey] as? NSNumber).flatMap { $0.doubleValue > 0 ? $0.doubleValue : nil }
            }
        }
        b.power = PowerReadings.read(d, external: b.external)
        if !hasInternalBattery { b.note = "Встроенная батарея не обнаружена. На настольных Mac показатели аккумулятора недоступны."; b.percent = nil; b.cycles = nil; b.amperage = nil }
        return b
    }
    static func scan() -> ScanResult {
        ScanResult(devices: [mac()], messages: [])
    }
}

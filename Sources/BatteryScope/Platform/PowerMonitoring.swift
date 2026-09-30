import Foundation
import AppKit
import IOKit.ps

/// System callbacks only trigger a lightweight Mac read, never a full peripheral scan.
final class PowerEventMonitor {
    private var source: CFRunLoopSource?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerEventMonitor>.fromOpaque(context).takeUnretainedValue().onChange()
        }
        source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            let center = NotificationCenter.default
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in onChange() }))
        }
    }
    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        for (center, token) in observers { center.removeObserver(token) }
    }
}

extension Store {
    func updateSystemCondition() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: systemCondition = "Тепловое состояние: нормальное"
        case .fair: systemCondition = "Тепловое состояние: повышенное"
        case .serious: systemCondition = "Тепловое состояние: серьёзное"
        case .critical: systemCondition = "Тепловое состояние: критическое"
        @unknown default: systemCondition = "Тепловое состояние неизвестно"
        }
    }
    var reducedPolling: Bool {
        lowPowerMode || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
    }
    func scheduledRefresh() async {
        guard !sleeping else { return }
        updateSystemCondition()
        if !reducedPolling || Date().timeIntervalSince(lastPeripheralScan) >= 300 { await refresh() }
        else {
            await refreshMac()
            if historySyncEnabled && Date().timeIntervalSince(lastSyncAttempt) >= 300 { await syncHistory() }
        }
    }
    func refreshMac() async {
        guard !sleeping, !macRefreshBusy, Date().timeIntervalSince(lastMacRead) > 0.5 else { return }
        let generation = workGeneration
        macRefreshBusy = true
        defer { macRefreshBusy = false }
        updateSystemCondition()
        let battery = await Task.detached(priority: .utility) { BatteryReader.mac() }.value
        guard !sleeping, generation == workGeneration else { return }
        let previous = history.filter { $0.battery.id == "mac" }.max { $0.battery.date < $1.battery.date }?.battery
        let powerChanged = previous.map { $0.external != battery.external || $0.charging != battery.charging } ?? false
        lastMacRead = Date()
        if let index = devices.firstIndex(where: { $0.id == "mac" }) { devices[index] = battery }
        else { devices.insert(battery, at: 0) }
        livePower.append(LivePowerSample(date: battery.date, battery: battery.watts, input: battery.power?.inputWatts, system: battery.power?.systemWatts))
        livePower.removeAll { Date().timeIntervalSince($0.date) > 1800 }
        if livePower.count > 500 { livePower.removeFirst(livePower.count - 500) }
        if powerChanged && historySyncEnabled {
            saveSyncSnapshots()
            Task { await syncHistory() }
        }
    }
}

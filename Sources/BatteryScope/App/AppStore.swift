import SwiftUI
import UserNotifications
import AppKit

@MainActor final class Store: ObservableObject {
    @Published var sleeping = false
    var sleepObservers: [NSObjectProtocol] = []
    var workGeneration = UUID()
    @Published var devices: [Battery] = []
    @Published var history: [Sample] = []
    @Published var messages: [String] = []
    @Published var busy = false
    @Published var selected = "mac"
    @Published var page = "Обзор"
    @Published var error: String?
    @Published var storageDetails = "Нажмите «Прочитать данные накопителей»."
    @Published var storageBusy = false
    @Published var technical: [String: TechnicalRecord] = [:]
    @Published var technicalBusy = Set<String>()
    @Published var wifi: Bool = UserDefaults.standard.object(forKey: "wifi") == nil ? true : UserDefaults.standard.bool(forKey: "wifi") {
        didSet { UserDefaults.standard.set(wifi, forKey: "wifi") }
    }
    @Published var bluetooth: Bool = UserDefaults.standard.object(forKey: "bluetooth") == nil ? true : UserDefaults.standard.bool(forKey: "bluetooth") {
        didSet { UserDefaults.standard.set(bluetooth, forKey: "bluetooth") }
    }
    @Published var alerts: Bool = UserDefaults.standard.object(forKey: "alerts") == nil ? false : UserDefaults.standard.bool(forKey: "alerts") {
        didSet { UserDefaults.standard.set(alerts, forKey: "alerts") }
    }
    @Published var threshold: Double = UserDefaults.standard.object(forKey: "threshold") == nil ? 20.0 : UserDefaults.standard.double(forKey: "threshold") {
        didSet { UserDefaults.standard.set(threshold, forKey: "threshold") }
    }
    @Published var timeThreshold: Double = UserDefaults.standard.object(forKey: "timeThreshold") == nil ? 15.0 : UserDefaults.standard.double(forKey: "timeThreshold") {
        didSet { UserDefaults.standard.set(timeThreshold, forKey: "timeThreshold") }
    }
    @Published var reportTemplate: String = UserDefaults.standard.string(forKey: "reportTemplate") ?? Export.template {
        didSet { UserDefaults.standard.set(reportTemplate, forKey: "reportTemplate") }
    }
    @Published var historySyncEnabled: Bool = UserDefaults.standard.object(forKey: "historySyncEnabled") == nil ? false : UserDefaults.standard.bool(forKey: "historySyncEnabled") {
        didSet { UserDefaults.standard.set(historySyncEnabled, forKey: "historySyncEnabled") }
    }
    @Published var syncPeers: [SyncPeer] = []
    @Published var syncBusy = false
    @Published var syncStatus = UserDefaults.standard.string(forKey: "historySyncLastStatus") ?? "Обмен историей ещё не выполнялся." {
        didSet { UserDefaults.standard.set(syncStatus, forKey: "historySyncLastStatus") }
    }
    @Published var syncFolderName: String = UserDefaults.standard.string(forKey: "historySyncFolderName") ?? "Папка не выбрана" {
        didSet { UserDefaults.standard.set(syncFolderName, forKey: "historySyncFolderName") }
    }
    var syncWorker: Task<HistorySyncResult, Error>?
    var syncGeneration = UUID()
    var syncRestartRequested = false
    var lastSyncAttempt = Date.distantPast
    var notified = Set<String>()
    @Published var lowPowerMode = false
    @Published var systemCondition = "Тепловое состояние: нормальное"
    @Published var livePower: [LivePowerSample] = []
    var powerMonitor: PowerEventMonitor?
    var powerTimer: Timer?
    var macRefreshBusy = false
    var lastMacRead = Date.distantPast
    var lastPeripheralScan = Date.distantPast
    var timer: Timer?
    var lastSaved: [String: Date] = [:]
    var database: HistoryDatabase?
    let databaseURL: URL
    var current: Battery? {
        knownDevices.first(where: { $0.id == selected })
    }
    var knownDevices: [Battery] {
        var result = devices
        var seen = Set(devices.map(\.id))
        for sample in history.sorted(by: { $0.battery.date > $1.battery.date }) where seen.insert(sample.battery.id).inserted {
            var archived = sample.battery
            archived.available = false
            archived.connection = sample.sourceMacID.map { $0 != LocalMacIdentity.id } == true ? "Из iCloud" : "Сохранённые данные"
            archived.note = "Последнее измерение: \(archived.date.formatted()). Для новых данных нажмите «Обновить» на исходном Mac; для истории другого Mac также выполните обмен iCloud."
            result.append(archived)
        }
        return result
    }
    var samples: [Sample] { history.filter { $0.battery.id == selected } }
    var menuTitle: String {
        let device = (current?.isLive == true && current?.percent != nil) ? current : devices.first { $0.isLive && $0.percent != nil }
        return device.map { $0.value($0.percent, suffix: "%") } ?? ""
    }

    init(historyFolder: URL? = nil, observeSystemEvents: Bool = true) {
        let folder = historyFolder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BatteryScope")
        databaseURL = folder.appendingPathComponent("BatteryScope.sqlite")
        do {
            database = try HistoryDatabase(url: databaseURL, legacyURL: folder.appendingPathComponent("history.json"))
            history = try database!.load()
        } catch { self.error = "Не удалось открыть базу: \(error.localizedDescription). Старый JSON сохранён без изменений." }
        for sample in history { lastSaved[sample.battery.id] = max(lastSaved[sample.battery.id] ?? .distantPast, sample.battery.date) }
        updateSystemCondition()
        if observeSystemEvents { observeSleep() }
        configurePolling()
    }

    func refresh(forceSync: Bool = false) async {
        guard !sleeping, !busy else { return }; busy = true
        let generation = workGeneration
        defer { busy = false }
        // Receive cloud history before a potentially slow peripheral scan.
        if forceSync && historySyncEnabled {
            await refreshMac()
            await syncHistory(forceSnapshot: true)
            guard !sleeping, generation == workGeneration else { return }
        }
        let result = await DeviceReader.scan(network: wifi, bluetooth: bluetooth)
        guard !sleeping, generation == workGeneration else { return }
        devices = result.devices; messages = result.messages
        updateAccessoryTechnicalRecords()
        lastPeripheralScan = Date(); await refreshMac()
        await notifyBatteryWear()
        if current == nil { selected = "mac" }
        for b in devices where b.isLive && (b.id == "mac" || b.percent != nil || b.components?.isEmpty == false) {
            if Date().timeIntervalSince(lastSaved[b.id] ?? .distantPast) >= 3600 || (b.id == "mac" && history.last(where: { $0.battery.id == "mac" })?.battery.summary == nil) { save(b) }
            let low = b.percent.map { $0 <= threshold } == true || (b.id == "mac" && b.minutes.map { $0 <= timeThreshold } == true)
            if !low || b.external == true { notified.remove(b.id) }
            if alerts && low && b.external != true && b.charging != true && !notified.contains(b.id) {
                let content = UNMutableNotificationContent(); content.title = "\(b.name): низкий заряд"; content.body = "Заряд: \(b.value(b.percent, suffix: "%")). Подключите питание."
                do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "battery-" + b.id, content: content, trigger: nil)); notified.insert(b.id) }
                catch { self.error = error.localizedDescription }
            }
        }
        if !sleeping && historySyncEnabled && (forceSync || Date().timeIntervalSince(lastSyncAttempt) >= 300) {
            await syncHistory(forceSnapshot: forceSync)
        }
    }
    func save(_ battery: Battery) {
        guard battery.isLive else { return }
        guard let database else { error = "База SQLite недоступна. Перезапустите приложение после исправления ошибки доступа."; return }
        var snapshot = battery
        snapshot.details = [:]
        let sample = Sample(battery: snapshot, sourceMacID: LocalMacIdentity.id, sourceMacName: LocalMacIdentity.name)
        do {
            try database.append(sample)
            history.append(sample)
            lastSaved[battery.id] = Date()
        } catch { self.error = "Ошибка сохранения истории: \(error.localizedDescription)" }
    }
    func enableAlerts(_ enabled: Bool) {
        alerts = enabled
        if enabled { Task {
            do { alerts = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); if !alerts { error = "Уведомления запрещены. Разрешите их для BatteryScope в настройках macOS." } }
            catch { alerts = false; self.error = error.localizedDescription }
        } }
    }
}

import SwiftUI
import UserNotifications
import AppKit

@MainActor final class Store: ObservableObject {
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
    @AppStorage("wifi") var wifi = true
    @AppStorage("bluetooth") var bluetooth = true
    @AppStorage("alerts") var alerts = false
    @AppStorage("threshold") var threshold = 20.0
    @AppStorage("timeThreshold") var timeThreshold = 15.0
    @AppStorage("reportTemplate") var reportTemplate = Export.template
    @AppStorage("historySyncEnabled") var historySyncEnabled = false
    @Published var syncBusy = false
    @Published var syncStatus = "Обмен историей ещё не выполнялся."
    @AppStorage("historySyncFolderName") var syncFolderName = "Папка не выбрана"
    private var syncWorker: Task<HistorySyncResult, Error>?
    private var syncGeneration = UUID()
    private var lastSyncAttempt = Date.distantPast
    private var notified = Set<String>()
    private var timer: Timer?
    private var lastSaved: [String: Date] = [:]
    private var database: HistoryDatabase?
    let databaseURL: URL
    var current: Battery? {
        knownDevices.first(where: { $0.id == selected })
    }
    var knownDevices: [Battery] {
        var result = devices
        var seen = Set(devices.map(\.id))
        for sample in history.reversed() where seen.insert(sample.battery.id).inserted {
            var archived = sample.battery
            archived.available = false
            archived.connection = "История · " + (sample.sourceMacName ?? "этот Mac")
            archived.note = "Последнее измерение: \(archived.date.formatted()). Новые данные появятся после запуска BatteryScope на исходном Mac и доставки файлов iCloud."
            result.append(archived)
        }
        return result
    }
    var samples: [Sample] { history.filter { $0.battery.id == selected } }
    var menuTitle: String {
        let device = (current?.isLive == true && current?.percent != nil) ? current : devices.first { $0.isLive && $0.percent != nil }
        return device.map { $0.value($0.percent, suffix: "%") } ?? ""
    }

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BatteryScope")
        databaseURL = folder.appendingPathComponent("BatteryScope.sqlite")
        do {
            database = try HistoryDatabase(url: databaseURL, legacyURL: folder.appendingPathComponent("history.json"))
            history = try database!.load()
        } catch { self.error = "Не удалось открыть базу: \(error.localizedDescription). Старый JSON сохранён без изменений." }
        for sample in history { lastSaved[sample.battery.id] = max(lastSaved[sample.battery.id] ?? .distantPast, sample.battery.date) }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
    }
    func refresh() async {
        guard !busy else { return }; busy = true
        let result = await DeviceReader.scan(network: wifi, bluetooth: bluetooth)
        devices = result.devices; messages = result.messages; busy = false
        if current == nil { selected = "mac" }
        for b in devices where b.isLive && (b.id == "mac" || b.percent != nil || b.components?.isEmpty == false) {
            if Date().timeIntervalSince(lastSaved[b.id] ?? .distantPast) >= 3600 { save(b) }
            let low = b.percent.map { $0 <= threshold } == true || (b.id == "mac" && b.minutes.map { $0 <= timeThreshold } == true)
            if !low || b.external == true { notified.remove(b.id) }
            if alerts && low && b.external != true && b.charging != true && !notified.contains(b.id) {
                let content = UNMutableNotificationContent(); content.title = "\(b.name): низкий заряд"; content.body = "Заряд: \(b.value(b.percent, suffix: "%")). Подключите питание."
                do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "battery-" + b.id, content: content, trigger: nil)); notified.insert(b.id) }
                catch { self.error = error.localizedDescription }
            }
        }
        if historySyncEnabled && Date().timeIntervalSince(lastSyncAttempt) >= 300 {
            await syncHistory()
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
    func setHistorySyncEnabled(_ enabled: Bool) {
        syncGeneration = UUID()
        syncWorker?.cancel()
        historySyncEnabled = enabled
        if !enabled { syncStatus = "Обмен выключен. Локальная история и файлы в общей папке сохранены."; return }
        if UserDefaults.standard.data(forKey: "historySyncFolderBookmark") == nil { chooseHistorySyncFolder() }
        else { Task { await syncHistory() } }
    }
    func chooseHistorySyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.prompt = "Выбрать для истории"
        panel.message = "Выберите одну и ту же папку в iCloud Drive на всех Mac. В неё будут записаны история измерений, имена и идентификаторы устройств. Подробная диагностика останется на этом Mac."
        guard panel.runModal() == .OK, let folder = panel.url else {
            if UserDefaults.standard.data(forKey: "historySyncFolderBookmark") == nil { historySyncEnabled = false }
            return
        }
        do {
            let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            syncGeneration = UUID(); syncWorker?.cancel()
            UserDefaults.standard.set(bookmark, forKey: "historySyncFolderBookmark")
            syncFolderName = folder.path; historySyncEnabled = true
            Task { await syncHistory() }
        } catch { self.error = "Не удалось запомнить папку: \(error.localizedDescription)" }
    }
    func syncHistory() async {
        guard historySyncEnabled, !syncBusy, let database else { return }
        syncBusy = true; lastSyncAttempt = Date()
        let generation = syncGeneration
        defer {
            syncBusy = false; syncWorker = nil
            // A changed folder must wait for the previous coordinated operation to finish.
            if generation != syncGeneration && historySyncEnabled { Task { await syncHistory() } }
        }
        do {
            guard let bookmark = UserDefaults.standard.data(forKey: "historySyncFolderBookmark") else {
                throw ReaderError.message("Выберите общую папку истории в настройках.")
            }
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale { throw ReaderError.message("Доступ к папке изменился. Выберите её заново в настройках.") }
            syncStatus = "Читаем и записываем файлы общей истории…"
            let snapshots = history, macID = LocalMacIdentity.id, macName = LocalMacIdentity.name
            let worker = Task.detached(priority: .utility) {
                try HistoryFolderSync.exchange(folder: folder, samples: snapshots, macID: macID, macName: macName)
            }
            syncWorker = worker
            let result = try await worker.value
            guard historySyncEnabled, generation == syncGeneration else { return }
            try database.merge(result.incoming)
            history = try database.load()
            for sample in history { lastSaved[sample.battery.id] = max(lastSaved[sample.battery.id] ?? .distantPast, sample.battery.date) }
            syncStatus = "\(Date().formatted()): записано файлов \(result.written), получено снимков \(result.incoming.count). Доставкой на другие Mac управляет iCloud."
            if result.waiting > 0 { syncStatus += " Ожидают загрузки: \(result.waiting)." }
            if !result.issues.isEmpty { syncStatus += " Проблемы с файлами (\(result.issues.count)): " + result.issues.prefix(3).joined(separator: "; ") }
        } catch {
            guard historySyncEnabled, generation == syncGeneration else { return }
            syncStatus = "Обмен не завершён: \(error.localizedDescription). Повторим автоматически; локальная история сохранена."
        }
    }
    func readTechnical(force: Bool = false) async {
        guard let device = current, !technicalBusy.contains(device.id) else { return }
        if !force {
            if technical[device.id] != nil { return }
            do { if let record = try database?.loadTechnical(device.id) { technical[device.id] = record; return } }
            catch { self.error = error.localizedDescription }
        }
        technicalBusy.insert(device.id)
        let record = await Task.detached(priority: .utility) { TechnicalReader.read(device) }.value
        technical[device.id] = record; technicalBusy.remove(device.id)
        do { try database?.saveTechnical(record) } catch { self.error = error.localizedDescription }
    }
    func exportTechnical() {
        guard let record = technical[selected] else { return }
        do {
            write(String(decoding: try FieldLabels.export(record), as: UTF8.self), name: "BatteryScope-specifications.json")
        } catch { self.error = error.localizedDescription }
    }
    func enableAlerts(_ enabled: Bool) {
        alerts = enabled
        if enabled { Task {
            do { alerts = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); if !alerts { error = "Уведомления запрещены. Разрешите их для BatteryScope в настройках macOS." } }
            catch { alerts = false; self.error = error.localizedDescription }
        } }
    }
    func exportCSV(all: Bool = false) { write(Export.csv(all ? history : samples), name: "BatteryScope-history.csv") }
    func exportReport() { if let b = current { write(Export.report(b, template: reportTemplate), name: "BatteryScope-report.html") } }
    func write(_ text: String, name: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url { do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
    func printReport() {
        guard let b = current else { return }
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        let html = Export.report(b, template: reportTemplate)
        if let attributed = try? NSAttributedString(data: Data(html.utf8), options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) { view.textStorage?.setAttributedString(attributed) }
        else { view.string = b.name + "\n" + b.metrics.map { $0.0 + ": " + $0.1 }.joined(separator: "\n") }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo; info.isHorizontallyCentered = true; info.horizontalPagination = .fit
        NSPrintOperation(view: view, printInfo: info).run()
    }
    func readStorage() async {
        guard !storageBusy else { return }; storageBusy = true
        let text = await Task.detached(priority: .utility) {
            do { return String(decoding: try Command.run("system_profiler", ["SPNVMeDataType", "SPSerialATADataType"], timeout: 30), as: UTF8.self) }
            catch { return error.localizedDescription }
        }.value
        storageDetails = text.isEmpty ? "Система не предоставила сведения о накопителе." : text; storageBusy = false
    }
}

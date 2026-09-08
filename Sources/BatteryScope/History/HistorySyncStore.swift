import SwiftUI
import AppKit

extension Store {
    func setHistorySyncEnabled(_ enabled: Bool) {
        syncGeneration = UUID()
        syncWorker?.cancel()
        historySyncEnabled = enabled
        if !enabled { syncStatus = "Обмен выключен. Локальная история и файлы в общей папке сохранены."; return }
        if UserDefaults.standard.data(forKey: "historySyncFolderBookmark") == nil { setupICloud() }
        else { Task { await syncHistory() } }
    }
    func chooseHistorySyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = CloudFolder.drive
        panel.prompt = "Выбрать для истории"
        panel.message = "Выберите одну и ту же папку в iCloud Drive на всех Mac. В неё будут записаны история измерений, имена и идентификаторы устройств. Подробная диагностика останется на этом Mac."
        guard panel.runModal() == .OK, let folder = panel.url else {
            if UserDefaults.standard.data(forKey: "historySyncFolderBookmark") == nil { historySyncEnabled = false }
            return
        }
        useSyncFolder(folder)
    }
    func setupICloud() {
        do { useSyncFolder(try CloudFolder.prepare()) }
        catch {
            if UserDefaults.standard.data(forKey: "historySyncFolderBookmark") == nil { historySyncEnabled = false }
            self.error = error.localizedDescription
        }
    }
    func useSyncFolder(_ folder: URL) {
        do {
            let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            syncGeneration = UUID(); syncWorker?.cancel(); syncPeers = []
            UserDefaults.standard.set(bookmark, forKey: "historySyncFolderBookmark")
            syncFolderName = folder.path; historySyncEnabled = true
            Task { await syncHistory() }
        } catch { self.error = "Не удалось запомнить папку: \(error.localizedDescription)" }
    }
    func openSyncFolder() {
        guard let data = UserDefaults.standard.data(forKey: "historySyncFolderBookmark") else { return }
        do {
            var stale = false
            let folder = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.open(folder)
        } catch { self.error = error.localizedDescription }
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
            let folder: URL
            if syncFolderName == CloudFolder.drive.appendingPathComponent("BatteryScope", isDirectory: true).path {
                // The standard folder is resolved on this Mac, independently of stale bookmarks.
                folder = try CloudFolder.prepare()
            } else {
                var stale = false
                do {
                    folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                } catch { throw ReaderError.message("Не удалось восстановить доступ к папке. Нажмите «Настроить общую папку iCloud» или выберите папку заново.") }
                if stale { throw ReaderError.message("Доступ к папке изменился. Выберите её заново в настройках.") }
            }
            syncStatus = "Читаем и записываем файлы общей истории…"
            let snapshots = history, macID = LocalMacIdentity.id, macName = LocalMacIdentity.name
            let worker = Task.detached(priority: .utility) {
                try HistoryFolderSync.exchange(folder: folder, samples: snapshots, macID: macID, macName: macName)
            }
            syncWorker = worker
            let result = try await worker.value
            guard historySyncEnabled, generation == syncGeneration else { return }
            syncPeers = result.peers
            try database.merge(result.incoming)
            history = try database.load()
            for sample in history { lastSaved[sample.battery.id] = max(lastSaved[sample.battery.id] ?? .distantPast, sample.battery.date) }
            syncStatus = "\(Date().formatted()): в папке файлов \(result.filesSeen), добавлено файлов \(result.written), новых снимков получено \(result.incoming.count)."
            if result.cloudConfirmed {
                syncStatus += " Папка распознана как iCloud. Это не подтверждает получение другим Mac."
                if result.uploading > 0 { syncStatus += " Ожидают отправки в iCloud: \(result.uploading)." }
            } else {
                syncStatus += " iCloud для этой папки не подтверждён. Она может быть локальной. На обоих Mac выберите одну и ту же папку через раздел iCloud Drive в Finder."
            }
            if result.written == 0 && result.incoming.isEmpty { syncStatus += " Новых данных в выбранной папке нет." }
            if result.waiting > 0 { syncStatus += " Ожидают загрузки: \(result.waiting)." }
            if !result.issues.isEmpty { syncStatus += " Проблемы с файлами (\(result.issues.count)): " + result.issues.prefix(3).joined(separator: "; ") }
        } catch {
            guard historySyncEnabled, generation == syncGeneration else { return }
            syncStatus = "Обмен не завершён: \(error.localizedDescription). Повторим автоматически; локальная история сохранена."
        }
    }
}

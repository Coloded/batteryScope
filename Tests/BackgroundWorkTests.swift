import Foundation

@main struct BackgroundWorkTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(historyFolder: folder, observeSystemEvents: false)
        defer { store.stopBackgroundWork() }
        precondition(store.timer?.isValid == true && store.powerTimer?.isValid == true)
        let originalRead = store.lastMacRead, originalScan = store.lastPeripheralScan, originalSync = store.lastSyncAttempt
        store.setSleeping(true)
        precondition(store.timer == nil && store.powerTimer == nil && store.powerMonitor == nil)
        await store.scheduledRefresh()
        await store.refresh()
        await store.refreshMac()
        await store.syncHistory()
        precondition(store.devices.isEmpty && store.history.isEmpty)
        precondition(store.lastMacRead == originalRead && store.lastPeripheralScan == originalScan && store.lastSyncAttempt == originalSync)
        store.setSleeping(false)
        precondition(store.timer?.isValid == true && store.powerTimer?.isValid == true)
        precondition(store.devices.isEmpty && store.lastSyncAttempt == originalSync)
        precondition(store.timer!.fireDate > Date() && store.powerTimer!.fireDate > Date())
        var accessory = Battery(id: "bt:00:11:22:33:44:55", name: "Test earbuds", model: "Headphones", connection: "Bluetooth")
        accessory.details = ["device_batteryLevelCase": "12 %"]
        store.devices = [accessory]
        store.updateAccessoryTechnicalRecords()
        accessory.details = ["device_batteryLevelCase": "81 %", "device_batteryLevelLeft": "77 %"]
        store.devices = [accessory]
        store.updateAccessoryTechnicalRecords()
        precondition(store.technical[accessory.id]?.sections["Питание аксессуара"]?["device_batteryLevelCase"] == "81 %")
        let saved = try store.database!.loadTechnical(accessory.id)
        precondition(saved?.sections["Питание аксессуара"]?["device_batteryLevelCase"] == "81 %")
        accessory.available = false
        accessory.connection = "Не подключено"
        accessory.details = [:]
        store.devices = [accessory]
        store.updateAccessoryTechnicalRecords()
        precondition(store.technical[accessory.id]?.sections["Питание аксессуара"]?.isEmpty == true)
        precondition(store.technical[accessory.id]?.notes.contains(where: { $0.contains("кэш macOS") }) == true)
        print("PASS: accessory technical snapshot follows new macOS data; missing fields are not carried forward")
        print("PASS: sleep removes timers; all refresh paths blocked; wake schedules future intervals without catch-up")
    }
}

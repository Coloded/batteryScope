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
        print("PASS: sleep removes timers; all refresh paths blocked; wake schedules future intervals without catch-up")
    }
}

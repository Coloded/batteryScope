import SwiftUI
import Charts

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { _ = UpdateController.shared; _ = AppDiagnostics.shared }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct BatteryScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var menuInserted = true
    @StateObject private var store = Store()
    @StateObject private var updates = UpdateController.shared
    var body: some Scene {
        WindowGroup("BatteryScope", id: "main") { MainView().environmentObject(store).frame(minWidth: 980, minHeight: 700).task { await store.refresh() } }
        .commands { CommandGroup(after: .appInfo) { Button("Проверить обновления…") { updates.check() }.disabled(!updates.canCheck) } }
        MenuBarExtra(isInserted: $menuInserted) { MenuView().environmentObject(store) } label: { Label(store.menuTitle, systemImage: "battery.75percent") }
        .menuBarExtraStyle(.window)
    }
}

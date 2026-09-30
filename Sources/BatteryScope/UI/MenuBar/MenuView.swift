import SwiftUI

struct MenuView: View {
    @ObservedObject private var updates = UpdateController.shared
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BatteryScope").font(.headline)
            ForEach(store.devices) { b in VStack(alignment: .leading, spacing: 4) { HStack { Label { Text(b.name) } icon: { Image(nsImage: b.deviceIcon) }; Spacer(); Text(b.value(b.percent, suffix: "%")).bold() }; Text(b.state).font(.caption).foregroundStyle(.secondary) } }
            ForEach(store.devices.filter { $0.assessment != nil }) { device in
                if let warning = device.assessment { Label(device.name + ": " + warning.title, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
            }
            Divider()
            Button("Обновить") { Task { await store.refresh(forceSync: true) } }.disabled(store.busy)
            Button("Открыть BatteryScope") { NSApp.activate(ignoringOtherApps: true); if let window = NSApp.windows.first(where: { $0.title == "BatteryScope" }) { window.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") } }
            Button("Проверить обновления…") { updates.check() }.disabled(!updates.canCheck)
            Button("Завершить") { NSApp.terminate(nil) }
        }.padding(20).frame(width: 310)
    }
}

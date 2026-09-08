import SwiftUI

struct DeviceSelectorView: View {
    @EnvironmentObject var store: Store
    private func deviceMenuTitle(_ device: Battery) -> String {
        var parts = [device.name, device.connection]
        if device.isLive, device.percent != nil { parts.append(device.value(device.percent, suffix: "%")) }
        let prefix = store.selected == device.id ? "✓ " : ""
        return prefix + parts.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("УСТРОЙСТВО").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Menu {
                ForEach(store.knownDevices) { device in
                    Button { store.selected = device.id } label: {
                        Label {
                            Text(deviceMenuTitle(device))
                        } icon: { Image(nsImage: device.deviceIcon) }
                    }
                }
            } label: {
                Label { Text(store.current?.name ?? "Выберите устройство").lineLimit(1) }
                icon: { Image(nsImage: store.current?.deviceIcon ?? DeviceIconKind.generic.image) }
            }.menuStyle(.borderedButton).menuIndicator(.visible).controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(store.knownDevices.isEmpty)
                .accessibilityLabel("Выбрать устройство")
                .accessibilityValue(store.current?.name ?? "Устройства не найдены")
                .help(store.current?.name ?? "Выбрать устройство")
            if let device = store.current {
                HStack {
                    Text(device.connection).lineLimit(2)
                    Spacer(minLength: 4)
                    if device.isLive, device.percent != nil { Text(device.value(device.percent, suffix: "%")).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

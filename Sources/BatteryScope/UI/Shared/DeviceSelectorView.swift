import SwiftUI
import AppKit

struct DeviceSelectorView: View {
    @EnvironmentObject var store: Store
    private func deviceMenuTitle(_ device: Battery) -> String {
        var parts = [device.name]
        if historyLabel(device) == nil { parts.append(device.connection) }
        if device.isLive, device.percent != nil { parts.append(device.value(device.percent, suffix: "%")) }
        return parts.joined(separator: " · ")
    }
    private func historyLabel(_ device: Battery) -> DeviceHistoryLabel? {
        guard !store.devices.contains(where: { $0.id == device.id }),
              let sample = store.history.last(where: { $0.battery.id == device.id }) else { return nil }
        return DeviceHistoryLabel(sample: sample, localMacID: LocalMacIdentity.id)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("УСТРОЙСТВО").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ZStack {
                NativeDeviceMenu(items: store.knownDevices.map { device in
                    DeviceMenuItem(id: device.id, title: (device.assessment == nil ? "" : "⚠︎ ") + (historyLabel(device) == nil ? deviceMenuTitle(device) : device.name),
                                   deviceIcon: device.deviceIcon, trailingSymbol: historyLabel(device)?.symbol,
                                   help: historyLabel(device)?.help ?? device.connection)
                }, selection: $store.selected)
                HStack(spacing: 7) {
                    if let device = store.current {
                        Image(nsImage: device.deviceIcon).resizable().scaledToFit().frame(width: 20, height: 20)
                        Text(device.name).lineLimit(1).truncationMode(.tail)
                        if device.assessment != nil { Image(systemName: "exclamationmark.triangle") }
                        Spacer(minLength: 0)
                        if let history = historyLabel(device) { Image(systemName: history.symbol).font(.caption) }
                    } else { Text("Выбрать устройство"); Spacer() }
                    Image(systemName: "chevron.down").font(.caption)
                }.padding(.horizontal, 10).allowsHitTesting(false)
            }.frame(height: 34)
            .help(store.current.flatMap(historyLabel)?.help ?? store.current?.name ?? "Выбрать устройство")
            if let device = store.current {
                HStack {
                    if let history = historyLabel(device) {
                        Label(history.title, systemImage: history.symbol).help(history.help)
                    } else {
                        Text(device.connection).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if device.isLive, device.percent != nil { Text(device.value(device.percent, suffix: "%")).monospacedDigit() }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Presentation only: the persisted sample and its source are left unchanged.
private struct DeviceHistoryLabel {
    let title: String
    let symbol: String
    let help: String
    init(sample: Sample, localMacID: String) {
        let remote = sample.sourceMacID.map { $0 != localMacID } ?? false
        title = remote ? "Из iCloud" : "Сохранённые данные"
        symbol = remote ? "icloud.and.arrow.down" : "clock"
        let origin = remote ? "История получена с другого Mac" : "Снимок сохранён на этом Mac"
        help = origin + ". Последнее измерение: " + sample.battery.date.formatted()
    }
}

private struct DeviceMenuItem {
    let id: String
    let title: String
    let deviceIcon: NSImage
    let trailingSymbol: String?
    let help: String
}

/// Native attributed menu titles keep the history badge after the device name.
/// SwiftUI Menu can move a label image to the leading icon slot on macOS.
private struct NativeDeviceMenu: NSViewRepresentable {
    let items: [DeviceMenuItem]
    @Binding var selection: String
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.target = context.coordinator
        button.action = #selector(Coordinator.open(_:))
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.setAccessibilityLabel("Выбрать устройство")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.selection = $selection
        let menu = NSMenu()
        for item in items {
            let menuItem = NSMenuItem(title: item.title, action: #selector(Coordinator.select(_:)), keyEquivalent: "")
            menuItem.target = context.coordinator
            menuItem.representedObject = item.id
            menuItem.state = item.id == selection ? .on : .off
            menuItem.image = item.deviceIcon
            menuItem.toolTip = item.help
            if let symbol = item.trailingSymbol,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.help) {
                let title = NSMutableAttributedString(string: item.title + "  ", attributes: [.font: NSFont.menuFont(ofSize: 0)])
                let attachment = NSTextAttachment()
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
                title.append(NSAttributedString(attachment: attachment))
                menuItem.attributedTitle = title
            }
            menu.addItem(menuItem)
        }
        context.coordinator.menu = menu
        button.isEnabled = !items.isEmpty
        button.toolTip = items.first(where: { $0.id == selection })?.help
    }
    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        var menu = NSMenu()
        @objc func open(_ sender: NSButton) {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        }
        @objc func select(_ sender: NSMenuItem) {
            if let id = sender.representedObject as? String { selection.wrappedValue = id }
        }
    }
}

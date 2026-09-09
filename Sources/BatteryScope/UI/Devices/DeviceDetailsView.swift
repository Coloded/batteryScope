import SwiftUI
import Charts

struct DeviceDetailsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Поля, полученные от устройства. Их набор зависит от оборудования и версии ОС.").foregroundStyle(.secondary)
            if let b = store.current {
                ForEach(b.metrics.filter { $0.1 != "—" }, id: \.0) { key, value in HStack { Text(key); Spacer(); Text(value).monospacedDigit() }; Divider() }
                DisclosureGroup("Исходные диагностические поля") { ForEach(b.details.keys.sorted(), id: \.self) { key in HStack(alignment: .top) { TechnicalFieldRow(fieldKey: key, raw: b.details[key] ?? "") }.font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.vertical, 3) } }
                if b.id == "mac" {
                    Button(store.storageBusy ? "Читаем…" : "Прочитать данные накопителей") { Task { await store.readStorage() } }.disabled(store.storageBusy)
                    Text("Системные сведения о SSD. Счётчики прочитанных/записанных байтов доступны не на всех Mac.").font(.caption).foregroundStyle(.secondary)
                    Text(store.storageDetails).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }
}

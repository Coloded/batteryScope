import SwiftUI
import Charts

struct SpecificationsView: View {
    @EnvironmentObject var store: Store
    @State private var technicalSearch = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Поиск по-русски, по коду или значению", text: $technicalSearch).textFieldStyle(.roundedBorder)
                Button(store.technicalBusy.contains(store.selected) ? "Читаем…" : "Прочитать заново") { Task { await store.readTechnical(force: true) } }.disabled(store.technicalBusy.contains(store.selected) || store.current?.isLive != true)
                Button("Экспорт JSON") { store.exportTechnical() }.disabled(store.technical[store.selected] == nil)
            }
            if let record = store.technical[store.selected] {
                Text("Снимок характеристик: \(record.date.formatted()). Нажмите «Прочитать заново» для актуальных данных.").font(.caption).foregroundStyle(.secondary)
                Text("Русское название — сверху, исходный код — под ним. Наведите курсор на название, чтобы прочитать пояснение. Служебные коды без подтверждённой расшифровки не интерпретируются.").font(.caption).foregroundStyle(.secondary)
                ForEach(record.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(record.sections.keys.sorted(), id: \.self) { section in
                    let values = record.sections[section] ?? [:]
                    let keys = values.keys.sorted().filter { technicalSearch.isEmpty || section.localizedCaseInsensitiveContains(technicalSearch) || FieldLabels.matches(technicalSearch, key: $0, raw: values[$0] ?? "") }
                    if !keys.isEmpty {
                        GroupBox(section) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(keys, id: \.self) { key in
                                    TechnicalFieldRow(fieldKey: key, raw: values[key] ?? "").padding(.vertical, 8)
                                    Divider()
                                }
                            }.padding(10)
                        }
                    }
                }
            } else { ProgressView("Читаем технические характеристики…").frame(maxWidth: .infinity).padding(40) }
        }.task(id: store.selected) { await store.readTechnical() }
    }
}

import SwiftUI
import Charts

struct SpecificationsView: View {
    @EnvironmentObject var store: Store
    @State private var technicalSearch = ""
    @State private var showCodes = false
    @State private var collapsed: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Поиск по-русски, по коду или значению", text: $technicalSearch).textFieldStyle(.roundedBorder)
                Button(store.technicalBusy.contains(store.selected) ? "Читаем…" : "Прочитать заново") { Task { await store.readTechnical(force: true) } }.disabled(store.busy || store.technicalBusy.contains(store.selected) || store.current?.isLive != true)
                Button("Экспорт JSON") { store.exportTechnical() }.disabled(store.technical[store.selected] == nil)
            }
            if let record = store.technical[store.selected] {
                Text(store.selected.hasPrefix("bt:") ? "Данные macOS прочитаны: \(record.date.formatted()). Свежесть измерения заряда может отличаться." : "Снимок характеристик: \(record.date.formatted()).").font(.caption).foregroundStyle(.secondary)
                Toggle("Показывать технические коды", isOn: $showCodes).toggleStyle(.checkbox).font(.caption)
                HStack { Text("Параметр").frame(maxWidth: .infinity, alignment: .leading); Text("Значение").frame(maxWidth: .infinity, alignment: .leading) }.font(.headline).padding(12).background(.quaternary.opacity(0.5))
                ForEach(record.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(record.sections.keys.sorted(), id: \.self) { section in
                    let values = record.sections[section] ?? [:]
                    let keys = values.keys.sorted().filter { technicalSearch.isEmpty || section.localizedCaseInsensitiveContains(technicalSearch) || FieldLabels.matches(technicalSearch, key: $0, raw: values[$0] ?? "") }
                    if !keys.isEmpty {
                        DisclosureGroup(isExpanded: Binding(get: { !technicalSearch.isEmpty || !collapsed.contains(section) }, set: { expanded in if expanded { collapsed.remove(section) } else { collapsed.insert(section) } })) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(keys, id: \.self) { key in
                                    TechnicalFieldRow(fieldKey: key, raw: values[key] ?? "", showCodes: showCodes).padding(.vertical, 5)
                                    Divider()
                                }
                            }.padding(.leading, 12)
                        } label: { Text(section).font(.headline) }
                        .padding(.horizontal, 12)
                    }
                }
            } else { ProgressView("Читаем технические характеристики…").frame(maxWidth: .infinity).padding(40) }
        }.task(id: store.selected) { await store.readTechnical() }
        .task(id: store.current?.date) { if store.current?.isLive == false { await store.readTechnical() } }
    }
}

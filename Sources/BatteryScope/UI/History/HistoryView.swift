import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var selectedMetric = "Заряд"
    @State private var historyHours = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Снимки сохраняются раз в час, перед обменом iCloud при обновлении данных и вручную в обзоре.").foregroundStyle(.secondary)
            if store.samples.isEmpty { empty("История пока пуста", "Сохраните первый снимок в обзоре. Снимки сохраняются отдельно для каждого устройства.") }
            else {
                let choices = ObservationSeries.available(store.samples.map(\.battery))
                let chosen = choices.first(where: { $0.id == selectedMetric }) ?? choices.first
                if let chosen {
                    Picker("Показатель", selection: Binding(get: { chosen.id }, set: { selectedMetric = $0 })) {
                        ForEach(choices) { item in Text(item.id + ", " + item.unit).tag(item.id) }
                    }
                    Picker("Период", selection: $historyHours) {
                        Text("24 часа").tag(24)
                        Text("7 дней").tag(168)
                        Text("Все").tag(0)
                    }.pickerStyle(.segmented)
                    let end = store.samples.map(\.battery.date).max() ?? Date()
                    let visible = store.samples.sorted { $0.battery.date < $1.battery.date }.filter {
                        historyHours == 0 || $0.battery.date >= end.addingTimeInterval(-Double(historyHours) * 3600)
                    }
                    if visible.contains(where: { chosen.read($0.battery)?.isFinite == true }) {
                        MeasurementChart(samples: visible.map { .init(date: $0.battery.date, value: chosen.read($0.battery)) },
                                         title: chosen.id, unit: chosen.unit)
                    } else {
                        Text("За выбранный период нет измерений этого показателя.").foregroundStyle(.secondary)
                    }
                    HStack { Text("\(chosen.id) · \(chosen.values(visible.map(\.battery)).count) измерений").font(.headline); Spacer(); Button("Экспорт CSV") { store.exportCSV() } }
                    ForEach(visible.reversed().filter { chosen.read($0.battery) != nil }.prefix(100)) { sample in
                        HStack { Text(sample.battery.date.formatted()); Spacer(); Text(sample.battery.value(chosen.read(sample.battery), suffix: " " + chosen.unit, digits: 1)) }.font(.callout).padding(.vertical, 4)
                        Divider()
                    }
                } else { Text("Снимки есть, но числовые показатели в них отсутствуют.").foregroundStyle(.secondary) }

            }
            DisclosureGroup("Общая история всех устройств · \(store.history.count) снимков") {
                Button("Экспорт общей истории в CSV") { store.exportCSV(all: true) }
                ForEach(store.history.reversed().prefix(100)) { sample in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sample.battery.name)
                            if let source = sample.sourceMacName,
                               source.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(sample.battery.name.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame {
                                Text("Источник: " + source).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(sample.battery.date.formatted()).font(.caption)
                        if let item = ObservationSeries.available([sample.battery]).first {
                            Text(sample.battery.value(item.read(sample.battery), suffix: " " + item.unit))
                        }
                    }.padding(.vertical, 4)
                }
                Text("Показаны последние 100 снимков. Экспорт содержит всю историю.").font(.caption).foregroundStyle(.secondary)
            }
            let offline = Dictionary(grouping: store.history, by: { $0.battery.id }).values.compactMap { $0.last?.battery }.filter { b in !store.devices.contains { $0.id == b.id } }
            if !offline.isEmpty { Text("Отключённые устройства").font(.headline); ForEach(offline) { b in Button(b.name) { store.selected = b.id } } }
        }
    }
}

import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var showHealth = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Снимки сохраняются автоматически раз в час, пока приложение запущено, и вручную кнопкой в обзоре.").foregroundStyle(.secondary)
            if store.samples.isEmpty { empty("История пока пуста", "Подключите устройство с батареей. Снимки сохраняются отдельно для каждого устройства.") }
            else {
                Toggle("Показать состояние батареи вместо заряда", isOn: $showHealth)
                Chart(store.samples) { s in if let health = (showHealth ? s.battery.health : s.battery.percent) { LineMark(x: .value("Дата", s.battery.date), y: .value("Состояние, %", health)); PointMark(x: .value("Дата", s.battery.date), y: .value("Состояние, %", health)) } }.foregroundStyle(.mint).frame(height: 240)
                HStack { Text("\(showHealth ? "Состояние" : "Заряд") · \(store.samples.count) снимков").font(.headline); Spacer(); Button("Экспорт CSV") { store.exportCSV() } }
                ForEach(store.samples.reversed().prefix(100)) { s in HStack { Text(s.battery.date.formatted()); Spacer(); Text(s.battery.value((showHealth ? s.battery.health : s.battery.percent), suffix: "%", digits: 1)); Text(s.battery.value(s.battery.cycles, suffix: " циклов")).foregroundStyle(.secondary) }.font(.callout).padding(.vertical, 6); Divider() }
            }
            DisclosureGroup("Общая история всех устройств · \(store.history.count) снимков") {
                Button("Экспорт общей истории в CSV") { store.exportCSV(all: true) }
                ForEach(store.history.reversed().prefix(100)) { sample in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(sample.battery.name)
                            Text(sample.sourceMacName ?? "Этот Mac").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(sample.battery.date.formatted()).font(.caption)
                        Text(sample.battery.value(sample.battery.percent, suffix: "%"))
                    }.padding(.vertical, 4)
                }
                Text("Показаны последние 100 снимков. Экспорт содержит всю историю.").font(.caption).foregroundStyle(.secondary)
            }
            let offline = Dictionary(grouping: store.history, by: { $0.battery.id }).values.compactMap { $0.last?.battery }.filter { b in !store.devices.contains { $0.id == b.id } }
            if !offline.isEmpty { Text("Отключённые устройства").font(.headline); ForEach(offline) { b in Button(b.name) { store.selected = b.id } } }
        }
    }
}

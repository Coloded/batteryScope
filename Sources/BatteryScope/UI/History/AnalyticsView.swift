import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Статистика по сохранённым наблюдениям. Заводские данные за весь срок службы доступны только в подробностях, если устройство их сообщает.").foregroundStyle(.secondary)
            ForEach([("Температура, °C", store.samples.compactMap { $0.battery.temperature }), ("Напряжение, В", store.samples.compactMap { $0.battery.voltage }), ("Поток батареи, Вт", store.samples.compactMap { $0.battery.watts })], id: \.0) { title, values in
                GroupBox(title) { HStack { metric("Минимум", format(values.min()), ""); metric("Среднее", format(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)), ""); metric("Максимум", format(values.max()), "") } }
            }
            if let first = store.samples.first { Text("Наблюдаем с \(first.battery.date.formatted()). Это период наблюдений, а не время работы батареи.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func format(_ n: Double?) -> String { n.map { String(format: "%.2f", $0) } ?? "—" }
}

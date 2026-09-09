import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let batteries = store.samples.map(\.battery)
        let series = ObservationSeries.available(batteries)
        VStack(alignment: .leading, spacing: 12) {
            Text("Статистика сохранённых измерений этого устройства. Среднее рассчитано по снимкам, а не по времени работы.").font(.callout).foregroundStyle(.secondary)
            if series.isEmpty {
                empty("Пока нет измерений для анализа", "Сохраните снимок в обзоре или дождитесь автоматического сохранения. Данные отключённых аксессуаров могут быть недоступны.")
            } else {
                ForEach(series) { item in
                    let values = item.values(batteries)
                    GroupBox("\(item.id), \(item.unit) · \(values.count) измерений") {
                        HStack {
                            metric("Минимум", format(values.min()), "")
                            metric("Среднее", format(values.reduce(0, +) / Double(values.count)), "")
                            metric("Максимум", format(values.max()), "")
                        }
                    }
                }
                Text("Изменения во времени доступны в разделе «История».").font(.caption).foregroundStyle(.secondary)
            }
            if let first = batteries.map(\.date).min(), let last = batteries.map(\.date).max() {
                Text("Период: \(first.formatted()) — \(last.formatted()). Это период наблюдений, а не время автономной работы.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func format(_ n: Double?) -> String { n.map { String(format: "%.1f", $0) } ?? "—" }
}

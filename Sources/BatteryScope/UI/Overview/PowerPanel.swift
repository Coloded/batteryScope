import SwiftUI
import Charts

struct PowerPanel: View {
    @EnvironmentObject var store: Store
    let device: Battery
    @State private var series = "Вход от адаптера"
    @State private var historyHours = 24
    private var chartSamples: [LivePowerSample] {
        if device.id == "mac" && device.isLive { return store.livePower }
        let ordered = store.samples.sorted { $0.battery.date < $1.battery.date }
        let end = ordered.last?.battery.date ?? device.date
        return ordered.filter { historyHours == 0 || $0.battery.date >= end.addingTimeInterval(-Double(historyHours) * 3600) }.suffix(1000).map {
            LivePowerSample(date: $0.battery.date, battery: $0.battery.watts, input: $0.battery.power?.inputWatts, system: $0.battery.power?.systemWatts)
        }
    }
    private func value(_ sample: LivePowerSample) -> Double? {
        switch series {
        case "Поток батареи": return sample.battery
        case "Потребление системы": return sample.system
        default: return sample.input
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if device.id == "mac" || device.id.hasPrefix("mac:") {
                if !device.isDesktop {
                HStack {
                    if let thermal = device.summary?["Тепловое состояние"] { Label(thermal, systemImage: "thermometer.medium") }
                    Spacer()
                    if let mode = device.summary?["Энергосбережение"] { Text("Энергосбережение: " + mode) }
                }.font(.caption)
                }
                Picker("График мощности", selection: $series) {
                    Text("Мощность адаптера").tag("Вход от адаптера")
                    if !device.isDesktop { Text("Зарядка / разряд").tag("Поток батареи") }
                    Text("Потребление").tag("Потребление системы")
                }.pickerStyle(.segmented).labelsHidden()
                if !(device.id == "mac" && device.isLive) {
                    Picker("Период", selection: $historyHours) {
                        Text("24 часа").tag(24)
                        Text("7 дней").tag(168)
                        Text("Все").tag(0)
                    }.pickerStyle(.segmented)
                }
                if chartSamples.contains(where: { value($0) != nil }) {
                    PowerHistoryChart(samples: chartSamples, value: value, live: device.id == "mac" && device.isLive)
                } else { Text("Для выбранного показателя пока нет измерений.").font(.caption).foregroundStyle(.secondary) }
                Text(device.id == "mac" && device.isLive ? "Последние 30 минут текущего запуска" : "Сохранённые измерения до последнего снимка · до 1000 точек").font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { chooseSeries() }
        .onChange(of: device.id) { _ in chooseSeries() }
    }
    private func chooseSeries() {
        if device.power?.systemWatts != nil { series = "Потребление системы" }
        else if device.watts != nil && !device.isDesktop { series = "Поток батареи" }
        else { series = "Вход от адаптера" }
    }
}

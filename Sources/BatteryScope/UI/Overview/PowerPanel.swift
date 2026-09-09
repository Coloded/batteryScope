import SwiftUI
import Charts

struct PowerPanel: View {
    @EnvironmentObject var store: Store
    let device: Battery
    @State private var series = "Вход от адаптера"
    private var chartSamples: [LivePowerSample] {
        if device.id == "mac" && device.isLive { return store.livePower }
        return store.samples.sorted { $0.battery.date < $1.battery.date }.suffix(100).map {
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
        VStack(alignment: .leading, spacing: 8) {
            Text(device.isDesktop ? "История мощности" : "Питание и зарядка").font(.headline)
            if !device.isDesktop {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if device.power?.inputWatts != nil { metric("Вход от адаптера", device.value(device.power?.inputWatts, suffix: " Вт", digits: 1), "SystemPowerIn · питание всего Mac") }
                if device.power?.systemWatts != nil { metric("Потребление системы", device.value(device.power?.systemWatts, suffix: " Вт", digits: 1), "SystemLoad · телеметрия контроллера") }
                if device.watts != nil { metric("Поток батареи", device.value(device.watts, suffix: " Вт", digits: 1), "U × I · + в батарею, − из батареи по знаку датчика") }
                if device.power?.adapterRatingWatts != nil { metric("Мощность адаптера", device.value(device.power?.adapterRatingWatts, suffix: " Вт"), "Данные адаптера, не текущее потребление") }
            }
            }
            Text("Телеметрия Mac, без потерь блока питания.").font(.caption).foregroundStyle(.secondary)
            if device.id == "mac" || device.id.hasPrefix("mac:") {
                if !device.isDesktop {
                HStack {
                    if let thermal = device.summary?["Тепловое состояние"] { Label("Тепловое состояние: " + thermal, systemImage: "thermometer.medium") }
                    Spacer()
                    if let mode = device.summary?["Энергосбережение"] { Text("Энергосбережение: " + mode) }
                }.font(.caption)
                }
                Picker("График мощности", selection: $series) {
                    Text("Вход от адаптера").tag("Вход от адаптера")
                    if !device.isDesktop { Text("Поток батареи").tag("Поток батареи") }
                    Text("Потребление системы").tag("Потребление системы")
                }.pickerStyle(.segmented)
                if chartSamples.contains(where: { value($0) != nil }) {
                    Chart(chartSamples) { sample in
                        if let watts = value(sample) { PointMark(x: .value("Время", sample.date), y: .value("Вт", watts)) }
                    }.foregroundStyle(.mint).frame(height: 100)
                } else { Text("Для выбранного показателя пока нет измерений.").font(.caption).foregroundStyle(.secondary) }
                Text(device.id == "mac" && device.isLive ? "Последние 30 минут текущего запуска" : "Сохранённые измерения этого Mac · до 100 снимков").font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { if device.isDesktop { series = "Потребление системы" } }
        .onChange(of: device.isDesktop) { desktop in if desktop { series = "Потребление системы" } }
    }
}

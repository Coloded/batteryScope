import SwiftUI
import Charts

struct PowerPanel: View {
    @EnvironmentObject var store: Store
    let device: Battery
    @State private var series = "Вход от адаптера"
    private func value(_ sample: LivePowerSample) -> Double? {
        switch series {
        case "Поток батареи": return sample.battery
        case "Потребление системы": return sample.system
        default: return sample.input
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Питание и зарядка").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Вход от адаптера", device.value(device.power?.inputWatts, suffix: " Вт", digits: 1), "SystemPowerIn · питание всего Mac")
                metric("Потребление системы", device.value(device.power?.systemWatts, suffix: " Вт", digits: 1), "SystemLoad · телеметрия контроллера")
                metric("Поток батареи", device.value(device.watts, suffix: " Вт", digits: 1), "U × I · + в батарею, − из батареи по знаку датчика")
                metric("Мощность адаптера", device.value(device.power?.adapterRatingWatts, suffix: " Вт"), "Данные адаптера, не текущее потребление")
            }
            Text("Прочерк означает отсутствие измерения. Входная мощность не равна потреблению из розетки: потери адаптера здесь не измеряются. Служебная телеметрия доступна не на всех моделях macOS.").font(.caption).foregroundStyle(.secondary)
            if device.id == "mac" {
                HStack { Label(store.systemCondition, systemImage: "thermometer.medium"); Spacer(); Text(store.lowPowerMode ? "Энергосбережение включено" : "Обычный режим") }.font(.caption)
                Picker("График мощности", selection: $series) {
                    Text("Вход от адаптера").tag("Вход от адаптера")
                    Text("Поток батареи").tag("Поток батареи")
                    Text("Потребление системы").tag("Потребление системы")
                }.pickerStyle(.segmented)
                if store.livePower.contains(where: { value($0) != nil }) {
                    Chart(store.livePower) { sample in
                        if let watts = value(sample) { PointMark(x: .value("Время", sample.date), y: .value("Вт", watts)) }
                    }.foregroundStyle(.mint).frame(height: 160)
                } else { Text("Для выбранного показателя пока нет измерений.").font(.caption).foregroundStyle(.secondary) }
                Text("Последние 30 минут текущего запуска. В общей истории сохраняются отдельные снимки; график не подменяет отсутствующие значения другой метрикой.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

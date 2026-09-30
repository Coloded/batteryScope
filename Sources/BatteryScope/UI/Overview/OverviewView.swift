import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let b = store.current {
                if b.isDesktop {
                    DesktopOverview(device: b)
                } else {
                HStack(spacing: 14) {
                    if !b.isAccessory || b.percent != nil {
                    ZStack {
                        Circle().stroke(.mint.opacity(0.12), lineWidth: 7)
                        Circle().trim(from: 0, to: min(1, max(0, (b.percent ?? 0) / 100))).stroke(.mint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack { Text(b.value(b.percent, suffix: "%")).font(.system(size: 19, weight: .semibold, design: .rounded)); Text("заряд").font(.caption2).foregroundStyle(.secondary) }
                    }.frame(width: 52, height: 52)
                    } else { Image(nsImage: b.iconKind.image).resizable().scaledToFit().frame(width: 44, height: 44).foregroundStyle(.mint) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.isAccessory ? (b.isLive ? "Подключено" : "Не подключено") : b.snapshotPowerState).font(.headline)
                        Text("\(!b.isLive ? b.connection + " · " : "")\(b.id.hasPrefix("bt:") ? "Прочитано из macOS" : "Снимок") \(b.date.formatted())").font(.caption).foregroundStyle(.secondary)
                    }.help(b.note)
                    Spacer()
                }.padding(12).frame(maxWidth: .infinity).background(.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                }
                if let parts = b.components?.filter({ $0.key != "Аккумулятор" || b.percent == nil }), !parts.isEmpty {
                    Text(b.isLive ? "Компоненты" : "Последние известные показатели · время неизвестно").font(.headline)
                    HStack { ForEach(parts.keys.sorted(), id: \.self) { key in overviewMetric(key, b.value(parts[key], suffix: "%"), b.isLive ? "Последние данные macOS" : "Кэш macOS") } }
                }
                if b.isAccessory {
                    HStack(spacing: 8) {
                        ForEach(["LowBatteryNotificationPercentage", "CriticallyLowBatteryNotificationPercentage"], id: \.self) { key in
                            if let raw = b.details[key] {
                                overviewMetric(key == "LowBatteryNotificationPercentage" ? "Низкий заряд" : "Критический заряд", raw + "%", "Порог уведомления устройства")
                            }
                        }
                    }
                }
                if !b.isAccessory && !b.isDesktop {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    if b.health != nil { overviewMetric("Максимальная ёмкость", b.value(b.health, suffix: "%", digits: 1), b.healthSource) }
                    if b.cycles != nil { overviewMetric("Циклы", b.value(b.cycles), "Полные циклы заряда") }
                    if b.temperature != nil { overviewMetric("Температура", b.value(b.temperature, suffix: " °C", digits: 1), "Датчик аккумулятора") }
                    if b.full != nil { overviewMetric("Полная ёмкость", b.value(b.full, suffix: " мА·ч"), "Оценка контроллера при полном заряде") }
                    if b.remainingCapacity != nil { overviewMetric("Остаток заряда", b.value(b.remainingCapacity, suffix: " мА·ч"), "По данным контроллера") }
                    if b.design != nil { overviewMetric("Проектная ёмкость", b.value(b.design, suffix: " мА·ч"), "Номинал производителя") }
                    if b.id == "mac" || b.id.hasPrefix("mac:") {
                        if b.power?.systemWatts != nil || b.watts != nil { OverviewPowerMetric(device: b) }
                        if b.power?.inputWatts != nil || b.power?.adapterRatingWatts != nil { AdapterPowerMetric(device: b) }
                    }
                }
                }
                if b.id == "mac" || b.id.hasPrefix("mac:") { PowerPanel(device: b) }
            }
            ForEach(store.messages, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
        }
    }
}

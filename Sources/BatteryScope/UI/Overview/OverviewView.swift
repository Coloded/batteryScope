import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = store.current {
                if b.isDesktop {
                    DesktopOverview(device: b)
                } else {
                HStack(spacing: 28) {
                    if !b.isAccessory || b.percent != nil {
                    ZStack {
                        Circle().stroke(.mint.opacity(0.12), lineWidth: 14)
                        Circle().trim(from: 0, to: min(1, max(0, (b.percent ?? 0) / 100))).stroke(.mint, style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack { Text(b.value(b.percent, suffix: "%")).font(.system(size: 28, weight: .semibold, design: .rounded)); Text("заряд").foregroundStyle(.secondary) }
                    }.frame(width: 92, height: 92)
                    } else { Image(nsImage: b.iconKind.image).resizable().scaledToFit().frame(width: 72, height: 72).foregroundStyle(.mint).frame(width: 145) }
                    VStack(alignment: .leading, spacing: 12) { Text(b.isAccessory ? (b.isLive ? "Подключено" : "Не подключено") : b.snapshotPowerState).font(.title2.bold()); Text(!b.isLive && !b.isAccessory ? "Показатели на момент сохранения снимка" : (b.note.isEmpty ? "Текущие показания аккумулятора" : b.note)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Text("\(!b.isLive ? b.connection + " · " : "")\(b.id.hasPrefix("bt:") ? "Прочитано из macOS" : "Снимок") \(b.date.formatted())").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(16).frame(maxWidth: .infinity).background(.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                }
                if let parts = b.components?.filter({ $0.key != "Аккумулятор" || b.percent == nil }), !parts.isEmpty {
                    Text(b.isLive ? "Компоненты" : "Последние известные показатели · время неизвестно").font(.headline)
                    HStack { ForEach(parts.keys.sorted(), id: \.self) { key in metric(key, b.value(parts[key], suffix: "%"), b.isLive ? "Последние данные macOS" : "Кэш macOS") } }
                }
                if b.isAccessory {
                    HStack(spacing: 12) {
                        ForEach(["LowBatteryNotificationPercentage", "CriticallyLowBatteryNotificationPercentage"], id: \.self) { key in
                            if let raw = b.details[key] {
                                metric(key == "LowBatteryNotificationPercentage" ? "Низкий заряд" : "Критический заряд", raw + "%", "Порог уведомления устройства")
                            }
                        }
                    }
                }
                if !b.isAccessory && !b.isDesktop {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    if b.health != nil { metric("Состояние", b.value(b.health, suffix: "%", digits: 1), "Полная / проектная ёмкость") }
                    if b.cycles != nil { metric("Циклы", b.value(b.cycles), "Полные циклы заряда") }
                    if b.temperature != nil { metric("Температура", b.value(b.temperature, suffix: " °C", digits: 1), "Датчик аккумулятора") }
                    if b.full != nil { metric("Полная ёмкость", b.value(b.full, suffix: " мА·ч"), "Доступная сейчас") }
                    if b.design != nil { metric("Проектная ёмкость", b.value(b.design, suffix: " мА·ч"), "Номинал производителя") }
                    if b.watts != nil { metric("Поток батареи", b.value(b.watts, suffix: " Вт", digits: 1), "Напряжение × ток; знак датчика") }
                }
                }
                if !b.isDesktop, let summary = b.summary {
                    HStack {
                        ForEach(["Ядра CPU", "Ядра GPU"], id: \.self) { key in
                            if let value = summary[key] { Text("\(key): \(value)").font(.callout) }
                        }
                    }
                }
                if b.id == "mac" || b.id.hasPrefix("mac:") { PowerPanel(device: b) }
                HStack { Button("Сохранить снимок") { store.save(b) }.disabled(!b.isLive || (b.percent == nil && b.components?.isEmpty != false && b.id != "mac")); Button("HTML-отчёт") { store.exportReport() }; Button("Печать / PDF") { store.printReport() } }
            }
            ForEach(store.messages, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
        }
    }
}

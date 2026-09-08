import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let b = store.current {
                HStack(spacing: 28) {
                    ZStack {
                        Circle().stroke(.mint.opacity(0.12), lineWidth: 14)
                        Circle().trim(from: 0, to: min(1, max(0, (b.percent ?? 0) / 100))).stroke(.mint, style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
                        VStack { Text(b.value(b.percent, suffix: "%")).font(.system(size: 36, weight: .semibold, design: .rounded)); Text("заряд").foregroundStyle(.secondary) }
                    }.frame(width: 145, height: 145)
                    VStack(alignment: .leading, spacing: 12) { Text(b.state).font(.title2.bold()); Text(b.note.isEmpty ? "Текущие показания аккумулятора" : b.note).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true); Text("Обновлено \(b.date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(28).frame(maxWidth: .infinity).background(.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                if let parts = b.components, !parts.isEmpty {
                    Text(b.isLive ? "Компоненты" : "Последние известные показатели · время неизвестно").font(.headline)
                    HStack { ForEach(parts.keys.sorted(), id: \.self) { key in metric(key, b.value(parts[key], suffix: "%"), b.isLive ? "По данным macOS" : "Кэш macOS") } }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    metric("Состояние", b.value(b.health, suffix: "%", digits: 1), "Полная / проектная ёмкость")
                    metric("Циклы", b.value(b.cycles), "Полные циклы заряда")
                    metric("Температура", b.value(b.temperature, suffix: " °C", digits: 1), "Датчик аккумулятора")
                    metric("Полная ёмкость", b.value(b.full, suffix: " мА·ч"), "Доступная сейчас")
                    metric("Проектная ёмкость", b.value(b.design, suffix: " мА·ч"), "Номинал производителя")
                    metric("Поток батареи", b.value(b.watts, suffix: " Вт", digits: 1), "Напряжение × ток; знак датчика")
                }
                if b.id == "mac" || b.id.hasPrefix("mac:") { PowerPanel(device: b) }
                HStack { Button("Сохранить снимок") { store.save(b) }.disabled(!b.isLive || (b.percent == nil && b.components?.isEmpty != false)); Button("HTML-отчёт") { store.exportReport() }; Button("Печать / PDF") { store.printReport() } }
            }
            ForEach(store.messages, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
        }
    }
}

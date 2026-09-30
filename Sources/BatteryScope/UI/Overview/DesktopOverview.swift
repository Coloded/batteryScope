import SwiftUI

struct DesktopOverview: View {
    @EnvironmentObject var store: Store
    let device: Battery
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: "desktopcomputer").font(.system(size: 28)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Потребление системы").foregroundStyle(.secondary)
                    if let watts = device.power?.systemWatts {
                        Text(device.value(watts, suffix: " Вт", digits: 1)).font(.system(size: 23, weight: .semibold, design: .rounded))
                    } else { Text("Нет текущего измерения").font(.title2) }

                }
                Spacer()
            }
            Text("\(device.isLive ? "Обновлено" : "Сохранённые данные") \(device.date.formatted())").font(.caption).foregroundStyle(.secondary)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        if let summary = device.summary, !summary.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                ForEach(["Процессор", "Ядра CPU", "Память", "Графика", "Ядра GPU", "macOS", "Тепловое состояние"], id: \.self) { key in
                    if let value = summary[key] { overviewMetric(key, value, "") }
                }
            }
        }
    }
}

import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: Store
    private let pages = [("Обзор", "square.grid.2x2"), ("История", "chart.xyaxis.line"), ("Аналитика", "waveform.path.ecg"), ("Характеристики", "cpu"), ("Подробности", "list.bullet.rectangle"), ("Настройки", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                Label("BatteryScope", systemImage: "battery.100percent").font(.title2.bold()).foregroundStyle(.mint)
                DeviceSelectorView()
                VStack(spacing: 6) { ForEach(pages, id: \.0) { title, icon in
                    Button { store.page = title } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(store.page == title ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
                } }
                Spacer()
                Label("Данные хранятся на Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Text(store.lowPowerMode ? "Бережный режим опроса" : "Питание: события и опрос").font(.caption2).foregroundStyle(.tertiary)
            }.padding(22).frame(width: 245).background(.ultraThinMaterial)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) { Text(store.page).font(.system(size: 32, weight: .bold)); Text(store.current.map { "\($0.name) · \($0.model)" } ?? "Читаем устройства…").foregroundStyle(.secondary) }
                        Spacer()
                        Button { Task { await store.refresh() } } label: { Label(store.busy ? "Обновление…" : "Обновить", systemImage: "arrow.clockwise") }.disabled(store.busy)
                    }
                    if let error = store.error { HStack { Text(error).foregroundStyle(.red); Spacer(); Button("Закрыть") { store.error = nil } }.padding().background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)) }
                    switch store.page {
                    case "История": HistoryView()
                    case "Аналитика": AnalyticsView()
                    case "Подробности": DeviceDetailsView()
                    case "Характеристики": SpecificationsView()
                    case "Настройки": SettingsView()
                    default: OverviewView()
                    }
                }.padding(32)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(.mint)
    }
}

import SwiftUI
import Charts

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { _ = UpdateController.shared }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct BatteryScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var menuInserted = true
    @StateObject private var store = Store()
    @StateObject private var updates = UpdateController.shared
    var body: some Scene {
        WindowGroup("BatteryScope", id: "main") { MainView().environmentObject(store).frame(minWidth: 980, minHeight: 700).task { await store.refresh() } }
        .commands { CommandGroup(after: .appInfo) { Button("Проверить обновления…") { updates.check() }.disabled(!updates.canCheck) } }
        MenuBarExtra(isInserted: $menuInserted) { MenuView().environmentObject(store) } label: { Label(store.menuTitle, systemImage: "battery.75percent") }
        .menuBarExtraStyle(.window)
    }
}

struct MainView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var updates = UpdateController.shared
    @State private var technicalSearch = ""
    private let pages = [("Обзор", "square.grid.2x2"), ("История", "chart.xyaxis.line"), ("Аналитика", "waveform.path.ecg"), ("Характеристики", "cpu"), ("Подробности", "list.bullet.rectangle"), ("Настройки", "slider.horizontal.3")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                Label("BatteryScope", systemImage: "battery.100percent").font(.title2.bold()).foregroundStyle(.mint)
                ScrollView { VStack(alignment: .leading, spacing: 8) {
                    Text("УСТРОЙСТВА").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(store.devices) { b in
                        Button { store.selected = b.id } label: {
                            HStack { Image(systemName: b.symbol); VStack(alignment: .leading) { Text(b.name).lineLimit(1); Text(b.connection).font(.caption).foregroundStyle(.secondary) }; Spacer(); if b.percent != nil { Text(b.value(b.percent, suffix: "%")).font(.caption.monospacedDigit()) } }
                            .padding(10).background(store.selected == b.id ? Color.mint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
                }.frame(maxHeight: 330)
                VStack(spacing: 6) { ForEach(pages, id: \.0) { title, icon in
                    Button { store.page = title } label: { Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(store.page == title ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
                } }
                Spacer()
                Label("Данные хранятся на Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Text("Обновление каждую минуту").font(.caption2).foregroundStyle(.tertiary)
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
                    case "История": history
                    case "Аналитика": analytics
                    case "Подробности": details
                    case "Характеристики": specifications
                    case "Настройки": settings
                    default: overview
                    }
                }.padding(32)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.tint(.mint)
    }
    private var overview: some View {
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
                    metric("Мощность", b.value(b.watts, suffix: " Вт", digits: 1), "Знак тока задан устройством")
                }
                HStack { Button("Сохранить снимок") { store.save(b) }.disabled(!b.isLive || (b.percent == nil && b.components?.isEmpty != false)); Button("HTML-отчёт") { store.exportReport() }; Button("Печать / PDF") { store.printReport() } }
            }
            ForEach(store.messages, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange) }
        }
    }
    private func metric(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).foregroundStyle(.secondary); Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1); Text(hint).font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Снимки сохраняются автоматически раз в час, пока приложение запущено, и вручную кнопкой в обзоре.").foregroundStyle(.secondary)
            if store.samples.isEmpty { empty("История пока пуста", "Подключите устройство с батареей. Снимки сохраняются отдельно для каждого устройства.") }
            else {
                Chart(store.samples) { s in if let health = s.battery.health ?? s.battery.percent { LineMark(x: .value("Дата", s.battery.date), y: .value("Состояние, %", health)); PointMark(x: .value("Дата", s.battery.date), y: .value("Состояние, %", health)) } }.foregroundStyle(.mint).frame(height: 240)
                HStack { Text("Состояние / заряд · \(store.samples.count) снимков").font(.headline); Spacer(); Button("Экспорт CSV") { store.exportCSV() } }
                ForEach(store.samples.reversed().prefix(100)) { s in HStack { Text(s.battery.date.formatted()); Spacer(); Text(s.battery.value(s.battery.health ?? s.battery.percent, suffix: "%", digits: 1)); Text(s.battery.value(s.battery.cycles, suffix: " циклов")).foregroundStyle(.secondary) }.font(.callout).padding(.vertical, 6); Divider() }
            }
            let offline = Dictionary(grouping: store.history, by: { $0.battery.id }).values.compactMap { $0.last?.battery }.filter { b in !store.devices.contains { $0.id == b.id } }
            if !offline.isEmpty { Text("Отключённые устройства").font(.headline); ForEach(offline) { b in Button(b.name) { store.selected = b.id } } }
        }
    }
    private var analytics: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Статистика по сохранённым наблюдениям. Заводские данные за весь срок службы доступны только в подробностях, если устройство их сообщает.").foregroundStyle(.secondary)
            ForEach([("Температура, °C", store.samples.compactMap { $0.battery.temperature }), ("Напряжение, В", store.samples.compactMap { $0.battery.voltage }), ("Мощность, Вт", store.samples.compactMap { $0.battery.watts })], id: \.0) { title, values in
                GroupBox(title) { HStack { metric("Минимум", format(values.min()), ""); metric("Среднее", format(values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)), ""); metric("Максимум", format(values.max()), "") } }
            }
            if let first = store.samples.first { Text("Наблюдаем с \(first.battery.date.formatted()). Это период наблюдений, а не время работы батареи.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func format(_ n: Double?) -> String { n.map { String(format: "%.2f", $0) } ?? "—" }
    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Поля, полученные от устройства. Их набор зависит от оборудования и версии ОС.").foregroundStyle(.secondary)
            if let b = store.current {
                ForEach(b.metrics, id: \.0) { key, value in HStack { Text(key); Spacer(); Text(value).monospacedDigit() }; Divider() }
                DisclosureGroup("Исходные диагностические поля") { ForEach(b.details.keys.sorted(), id: \.self) { key in HStack(alignment: .top) { Text(key).frame(maxWidth: .infinity, alignment: .leading); Text(b.details[key] ?? "").frame(maxWidth: .infinity, alignment: .trailing) }.font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(.vertical, 3) } }
                if b.id == "mac" {
                    Button(store.storageBusy ? "Читаем…" : "Прочитать данные накопителей") { Task { await store.readStorage() } }.disabled(store.storageBusy)
                    Text("Системные сведения о SSD. Счётчики прочитанных/записанных байтов доступны не на всех Mac.").font(.caption).foregroundStyle(.secondary)
                    Text(store.storageDetails).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }
    private var specifications: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Поиск по характеристикам и значениям", text: $technicalSearch).textFieldStyle(.roundedBorder)
                Button(store.technicalBusy.contains(store.selected) ? "Читаем…" : "Прочитать заново") { Task { await store.readTechnical(force: true) } }.disabled(store.technicalBusy.contains(store.selected) || store.current?.isLive != true)
                Button("Экспорт JSON") { store.exportTechnical() }.disabled(store.technical[store.selected] == nil)
            }
            if let record = store.technical[store.selected] {
                Text("Снимок характеристик: \(record.date.formatted()). Нажмите «Прочитать заново» для актуальных данных.").font(.caption).foregroundStyle(.secondary)
                ForEach(record.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(record.sections.keys.sorted(), id: \.self) { section in
                    let values = record.sections[section] ?? [:]
                    let keys = values.keys.sorted().filter { technicalSearch.isEmpty || section.localizedCaseInsensitiveContains(technicalSearch) || $0.localizedCaseInsensitiveContains(technicalSearch) || (values[$0] ?? "").localizedCaseInsensitiveContains(technicalSearch) }
                    if !keys.isEmpty {
                        GroupBox(section) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(keys, id: \.self) { key in
                                    HStack(alignment: .top) {
                                        Text(key).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(values[key] ?? "").frame(maxWidth: .infinity, alignment: .trailing)
                                    }.font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(.vertical, 8)
                                    Divider()
                                }
                            }.padding(10)
                        }
                    }
                }
            } else { ProgressView("Читаем технические характеристики…").frame(maxWidth: .infinity).padding(40) }
        }.task(id: store.selected) { await store.readTechnical() }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupBox("Обновления · BatteryScope \(updates.version)") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Автоматически проверять обновления", isOn: $updates.automaticChecks)
                    Button("Проверить обновления…") { updates.check() }.disabled(!updates.canCheck)
                    Text("Sparkle проверяет обновления на GitHub. Установка — после вашего подтверждения. История SQLite сохраняется отдельно от приложения.").font(.caption).foregroundStyle(.secondary)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("Искать iPhone/iPad по Wi-Fi", isOn: store.$wifi)
            Toggle("Показывать Bluetooth-аксессуары Apple", isOn: store.$bluetooth)
            Text("iPhone, iPad и iPod touch: подключите по USB, разблокируйте и подтвердите доверие. Для Wi-Fi включите показ устройства по Wi-Fi в Finder. Изменения поиска применяются при обновлении.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Какие Apple-устройства поддерживаются") {
                Text("Mac: встроенная батарея. iPhone/iPad/iPod touch: USB и Wi-Fi, диагностика зависит от ОС. Magic Keyboard/Mouse/Trackpad: заряд. AirPods: доступные уровни наушников и футляра из macOS. Apple TV может определяться через доверенное сетевое соединение, но батареи у него нет. Apple Watch, Apple Pencil, AirTag, HomePod и удалённые Mac не предоставляют этому приложению универсальный доступ к батарее; их поддержка не заявляется.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Уведомлять о низком заряде", isOn: Binding(get: { store.alerts }, set: { store.enableAlerts($0) }))
            HStack { Text("Порог заряда"); Slider(value: store.$threshold, in: 5...50, step: 5); Text("\(Int(store.threshold))%").frame(width: 45) }
            HStack { Text("Оставшееся время Mac"); Slider(value: store.$timeThreshold, in: 5...60, step: 5); Text("\(Int(store.timeThreshold)) мин").frame(width: 60) }
            Divider()
            Text("Шаблон HTML-отчёта").font(.headline)
            Text("Подстановки: {{device}}, {{model}}, {{date}}, {{rows}}, {{note}}. Этот шаблон также используется при печати.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: store.$reportTemplate).font(.system(.caption, design: .monospaced)).frame(height: 230).border(.quaternary)
            Button("Восстановить шаблон") { store.reportTemplate = Export.template }
            Text("База SQLite: ~/Library/Application Support/BatteryScope/BatteryScope.sqlite\nНет облачной синхронизации или телеметрии. Для записи новых снимков приложение должно оставаться запущенным.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
    private func empty(_ title: String, _ subtitle: String) -> some View { VStack(spacing: 14) { Image(systemName: "chart.xyaxis.line").font(.system(size: 40)).foregroundStyle(.mint); Text(title).font(.title2); Text(subtitle).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(50) }
}

struct MenuView: View {
    @ObservedObject private var updates = UpdateController.shared
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BatteryScope").font(.headline)
            ForEach(store.devices) { b in VStack(alignment: .leading, spacing: 4) { HStack { Label(b.name, systemImage: b.symbol); Spacer(); Text(b.value(b.percent, suffix: "%")).bold() }; Text(b.state).font(.caption).foregroundStyle(.secondary) } }
            Divider()
            Button("Обновить") { Task { await store.refresh() } }.disabled(store.busy)
            Button("Открыть BatteryScope") { NSApp.activate(ignoringOtherApps: true); if let window = NSApp.windows.first(where: { $0.title == "BatteryScope" }) { window.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") } }
            Button("Проверить обновления…") { updates.check() }.disabled(!updates.canCheck)
            Button("Завершить") { NSApp.terminate(nil) }
        }.padding(20).frame(width: 310)
    }
}

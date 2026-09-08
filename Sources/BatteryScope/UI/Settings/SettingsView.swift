import SwiftUI
import Charts

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var login = LoginItemController.shared
    @ObservedObject private var diagnostics = AppDiagnostics.shared
    @ObservedObject private var updates = UpdateController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupBox("Обновления · BatteryScope \(updates.version)") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Автоматически проверять обновления", isOn: $updates.automaticChecks)
                    Button("Проверить обновления…") { updates.check() }.disabled(!updates.canCheck)
                    Text("Sparkle проверяет обновления на GitHub. Установка — после вашего подтверждения. История SQLite сохраняется отдельно от приложения.").font(.caption).foregroundStyle(.secondary)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Общая история · iCloud Drive") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Обмениваться историей с другими Mac", isOn: Binding(get: { store.historySyncEnabled }, set: { store.setHistorySyncEnabled($0) }))
                    Text("На обоих Mac выберите одну и ту же папку через раздел iCloud Drive в Finder. Одинаковое имя или путь «Документы» не гарантируют общую папку. История объединяется в локальной SQLite; сам файл базы не передаётся.").font(.caption).foregroundStyle(.secondary)
                    Button("Настроить общую папку iCloud") { store.setupICloud() }
                    Text("На обоих Mac нажмите эту кнопку: будет выбрана iCloud Drive → BatteryScope. На MacBook тоже нужна эта версия приложения.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Другая папка…") { store.chooseHistorySyncFolder() }
                        Button("Обменяться сейчас") { Task { await store.syncHistory() } }.disabled(!store.historySyncEnabled || store.syncBusy)
                        if store.syncBusy { ProgressView().controlSize(.small) }
                    }
                    Button("Открыть папку в Finder") { store.openSyncFolder() }
                    Text(store.syncFolderName).font(.caption).textSelection(.enabled)
                    Text(store.syncStatus).font(.caption).foregroundStyle(.secondary)
                    if store.syncPeers.isEmpty {
                        Text("Отметок обмена от других Mac пока нет. Проверьте одинаковый Apple Account и общую папку на втором Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(store.syncPeers) { peer in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(peer.name).font(.callout.weight(.medium))
                            Text("Последний обмен: " + peer.lastExchange.formatted()).font(.caption)
                            Text("Снимков с этого Mac получено: \(peer.receivedBySource[LocalMacIdentity.id] ?? 0)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Передаются имена, идентификаторы устройств и снимки батарей. Подробная техническая диагностика остаётся локально. Выключение обмена не удаляет ранее переданные файлы. Для надёжной загрузки выберите «Сохранять загруженным» для этой папки в Finder, если команда доступна.").font(.caption).foregroundStyle(.secondary)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Работа приложения") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Запускать BatteryScope при входе в macOS", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                    if !login.message.isEmpty { Text(login.message).font(.caption).foregroundStyle(.secondary) }
                    Toggle("Локальная диагностика BatteryScope (MetricKit)", isOn: Binding(get: { diagnostics.enabled }, set: { diagnostics.setEnabled($0) }))
                    Text("Системных отчётов получено: \(diagnostics.reportCount). Сохраняются только количество и дата, без содержимого отчётов и отправки на сервер. Доставка зависит от macOS; это не монитор всех процессов.").font(.caption).foregroundStyle(.secondary)
                    if let date = diagnostics.lastReport { Text("Последний отчёт: " + date.formatted()).font(.caption) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }.onAppear { login.refresh() }
            Toggle("Искать iPhone/iPad по Wi-Fi", isOn: $store.wifi)
            Toggle("Показывать Bluetooth-аксессуары Apple", isOn: $store.bluetooth)
            Text("iPhone, iPad и iPod touch: подключите по USB, разблокируйте и подтвердите доверие. Для Wi-Fi включите показ устройства по Wi-Fi в Finder. Изменения поиска применяются при обновлении.").font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Какие Apple-устройства поддерживаются") {
                Text("Mac: встроенная батарея. iPhone/iPad/iPod touch: USB и Wi-Fi, диагностика зависит от ОС. Magic Keyboard/Mouse/Trackpad: заряд. AirPods: доступные уровни наушников и футляра из macOS. Apple TV может определяться через доверенное сетевое соединение, но батареи у него нет. Apple Watch, Apple Pencil, AirTag, HomePod не предоставляют этому приложению универсальный доступ к батарее; их поддержка не заявляется. История других Mac доступна через общую папку, если BatteryScope работает на каждом из них.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Уведомлять о низком заряде", isOn: Binding(get: { store.alerts }, set: { store.enableAlerts($0) }))
            HStack { Text("Порог заряда"); Slider(value: $store.threshold, in: 5...50, step: 5); Text("\(Int(store.threshold))%").frame(width: 45) }
            HStack { Text("Оставшееся время Mac"); Slider(value: $store.timeThreshold, in: 5...60, step: 5); Text("\(Int(store.timeThreshold)) мин").frame(width: 60) }
            Divider()
            Text("Шаблон HTML-отчёта").font(.headline)
            Text("Подстановки: {{device}}, {{model}}, {{date}}, {{rows}}, {{note}}. Этот шаблон также используется при печати.").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $store.reportTemplate).font(.system(.caption, design: .monospaced)).frame(height: 230).border(.quaternary)
            Button("Восстановить шаблон") { store.reportTemplate = Export.template }
            Text("База SQLite: ~/Library/Application Support/BatteryScope/BatteryScope.sqlite\nОбмен историей через выбранную папку включается отдельно. Телеметрии нет. Для записи новых снимков приложение должно оставаться запущенным.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

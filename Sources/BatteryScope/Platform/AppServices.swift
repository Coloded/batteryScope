import AppKit
import Combine
import ServiceManagement
import MetricKit

@MainActor final class LoginItemController: ObservableObject {
    static let shared = LoginItemController()
    @Published private(set) var enabled = false
    @Published private(set) var message = ""
    init() { refresh() }
    func refresh() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        message = status == .requiresApproval ? "Разрешите запуск в Системных настройках → Основные → Объекты входа." : ""
    }
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch { refresh(); message = error.localizedDescription }
    }
}

/// Keep only counts of reports on this Mac. Raw diagnostic payloads are never exported or synced.
final class AppDiagnostics: NSObject, ObservableObject, MXMetricManagerSubscriber {
    static let shared = AppDiagnostics()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "localDiagnosticsEnabled")
    @Published private(set) var reportCount = UserDefaults.standard.integer(forKey: "localDiagnosticsReports")
    @Published private(set) var lastReport = UserDefaults.standard.object(forKey: "localDiagnosticsLastReport") as? Date
    override init() {
        super.init()
        if enabled { MXMetricManager.shared.add(self) }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "localDiagnosticsEnabled")
        if value { MXMetricManager.shared.add(self) } else { MXMetricManager.shared.remove(self) }
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) { record(payloads.count) }
    func didReceive(_ payloads: [MXMetricPayload]) { record(payloads.count) }
    private func record(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, count > 0 else { return }
            self.reportCount += count; self.lastReport = Date()
            UserDefaults.standard.set(self.reportCount, forKey: "localDiagnosticsReports")
            UserDefaults.standard.set(self.lastReport, forKey: "localDiagnosticsLastReport")
        }
    }
}

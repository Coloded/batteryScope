import Foundation
import UserNotifications

extension Store {
    func notifyBatteryWear() async {
        guard alerts, !sleeping else { return }
        for device in devices where device.isLive && Date().timeIntervalSince(device.date) < 300 {
            guard !sleeping, let warning = device.assessment else { continue }
            let key = "batteryWearNotified." + device.id
            guard UserDefaults.standard.integer(forKey: key) < warning.severity else { continue }
            let content = UNMutableNotificationContent()
            content.title = device.name + ": " + warning.title
            content.body = warning.reason
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
                UserDefaults.standard.set(warning.severity, forKey: key)
            } catch { self.error = error.localizedDescription }
        }
    }
}

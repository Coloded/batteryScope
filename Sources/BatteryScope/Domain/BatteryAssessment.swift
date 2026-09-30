import Foundation

struct BatteryAssessment {
    let severity: Int
    let title: String
    let reason: String
}

extension Battery {
    var assessment: BatteryAssessment? {
        guard !isDesktop, !isAccessory else { return nil }
        if batteryCondition == "Permanent Battery Failure" || batteryHealth == "Poor" {
            return BatteryAssessment(severity: 2, title: "Требуется обслуживание", reason: "macOS сообщает о неисправности аккумулятора. Обратитесь в сервис для диагностики.")
        }
        if batteryCondition == "Check Battery" {
            return BatteryAssessment(severity: 2, title: "Требуется обслуживание", reason: "macOS рекомендует проверить аккумулятор в сервисе.")
        }
        if batteryHealth == "Fair" {
            return BatteryAssessment(severity: 1, title: "Износ аккумулятора", reason: "macOS сообщает об ограниченной ёмкости аккумулятора.")
        }
        if let health, health.isFinite, health >= 0, health < 80 {
            return BatteryAssessment(severity: 1, title: "Снижена ёмкость аккумулятора", reason: validSystemMaximumCapacity != nil ? "Максимальная ёмкость по macOS составляет \(value(health, suffix: "%", digits: 1)) — ниже порога внимания 80%." : "Полная ёмкость составляет \(value(health, suffix: "%", digits: 1)) от проектной — ниже порога внимания 80%. Это оценка ёмкости, а не подтверждение неисправности.")
        }
        return nil
    }
}

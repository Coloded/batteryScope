import Foundation

struct Sample: Codable, Identifiable {
    var id = UUID()
    var battery: Battery
    var sourceMacID: String? = nil
    var sourceMacName: String? = nil
}

enum Export {
    static func csv(_ samples: [Sample]) -> String {
        func field(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        func n(_ v: Double?) -> String { v.map { String($0) } ?? "" }
        let header = "date,device,model,connection,charge_percent,health_percent,full_mAh,design_mAh,cycles,temperature_C,voltage_V,current_mA,components,device_id,source_mac_id,source_mac_name,battery_flow_W,input_W,system_W,adapter_rating_W,current_source\n"
        return header + samples.map { s in
            let b = s.battery
            let components = (b.components ?? [:]).keys.sorted().map { "\($0)=\(n(b.components?[$0]))" }.joined(separator: "; ")
            return [ISO8601DateFormatter().string(from: b.date), b.name, b.model, b.connection, n(b.percent), n(b.health), n(b.full), n(b.design), n(b.cycles), n(b.temperature), n(b.voltage), n(b.amperage), components, b.id, s.sourceMacID ?? "", s.sourceMacName ?? "", n(b.watts), n(b.power?.inputWatts), n(b.power?.systemWatts), n(b.power?.adapterRatingWatts), b.currentSource ?? ""].map(field).joined(separator: ",")
        }.joined(separator: "\n")
    }
    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    static let template = """
    <!doctype html><html lang="ru"><meta charset="utf-8"><title>BatteryScope — отчёт</title>
    <style>body{font:16px -apple-system,sans-serif;max-width:800px;margin:60px auto;color:#17362d}h1{font-size:36px}td{padding:10px;border-bottom:1px solid #ddd}table{width:100%;border-collapse:collapse}small{color:#63766f}</style>
    <h1>{{device}}</h1><p>{{model}} · {{date}}</p><table>{{rows}}</table><p>{{note}}</p><small>BatteryScope · локальный отчёт о состоянии аккумулятора</small></html>
    """
    static func report(_ b: Battery, template: String) -> String {
        let rows = b.metrics.map { "<tr><td>\(escape($0.0))</td><td>\(escape($0.1))</td></tr>" }.joined()
        let values = ["device": escape(b.name), "model": escape(b.model), "date": escape(b.date.formatted()), "rows": rows, "note": escape(b.note)]
        return values.reduce(template) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }
}

extension Battery {
    func value(_ n: Double?, suffix: String = "", digits: Int = 0) -> String { n.map { String(format: "%.*f", digits, $0) + suffix } ?? "—" }
    var state: String { if !isLive { return "Нет свежих данных" }; if components?.isEmpty == false && percent == nil { return "Подключено" }; if charging == true { return "Заряжается" }; if external == true { return "Питание подключено" }; if percent != nil { return "От аккумулятора" }; return "Нет данных батареи" }
    var metrics: [(String, String)] { [
        ("Заряд", value(percent, suffix: "%")), ("Состояние батареи", value(health, suffix: "%", digits: 1)),
        ("Полная ёмкость", value(full, suffix: " мА·ч")), ("Проектная ёмкость", value(design, suffix: " мА·ч")),
        ("Циклы", value(cycles)), ("Температура", value(temperature, suffix: " °C", digits: 1)),
        ("Напряжение", value(voltage, suffix: " В", digits: 2)), ("Ток", value(amperage, suffix: " мА")),
        ("Поток мощности батареи", value(watts, suffix: " Вт", digits: 1)), ("Вход от адаптера в Mac", value(power?.inputWatts, suffix: " Вт", digits: 1)), ("Потребление системы (телеметрия)", value(power?.systemWatts, suffix: " Вт", digits: 1)), ("Мощность адаптера по данным устройства", value(power?.adapterRatingWatts, suffix: " Вт")), ("Оставшееся время", value(minutes, suffix: " мин")), ("Питание", state)
    ] + (components ?? [:]).keys.sorted().map { ($0 + (isLive ? "" : " (кэш)"), value(components?[$0], suffix: "%")) } }
}

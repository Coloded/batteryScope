import Foundation

struct ObservationSeries: Identifiable {
    let id: String
    let unit: String
    let read: (Battery) -> Double?
    func values(_ batteries: [Battery]) -> [Double] { batteries.compactMap(read).filter(\.isFinite) }
    static func available(_ batteries: [Battery]) -> [ObservationSeries] {
        var all: [ObservationSeries] = [
            .init(id: "Заряд", unit: "%", read: { $0.percent }),
            .init(id: "Максимальная ёмкость · macOS", unit: "%", read: { $0.validSystemMaximumCapacity }),
            .init(id: "Максимальная ёмкость · оценка", unit: "%", read: { $0.validSystemMaximumCapacity == nil ? $0.health : nil }),
            .init(id: "Потребление системы", unit: "Вт", read: { $0.power?.systemWatts }),
            .init(id: "Входная мощность", unit: "Вт", read: { $0.power?.inputWatts }),
            .init(id: "Температура батареи", unit: "°C", read: { $0.temperature }),
            .init(id: "Напряжение", unit: "В", read: { $0.voltage }),
            .init(id: "Поток батареи", unit: "Вт", read: { $0.watts })
        ]
        let parts = Set(batteries.flatMap { Array(($0.components ?? [:]).keys) })
        for part in parts.sorted() { all.append(.init(id: part, unit: "%", read: { $0.components?[part] })) }
        return all.filter { !$0.values(batteries).isEmpty }
    }
}

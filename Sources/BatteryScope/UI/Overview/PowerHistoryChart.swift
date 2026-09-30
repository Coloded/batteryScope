import SwiftUI

struct PowerHistoryChart: View {
    let samples: [LivePowerSample]
    let value: (LivePowerSample) -> Double?
    let live: Bool
    var body: some View {
        MeasurementChart(samples: samples.map { .init(date: $0.date, value: value($0)) },
                         title: "Мощность", unit: "Вт", live: live, height: 115)
    }
}

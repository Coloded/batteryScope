import SwiftUI

func metric(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).foregroundStyle(.secondary); Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1); Text(hint).font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(10).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

func empty(_ title: String, _ subtitle: String) -> some View { VStack(spacing: 14) { Image(systemName: "chart.xyaxis.line").font(.system(size: 40)).foregroundStyle(.mint); Text(title).font(.title2); Text(subtitle).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(50) }

/// Dense overview cards keep explanations in tooltips; reports retain full labels.
func overviewMetric(_ title: String, _ value: String, _ hint: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 10)).help(hint.isEmpty ? title : hint)
}

/// One grid cell, with the same two-line height as the other overview metrics.
struct OverviewPowerMetric: View {
    let device: Battery
    var body: some View {
        HStack(spacing: 8) {
            if let watts = device.power?.systemWatts {
                reading("Потребление", watts: watts)
                    .help("Потребление Mac по телеметрии контроллера, без потерь блока питания")
            }
            if let watts = device.watts {
                reading(watts < 0 ? "Разряд" : "Зарядка", watts: abs(watts))
                    .help("Мощность батареи по телеметрии macOS; при отсутствии согласованного показания — напряжение × ток.")
            }
        }.padding(8).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
    private func reading(_ title: String, watts: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(device.value(watts, suffix: " Вт", digits: 1))
                .font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AdapterPowerMetric: View {
    let device: Battery
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Мощность адаптера сейчас").font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(device.value(device.power?.inputWatts, suffix: " Вт", digits: 1))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                if let rating = device.power?.adapterRatingWatts {
                    Text("Адаптер: " + device.value(rating, suffix: " Вт")).font(.caption2).foregroundStyle(.secondary)
                }
            }.lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .help("Сейчас — фактическая входная мощность в Mac. Адаптер — заявленная мощность блока питания. Потребление из розетки здесь не измеряется.")
    }
}

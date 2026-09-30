import SwiftUI
import Charts

/// Connect only contiguous observations; missing readings and long gaps split the curve.
struct PowerHistoryChart: View {
    let samples: [LivePowerSample]
    let value: (LivePowerSample) -> Double?
    let live: Bool
    @State private var hoverDate: Date?
    private struct Reading: Identifiable {
        let date: Date
        let watts: Double
        let segment: Int
        var id: Date { date }
    }
    private var readings: [Reading] {
        var result: [Reading] = []
        var segment = 0
        var previous: Date?
        for sample in samples.sorted(by: { $0.date < $1.date }) {
            guard let watts = value(sample), watts.isFinite else { segment += 1; previous = nil; continue }
            if let previous, sample.date.timeIntervalSince(previous) > (live ? 90 : 7200) { segment += 1 }
            if result.last?.date == sample.date { result.removeLast() }
            result.append(Reading(date: sample.date, watts: watts, segment: segment))
            previous = sample.date
        }
        return result
    }
    var body: some View {
        let points = readings
        let counts = Dictionary(grouping: points, by: \.segment).mapValues(\.count)
        let selected = hoverDate.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Мощность, Вт").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let reading = selected ?? points.last {
                    Text(reading.date.formatted(date: .abbreviated, time: .shortened) + " · " + String(format: "%.1f Вт", reading.watts))
                        .font(.caption).monospacedDigit()
                }
            }
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Время", point.date), yStart: .value("Ноль", 0), yEnd: .value("Мощность, Вт", point.watts), series: .value("Участок", point.segment))
                        .interpolationMethod(.monotone).foregroundStyle(LinearGradient(colors: [.mint.opacity(0.3), .mint.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Время", point.date), y: .value("Мощность, Вт", point.watts), series: .value("Участок", point.segment))
                        .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2)).foregroundStyle(.mint)
                    if counts[point.segment] == 1 {
                        PointMark(x: .value("Время", point.date), y: .value("Мощность, Вт", point.watts)).foregroundStyle(.mint)
                    }
                }
                if let selected {
                    RuleMark(x: .value("Время", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                    PointMark(x: .value("Время", selected.date), y: .value("Мощность, Вт", selected.watts)).foregroundStyle(.mint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { axis in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel { if let watts = axis.as(Double.self) { Text(watts.formatted(.number.precision(.fractionLength(0...1)))) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { axis in
                    AxisTick()
                    AxisValueLabel { if let date = axis.as(Date.self) {
                        VStack(spacing: 2) {
                            Text(date, format: .dateTime.hour().minute())
                            if let first = points.first, let last = points.last, !Calendar.current.isDate(first.date, inSameDayAs: last.date) {
                                Text(date, format: .dateTime.day().month())
                            }
                        }
                    } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let frame = geometry[proxy.plotAreaFrame]
                            hoverDate = frame.contains(location) ? proxy.value(atX: location.x - frame.minX, as: Date.self) : nil
                        case .ended: hoverDate = nil
                        }
                    }
                }
            }
            .frame(height: 115)
            Text("Время · наведите курсор для точного значения").font(.caption).foregroundStyle(.secondary)
        }.padding(8).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
}

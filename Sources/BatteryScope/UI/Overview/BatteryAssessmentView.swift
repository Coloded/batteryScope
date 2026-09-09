import SwiftUI

struct BatteryAssessmentView: View {
    let device: Battery
    var body: some View {
        if let assessment = device.assessment {
            VStack(alignment: .leading, spacing: 6) {
                Label(assessment.title, systemImage: "exclamationmark.triangle.fill").font(.headline)
                Text(assessment.reason).font(.callout)
                if !device.isLive { Text("По сохранённому снимку от \(device.date.formatted())").font(.caption) }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(assessment.severity == 2 ? Color.red : Color.orange)
                .background((assessment.severity == 2 ? Color.red : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        } else if !device.isDesktop && device.health == nil && device.batteryHealth == nil {
            Text("Данные об износе аккумулятора недоступны").font(.caption).foregroundStyle(.secondary)
        }
    }
}

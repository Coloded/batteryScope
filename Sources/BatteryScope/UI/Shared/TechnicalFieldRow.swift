import SwiftUI

struct TechnicalFieldRow: View {
    let fieldKey: String
    let raw: String
    var showCodes = false
    var body: some View {
        let info = FieldLabels.label(fieldKey)
        let formatted = FieldLabels.value(raw, for: fieldKey)
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.known ? info.title : fieldKey).font(.callout)
                if showCodes && info.known && info.title != fieldKey { Text(fieldKey).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).help(info.explanation + "\n" + fieldKey)
            Text(formatted).font(.callout).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).help("Исходное значение: " + raw)
        }.textSelection(.enabled)
    }
}

import SwiftUI

struct TechnicalFieldRow: View {
    let fieldKey: String
    let raw: String
    var body: some View {
        let info = FieldLabels.label(fieldKey)
        let formatted = FieldLabels.value(raw, for: fieldKey)
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title).font(.callout).foregroundStyle(.primary)
                Text(fieldKey).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                if !info.known { Text("Служебное поле · расшифровка не подтверждена").font(.caption2).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).help(info.explanation)
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatted).font(.callout).monospacedDigit()
                if formatted != raw { Text("Исходное: " + raw).font(.caption2).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.textSelection(.enabled)
    }
}

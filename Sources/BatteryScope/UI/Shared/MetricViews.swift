import SwiftUI

func metric(_ title: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).foregroundStyle(.secondary); Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).minimumScaleFactor(0.7).lineLimit(1); Text(hint).font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14))
    }

func empty(_ title: String, _ subtitle: String) -> some View { VStack(spacing: 14) { Image(systemName: "chart.xyaxis.line").font(.system(size: 40)).foregroundStyle(.mint); Text(title).font(.title2); Text(subtitle).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(50) }

import AppKit
import SwiftUI

/// Drawn locally, so every device has an icon even on macOS without newer SF Symbols.
enum DeviceIconKind: CaseIterable {
    case desktop, laptop, phone, tablet, keyboard, trackpad, mouse, earbuds, headphones, watch, tv, speaker, musicPlayer, generic

    var image: NSImage { Self.images[self]! }
    private static let images: [DeviceIconKind: NSImage] = Dictionary(uniqueKeysWithValues: allCases.map { kind in
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            NSColor.labelColor.setStroke()
            func stroke(_ path: NSBezierPath) {
                path.lineWidth = 1.5; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
            }
            func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat = 2) {
                stroke(NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius))
            }
            func line(_ points: [(CGFloat, CGFloat)]) {
                let path = NSBezierPath()
                for (index, p) in points.enumerated() {
                    if index == 0 { path.move(to: NSPoint(x: p.0, y: p.1)) }
                    else { path.line(to: NSPoint(x: p.0, y: p.1)) }
                }
                stroke(path)
            }
            func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                stroke(NSBezierPath(ovalIn: NSRect(x: x, y: y, width: w, height: h)))
            }
            switch kind {
            case .desktop:
                box(2, 3, 20, 14); line([(2, 14), (22, 14)]); line([(12, 17), (12, 21)]); line([(8, 21), (16, 21)])
            case .laptop:
                box(4, 3, 16, 13); line([(4, 16), (1, 20), (23, 20), (20, 16)]); line([(10, 18), (14, 18)])
            case .phone:
                box(6, 2, 12, 20, 3); line([(10, 5), (14, 5)]); line([(10, 19), (14, 19)])
            case .tablet:
                box(3, 2, 18, 20, 2.5); line([(10, 19), (14, 19)])
            case .keyboard:
                box(1.5, 5, 21, 14)
                for row in 0..<2 { for column in 0..<6 { line([(4 + CGFloat(column)*3.2, 9 + CGFloat(row)*3), (4.8 + CGFloat(column)*3.2, 9 + CGFloat(row)*3)]) } }
                line([(7, 15.5), (17, 15.5)])
            case .trackpad:
                box(2, 4, 20, 16, 3); line([(3, 17), (21, 17)])
            case .mouse:
                box(6, 2, 12, 20, 6); line([(12, 3), (12, 10)]); line([(7, 10), (17, 10)])
            case .earbuds:
                oval(3, 3, 7, 7); oval(14, 3, 7, 7)
                box(7, 8, 3, 13, 1.5); box(14, 8, 3, 13, 1.5)
            case .headphones:
                let arc = NSBezierPath(); arc.move(to: NSPoint(x: 4, y: 14)); arc.curve(to: NSPoint(x: 20, y: 14), controlPoint1: NSPoint(x: 2, y: -1), controlPoint2: NSPoint(x: 22, y: -1)); stroke(arc)
                box(2, 12, 5, 9); box(17, 12, 5, 9)
            case .watch:
                box(6, 6, 12, 12, 3); line([(9, 6), (9, 2), (15, 2), (15, 6)]); line([(9, 18), (9, 22), (15, 22), (15, 18)]); line([(12, 9), (12, 12), (14, 13)])
            case .tv:
                box(2, 4, 20, 14); line([(7, 18), (5, 21)]); line([(17, 18), (19, 21)]); line([(10, 8), (15, 11), (10, 14), (10, 8)])
            case .speaker:
                box(6, 2, 12, 20, 5); oval(9, 5, 6, 3); line([(9, 17), (15, 17)])
            case .musicPlayer:
                box(6, 2, 12, 20); box(8, 4, 8, 7, 1); oval(9, 14, 6, 6)
            case .generic:
                box(5, 4, 14, 16, 3); line([(9, 9), (15, 9)]); line([(9, 13), (15, 13)])
            }
            return true
        }
        image.isTemplate = true
        return (kind, image)
    })
}

extension Battery {
    var iconKind: DeviceIconKind {
        let text = (model + " " + name).lowercased()
        if text.contains("macbook") || ((id == "mac" || id.hasPrefix("mac:")) && (design != nil || full != nil || percent != nil)) { return .laptop }
        if id == "mac" || id.hasPrefix("mac:") || text.contains("imac") || text.contains("mac mini") || text.contains("mac studio") || text.contains("mac pro") { return .desktop }
        if text.contains("ipad") { return .tablet }
        if text.contains("iphone") { return .phone }
        if text.contains("ipod") { return .musicPlayer }
        if text.contains("trackpad") { return .trackpad }
        if text.contains("keyboard") { return .keyboard }
        if text.contains("mouse") { return .mouse }
        if text.contains("airpods max") { return .headphones }
        if text.contains("airpods") { return .earbuds }
        if text.contains("headphone") { return .headphones }
        if text.contains("watch") { return .watch }
        if text.contains("homepod") || text.contains("speaker") { return .speaker }
        if text.contains("tv") { return .tv }
        return .generic
    }
    var deviceIcon: NSImage { iconKind.image }
}

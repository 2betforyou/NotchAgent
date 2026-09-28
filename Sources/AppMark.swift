import AppKit
import SwiftUI

/// NotchAgent's own mark, matching the app icon (squircle, notch, `>_`). Used where the app
/// itself is meant; "Terminal" sessions keep the generic terminal symbol.
struct AppMark: View {
    var size: CGFloat = 18
    /// Drawn in code (same geometry as Scripts/MakeIcon.swift) so it never shows a cached icon.
    var body: some View {
        let s = size / 1024
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 206 * s, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
                .overlay { RoundedRectangle(cornerRadius: 206 * s, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: max(0.5, 3 * s)) }
            UnevenRoundedRectangle(bottomLeadingRadius: 58 * s, bottomTrailingRadius: 58 * s)
                .fill(.black).frame(width: 360 * s, height: 130 * s)
            PromptGlyph()
                .stroke(Color(red: 0.66, green: 0.96, blue: 0.75), style: StrokeStyle(lineWidth: 64 * s, lineCap: .round, lineJoin: .round))
                .frame(width: 520 * s, height: 300 * s)
                .offset(x: 30 * s, y: 330 * s)
        }
        .frame(width: 900 * s, height: 900 * s)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// `>_` on its own, for the empty closed notch where a dark icon would disappear on black.
struct PromptGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.18))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.82))
        p.move(to: CGPoint(x: rect.minX + w * 0.55, y: rect.minY + h * 0.84))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.95, y: rect.minY + h * 0.84))
        return p
    }
}

enum MenuBarIcon {
    /// Monochrome template of the app icon for the menu bar: outline, notch, `>_`.
    /// macOS tints template images for light and dark menu bars.
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 15), xRadius: 4, yRadius: 4)
            body.lineWidth = 1.5
            body.stroke()
            NSBezierPath(roundedRect: NSRect(x: 6, y: 12.5, width: 6, height: 4.5), xRadius: 1.2, yRadius: 1.2).fill()
            let prompt = NSBezierPath()
            prompt.lineWidth = 1.6; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round
            prompt.move(to: NSPoint(x: 5, y: 10)); prompt.line(to: NSPoint(x: 7.8, y: 7.5)); prompt.line(to: NSPoint(x: 5, y: 5))
            prompt.move(to: NSPoint(x: 9.5, y: 4.8)); prompt.line(to: NSPoint(x: 13, y: 4.8))
            prompt.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "NotchAgent"
        return image
    }
}

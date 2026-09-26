import AppKit
import SwiftTerm
import SwiftUI

/// The app's highlight color (buttons, status dots, caret). Mint is the original look.
enum Accent: String, CaseIterable, Identifiable {
    case mint, sky, lavender, peach, lemon, silver
    var id: String { rawValue }
    /// Read on every render through `Palette.mint`; set by `AppModel.accent`.
    nonisolated(unsafe) static var current: Accent = .mint
    var name: String {
        switch self {
        case .mint: L("민트", "Mint")
        case .sky: L("스카이", "Sky")
        case .lavender: L("라벤더", "Lavender")
        case .peach: L("피치", "Peach")
        case .lemon: L("레몬", "Lemon")
        case .silver: L("실버", "Silver")
        }
    }
    var rgb: (Double, Double, Double) {
        switch self {
        case .mint: (0.66, 0.96, 0.75)
        case .sky: (0.56, 0.82, 1.0)
        case .lavender: (0.77, 0.70, 1.0)
        case .peach: (1.0, 0.74, 0.62)
        case .lemon: (0.96, 0.90, 0.52)
        case .silver: (0.86, 0.88, 0.91)
        }
    }
    var color: SwiftUI.Color { SwiftUI.Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
    var nsColor: NSColor { NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
}

/// Terminal color schemes: background, text and the 16 ANSI colors programs use.
enum TerminalTheme: String, CaseIterable, Identifiable {
    case standard, deepBlue, warmInk
    var id: String { rawValue }
    var name: String {
        switch self {
        case .standard: L("기본", "Default")
        case .deepBlue: L("딥 블루", "Deep Blue")
        case .warmInk: L("따뜻한 먹색", "Warm Ink")
        }
    }
    var background: UInt32 { [0x090A0B, 0x0B1020, 0x14110E][index] }
    var foreground: UInt32 { [0xE0E8E3, 0xD6E2FF, 0xEDE3D4][index] }
    /// black, red, green, yellow, blue, magenta, cyan, white, then the bright variants.
    var ansi: [UInt32] {
        switch self {
        case .standard: [0x1B1D1F, 0xFF6B6B, 0x8EE6A8, 0xF5D76E, 0x6CB6FF, 0xC8A2FF, 0x6EE7E0, 0xD5DAD6,
                         0x4A4F54, 0xFF8E8E, 0xB6F5C8, 0xFFE699, 0x93CBFF, 0xDCC2FF, 0x9AF0EB, 0xFFFFFF]
        case .deepBlue: [0x1A2238, 0xFF7A90, 0x7EE0B5, 0xF2D675, 0x7AA7FF, 0xB69CFF, 0x6FD6F2, 0xC9D4EE,
                         0x3A4566, 0xFF9CAD, 0xA4EDCC, 0xF7E39E, 0xA3C2FF, 0xCDB9FF, 0x9AE3F7, 0xF4F7FF]
        case .warmInk: [0x26211B, 0xE8826E, 0xB5CC7A, 0xE6C170, 0x86A7C9, 0xC49AB8, 0x86C1B0, 0xD9CDBB,
                        0x4D443A, 0xF0A493, 0xCBDD9C, 0xF0D496, 0xA7C0DB, 0xD6B5CC, 0xA6D4C6, 0xFFF7EA]
        }
    }
    private var index: Int { Self.allCases.firstIndex(of: self)! }
    var backgroundColor: SwiftUI.Color { SwiftUI.Color(nsColor: Self.ns(background)) }
    static func ns(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    static func term(_ hex: UInt32) -> SwiftTerm.Color {
        func c(_ shift: UInt32) -> UInt16 { UInt16((hex >> shift) & 0xFF) * 257 }
        return SwiftTerm.Color(red: c(16), green: c(8), blue: c(0))
    }
}

/// Monospaced fonts offered in Settings: the system font plus common coding fonts if installed.
enum TerminalFont {
    static let system = "system"
    private static let candidates = ["Menlo", "Monaco", "D2Coding", "JetBrains Mono", "Fira Code", "Source Code Pro",
                                     "Hack", "Cascadia Code", "IBM Plex Mono", "Roboto Mono", "Sarasa Mono K"]
    static var available: [(id: String, name: String)] {
        [(system, "SF Mono")] + candidates.filter { NSFontManager.shared.availableMembers(ofFontFamily: $0) != nil }.map { ($0, $0) }
    }
    static func font(_ id: String, size: CGFloat) -> NSFont {
        if id != system, let font = NSFontManager.shared.font(withFamily: id, traits: [], weight: 5, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// Everything that decides how a terminal looks; compared to skip redundant updates.
struct TerminalAppearance: Equatable {
    var theme: TerminalTheme
    var font: String
    var size: Double
    var accent: Accent
}

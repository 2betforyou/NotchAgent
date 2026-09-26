import AppKit
import XCTest
@testable import NotchAgent

@MainActor
final class AppearanceTests: XCTestCase {
    func testThemeFontAndCaretReachTheTerminal() {
        let s = TerminalSession(kind: .shell, directory: FileManager.default.temporaryDirectory, executable: "/bin/zsh", fontSize: 13)
        s.apply(TerminalAppearance(theme: .deepBlue, font: "Menlo", size: 15, accent: .lavender))
        XCTAssertEqual(s.terminal.nativeBackgroundColor.usingColorSpace(.sRGB)?.blueComponent ?? 0, CGFloat(0x20) / 255, accuracy: 0.01)
        XCTAssertEqual(s.terminal.font.familyName, "Menlo")
        XCTAssertEqual(s.terminal.font.pointSize, 15)
        XCTAssertEqual(s.terminal.caretColor, Accent.lavender.nsColor)
        // An ANSI red written by a program now uses the theme's red.
        s.terminal.feed(text: "\u{1b}[31mR")
        XCTAssertEqual(s.terminal.getTerminal().getCharData(col: 0, row: 0)?.attribute.fg, .ansi256(code: 1))
    }
    func testMissingFontFallsBackToSystemMonospaced() {
        let font = TerminalFont.font("Definitely Not A Font", size: 13)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(TerminalFont.available.first?.id, TerminalFont.system)
    }
    func testEveryThemeHasSixteenColors() {
        for theme in TerminalTheme.allCases { XCTAssertEqual(theme.ansi.count, 16, theme.name) }
    }
    func testAccentIsRememberedAndDrivesPalette() {
        let d = UserDefaults.standard
        let saved = d.object(forKey: "accent")
        defer { d.set(saved, forKey: "accent"); Accent.current = AppModel().accent }
        let model = AppModel()
        model.accent = .sky
        XCTAssertEqual(Accent.current, .sky)
        XCTAssertEqual(AppModel().accent, .sky)
    }
}

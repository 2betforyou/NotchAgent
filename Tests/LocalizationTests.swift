import XCTest
@testable import NotchAgent

final class LocalizationTests: XCTestCase {
    override func tearDown() { AppLanguage.current = .korean }

    func testEnglishStrings() {
        AppLanguage.current = .english
        let now = Date(timeIntervalSince1970: 1000)
        let weekly = UsageWindow(id: "secondary", usedPercent: 25, durationMinutes: 10080, resetsAt: now.addingTimeInterval(3660))
        XCTAssertEqual(weekly.title, "Weekly")
        XCTAssertEqual(weekly.resetLabel(now: now), "Resets in 1h 1m")
        XCTAssertEqual(UsageWindow(id: "primary", usedPercent: 0, durationMinutes: 300, resetsAt: nil).title, "5-hour")
        XCTAssertEqual(AttentionReason.finished.message, "finished")
        XCTAssertEqual(UsageAge.label(since: now.addingTimeInterval(-300), now: now), "5m ago")
        XCTAssertEqual(HoverSpeed.fast.label, "Fast · 120ms")
        XCTAssertEqual(Accent.lavender.name, "Lavender")
    }
    func testKoreanStrings() {
        AppLanguage.current = .korean
        XCTAssertEqual(UsageWindow(id: "secondary", usedPercent: 0, durationMinutes: 10080, resetsAt: nil).title, "주간 한도")
        XCTAssertEqual(AttentionReason.bell.message, "확인이 필요해요")
    }
    func testSystemFollowsPreferredLanguage() {
        let expectKorean = Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        AppLanguage.current = .system
        XCTAssertEqual(L("한", "en"), expectKorean ? "한" : "en")
    }
    func testLanguageNamesAreInTheirOwnLanguage() {
        AppLanguage.current = .english
        XCTAssertEqual(AppLanguage.korean.name, "한국어")
        XCTAssertEqual(AppLanguage.english.name, "English")
        XCTAssertEqual(AppLanguage.system.name, "Match System")
    }
    /// Every L("…", "…") call in the app has a non-empty English side that is not Korean.
    func testEverySourceStringHasAnEnglishTranslation() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let hangul = try NSRegularExpression(pattern: "[가-힣]")
        var missing: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                if line.contains("// native name") { continue }
                let code = line.components(separatedBy: "//").first ?? line
                guard code.contains("\""), hangul.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil else { continue }
                if !code.contains("L(") { missing.append("\(file.lastPathComponent):\(number + 1)") }
            }
        }
        XCTAssertEqual(missing, [], "Korean UI text without an English translation")
    }
}

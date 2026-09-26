import XCTest
@testable import NotchAgent

final class ClaudeUsageTests: XCTestCase {
    private var directory: URL!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentClaude-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var sample: [String: Any] {
        ["five_hour": ["used_percentage": 23.5, "resets_at": 1_800_003_600],
         "seven_day": ["used_percentage": 41, "resets_at": 1_800_300_000]]
    }

    func testParsesDocumentedStatusLineFields() throws {
        let s = try XCTUnwrap(ClaudeUsage.parse(limits: sample, fetchedAt: now, now: now))
        XCTAssertEqual(s.windows.map(\.title), ["5시간 한도", "주간 한도"])
        XCTAssertEqual(s.windows.map(\.remaining), [76.5, 59])
        XCTAssertEqual(s.windows[0].resetLabel(now: now), "1시간 0분 후 초기화")
    }
    func testExpiredWindowIsHiddenNotShownAsCurrent() throws {
        let s = try XCTUnwrap(ClaudeUsage.parse(limits: sample, fetchedAt: now, now: now.addingTimeInterval(7200)))
        XCTAssertEqual(s.windows.map(\.title), ["주간 한도"])
        XCTAssertNil(ClaudeUsage.parse(limits: sample, fetchedAt: now, now: now.addingTimeInterval(400_000)))
    }
    func testMissingOrInvalidDataIsUnknown() {
        XCTAssertNil(ClaudeUsage.parse(limits: [:], fetchedAt: now, now: now))
        XCTAssertNil(ClaudeUsage.parse(limits: ["five_hour": ["resets_at": 1]], fetchedAt: now, now: now))
        XCTAssertNil(ClaudeUsage.parse(limits: ["spend_limit": ["used_percentage": 10]], fetchedAt: now, now: now))
    }
    func testSettingsOverrideIsValidJSONAndQuotesThePath() throws {
        let json = ClaudeStatusLine.settingsJSON(executable: "/Applications/My Apps/NotchAgent.app/Contents/MacOS/NotchAgent")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let line = try XCTUnwrap(parsed["statusLine"] as? [String: String])
        XCTAssertEqual(line["type"], "command")
        XCTAssertEqual(line["command"], "'/Applications/My Apps/NotchAgent.app/Contents/MacOS/NotchAgent' --claude-statusline")
    }
    func testUserStatusLinePrecedence() throws {
        let home = directory.appendingPathComponent("home"), work = directory.appendingPathComponent("work")
        func write(_ url: URL, _ command: String) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]]).write(to: url)
        }
        XCTAssertNil(ClaudeStatusLine.userCommand(workspace: work, home: home))
        try write(home.appendingPathComponent(".claude/settings.json"), "user")
        XCTAssertEqual(ClaudeStatusLine.userCommand(workspace: work, home: home), "user")
        try write(work.appendingPathComponent(".claude/settings.json"), "project")
        XCTAssertEqual(ClaudeStatusLine.userCommand(workspace: work, home: home), "project")
        try write(work.appendingPathComponent(".claude/settings.local.json"), "local")
        XCTAssertEqual(ClaudeStatusLine.userCommand(workspace: work, home: home), "local")
        try write(work.appendingPathComponent(".claude/settings.local.json"), "x --claude-statusline") // never chain to ourselves
        XCTAssertNil(ClaudeStatusLine.userCommand(workspace: work, home: home))
    }

    /// Runs the real app binary the way Claude Code runs a status line command.
    private func runHelper(input: [String: Any], chain: String?) throws -> (output: String, status: Int32) {
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: try XCTUnwrap(Bundle.main.executablePath))
        process.arguments = [ClaudeStatusLine.argument]
        var env = ["NOTCHAGENT_SUPPORT_DIR": directory.path, "PATH": "/usr/bin:/bin"]
        if let chain { env[ClaudeStatusLine.chainVariable] = chain }
        process.environment = env
        process.standardInput = stdin; process.standardOutput = stdout
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: input))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: output, as: UTF8.self), process.terminationStatus)
    }
    private func stored() -> [String: Any]? {
        let url = directory.appendingPathComponent("claude-rate-limits.json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    func testHelperRecordsLimitsAndKeepsTheUsersStatusLine() throws {
        let input: [String: Any] = ["model": ["display_name": "Opus"], "rate_limits": sample, "session_id": "secret-ish"]
        // The user's own command still receives the full JSON and its output is what Claude shows.
        let result = try runHelper(input: input, chain: "grep -o '\"display_name\":\"Opus\"' >/dev/null && printf 'mine'; exit 7")
        XCTAssertEqual(result.output, "mine")
        XCTAssertEqual(result.status, 7)
        let saved = try XCTUnwrap(stored())
        XCTAssertEqual(Set(saved.keys), ["rate_limits", "fetched_at"], "only the limits are kept")
        XCTAssertNotNil(ClaudeUsage.load(from: directory.appendingPathComponent("claude-rate-limits.json"), now: now))
    }
    func testHelperWithoutUserStatusLinePrintsSummary() throws {
        var limits = sample
        limits["five_hour"] = ["used_percentage": 20, "resets_at": Date().addingTimeInterval(3600).timeIntervalSince1970]
        limits["seven_day"] = ["used_percentage": 50, "resets_at": Date().addingTimeInterval(86400).timeIntervalSince1970]
        let result = try runHelper(input: ["model": ["display_name": "Opus"], "rate_limits": limits], chain: nil)
        XCTAssertEqual(result.output, "Opus · 5시간 한도 80% 남음 · 주간 한도 50% 남음\n")
    }
    func testHelperBeforeFirstResponseLeavesStoreUntouched() throws {
        let result = try runHelper(input: ["model": ["display_name": "Opus"]], chain: nil)
        XCTAssertEqual(result.output, "Opus\n")
        XCTAssertNil(stored())
    }
    /// Regression: a user status line that never reads stdin used to kill the helper (SIGPIPE).
    func testHelperSurvivesStatusLineThatIgnoresInput() throws {
        let big = String(repeating: "x", count: 200_000) // larger than a pipe buffer
        let result = try runHelper(input: ["rate_limits": sample, "padding": big], chain: "printf ok")
        XCTAssertEqual(result.output, "ok")
        XCTAssertEqual(result.status, 0)
        XCTAssertNotNil(stored())
    }
    func testAgeLabel() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        XCTAssertEqual(UsageAge.label(since: now.addingTimeInterval(-20), now: now), "방금 전")
        XCTAssertEqual(UsageAge.label(since: now.addingTimeInterval(-5 * 60), now: now), "5분 전")
        XCTAssertEqual(UsageAge.label(since: now.addingTimeInterval(-3 * 3600), now: now), "3시간 전")
        XCTAssertEqual(UsageAge.label(since: now.addingTimeInterval(-2 * 86400), now: now), "2일 전")
    }
}

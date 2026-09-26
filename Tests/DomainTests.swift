import XCTest
@testable import NotchAgent

final class DomainTests: XCTestCase {
    func testShellQuote() {
        XCTAssertEqual(ShellSafety.quote("/tmp/my app"), "'/tmp/my app'")
        XCTAssertEqual(ShellSafety.quote("a'b;$(id)"), "'a'\\''b;$(id)'")
        XCTAssertEqual(ShellSafety.quote(""), "''")
    }
    func testShellQuoteRoundTripDoesNotExecuteMetacharacters() throws {
        let values = ["a'b;$(id)", "space path", "줄\n바꿈", "`echo injected`", ""]
        for value in values {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-fc", "printf '%s' " + ShellSafety.quote(value)]
            process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(String(data: output, encoding: .utf8), value)
        }
    }
    func testRemainingIsNotConsumedPercentage() throws {
        let s = try XCTUnwrap(UsageSnapshot.parse(limits: ["rateLimits": ["primary": ["usedPercent": 73.0, "windowDurationMins": 300]]], activity: nil, plan: nil))
        XCTAssertEqual(s.windows[0].remaining, 27)
        XCTAssertEqual(s.windows[0].title, "5시간 한도")
        XCTAssertNil(s.lifetimeTokens)
    }
    func testSpecificCodexBucketWins() throws {
        let s = try XCTUnwrap(UsageSnapshot.parse(limits: ["rateLimits": ["primary": ["usedPercent": 99.0]], "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 12.0]]]], activity: ["summary": ["lifetimeTokens": 123456]], plan: "pro"))
        XCTAssertEqual(s.windows[0].remaining, 88)
        XCTAssertEqual(s.lifetimeTokens, 123456)
    }
    func testMissingDataIsUnknownNotZero() {
        for limits: [String: Any] in [[:], ["rateLimits": NSNull()], ["rateLimits": ["primary": ["resetsAt": 123]]], ["rateLimits": ["primary": ["usedPercent": Double.nan]]]] {
            XCTAssertNil(UsageSnapshot.parse(limits: limits, activity: nil, plan: nil))
        }
    }
    func testUnknownBucketsAreNotMislabelledCodex() {
        XCTAssertNil(UsageSnapshot.parse(limits: ["rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 50.0]]]], activity: nil, plan: nil))
    }
    func testClampAndResetLabels() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(UsageWindow(id: "primary", usedPercent: 120, durationMinutes: nil, resetsAt: now).remaining, 0)
        XCTAssertEqual(UsageWindow(id: "primary", usedPercent: -10, durationMinutes: nil, resetsAt: nil).remaining, 100)
        XCTAssertEqual(UsageWindow(id: "secondary", usedPercent: 0, durationMinutes: 10080, resetsAt: now.addingTimeInterval(3660)).resetLabel(now: now), "1시간 1분 후 초기화")
    }
    func testStaleness() {
        XCTAssertTrue(UsageSnapshot(windows: [], fetchedAt: Date().addingTimeInterval(-601)).isStale)
        XCTAssertFalse(UsageSnapshot(windows: [], fetchedAt: Date()).isStale)
    }
    func testHoverSpeedsAreOrderedAndPersistable() {
        let delays = HoverSpeed.allCases.map(\.delay)
        XCTAssertEqual(delays, delays.sorted())
        XCTAssertEqual(HoverSpeed.default.delay, 0.22) // unchanged behaviour for existing users
        for speed in HoverSpeed.allCases { XCTAssertEqual(HoverSpeed(rawValue: speed.rawValue), speed) }
        XCTAssertEqual(HoverSpeed.fast.label, "빠르게 · 120ms")
    }
    func testExecutableOverrideDoesNotFallbackSilently() {
        XCTAssertNil(ShellSafety.executable("shell", override: "/not/a/real/program"))
        XCTAssertEqual(ShellSafety.executable("shell"), "/bin/zsh")
    }
}

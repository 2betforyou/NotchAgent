import XCTest
@testable import NotchAgent

final class NotchStatusTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 10_000)

    func testPriorityAttentionThenWorkThenQuotaThenCount() {
        let quotas: [(agent: AgentKind, remaining: Double)] = [(.codex, 84), (.claude, 12)]
        XCTAssertEqual(NotchStatus.resolve(attention: [.finished, .bell], workingSince: [t0], quotas: quotas, running: 3), .attention(.bell),
                       "a question beats a finished result")
        XCTAssertEqual(NotchStatus.resolve(attention: [.exited, .finished], workingSince: [], quotas: [], running: 1), .attention(.finished))
        XCTAssertEqual(NotchStatus.resolve(attention: [], workingSince: [t0.addingTimeInterval(30), t0], quotas: quotas, running: 3),
                       .working(since: t0), "the longest-running work is timed")
        XCTAssertEqual(NotchStatus.resolve(attention: [], workingSince: [], quotas: quotas, running: 3), .lowQuota(.claude, remaining: 12))
        XCTAssertEqual(NotchStatus.resolve(attention: [], workingSince: [], quotas: [(.codex, 21)], running: 2), .sessions(2),
                       "quota only shows once it is low")
        XCTAssertEqual(NotchStatus.resolve(attention: [], workingSince: [], quotas: [], running: 0), .empty)
    }
    func testElapsedFitsTheWing() {
        XCTAssertEqual(NotchStatus.elapsed(since: t0, now: t0.addingTimeInterval(151)), "2:31")
        XCTAssertEqual(NotchStatus.elapsed(since: t0, now: t0.addingTimeInterval(5)), "0:05")
        XCTAssertEqual(NotchStatus.elapsed(since: t0, now: t0.addingTimeInterval(3840)), "1h04")
        XCTAssertEqual(NotchStatus.elapsed(since: t0, now: t0.addingTimeInterval(-3)), "0:00")
    }
    @MainActor func testModelReflectsSessionState() {
        let model = AppModel()
        model.usage.enabled = false; model.claudeUsage.enabled = false
        let s = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: "/tmp/p"), executable: "/bin/zsh", fontSize: 13)
        model.sessions = [s]
        XCTAssertEqual(model.notchStatus, .empty, "a tab that never started is not running")
        s.recordOutput(at: Date())
        model.tickActivity()
        guard case .working = model.notchStatus else { return XCTFail("expected elapsed time while working") }
        s.terminal.onBell?()
        model.phase = .closed
        model.tickActivity()
        XCTAssertEqual(model.notchStatus, .attention(.bell))
    }
}

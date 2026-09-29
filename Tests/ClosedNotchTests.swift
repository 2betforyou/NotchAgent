import XCTest
@testable import NotchAgent

@MainActor
final class ClosedNotchTests: XCTestCase {
    private let ids = (0..<8).map { _ in UUID() }

    func testLayoutByNumberOfSessions() {
        XCTAssertEqual(ClosedNotchLayout.make([]), .idle)
        XCTAssertEqual(ClosedNotchLayout.make([ids[0]]), .single(ids[0]))
        XCTAssertEqual(ClosedNotchLayout.make(Array(ids.prefix(3))), .multi(left: [ids[0], ids[1]], right: [ids[2]]), "left gets the extra one")
        XCTAssertEqual(ClosedNotchLayout.make(ids), .multi(left: Array(ids.prefix(4)), right: Array(ids.suffix(4))))
    }
    func testWingsVanishWhenIdleAndStaySymmetric() {
        XCTAssertEqual(ClosedNotchLayout.idle.wingWidth, 0)
        XCTAssertEqual(ClosedNotchLayout.single(ids[0]).wingWidth, ClosedNotchLayout.singleWing)
        let three = ClosedNotchLayout.make(Array(ids.prefix(3))).wingWidth
        let four = ClosedNotchLayout.make(Array(ids.prefix(4))).wingWidth
        XCTAssertEqual(three, four, "an odd count does not tilt the island")
        XCTAssertLessThan(four, ClosedNotchLayout.make(ids).wingWidth)
    }
    func testBadges() {
        XCTAssertEqual(NotchBadge(attention: nil, working: false), .quiet)
        XCTAssertEqual(NotchBadge(attention: nil, working: true), .working)
        XCTAssertEqual(NotchBadge(attention: .finished, working: true), .done, "a result outranks ongoing output")
        XCTAssertEqual(NotchBadge(attention: .bell, working: false), .waiting)
        XCTAssertEqual(NotchBadge(attention: .failed, working: false), .error)
        XCTAssertEqual(NotchBadge(attention: .exited, working: false), .quiet, "a clean exit is not an error")
    }
    func testQuestionOutranksErrorOutranksResult() {
        XCTAssertEqual(NotchStatus.resolve(attention: [.finished, .failed], workingSince: [], quotas: [], running: 2), .attention(.failed))
        XCTAssertEqual(NotchStatus.resolve(attention: [.failed, .bell], workingSince: [], quotas: [], running: 2), .attention(.bell))
    }
    func testIdleNotchHasNoWingsAndAnErrorKeepsASmallOne() {
        let model = AppModel()
        model.usage.enabled = false; model.claudeUsage.enabled = false // no quota to show
        model.compactWidth = 285 // 185 pt camera + 100
        model.sessions = []
        XCTAssertEqual(model.closedWidth, 185, "idle: exactly the camera housing")
        model.lastError = "x"
        XCTAssertEqual(model.closedWidth, 185 + 64)
    }
    func testNonZeroExitIsAnError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentFail-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("s.zsh")
        try "#!/bin/zsh -f\nexit 3\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let s = TerminalSession(kind: .codex, directory: dir, executable: script.path, fontSize: 13)
        s.start()
        let deadline = Date().addingTimeInterval(5)
        while !s.ended && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(s.tick(now: Date(), visible: false), .failed)
        let model = AppModel(); model.sessions = [s]
        XCTAssertEqual(model.notchSessions.map(\.id), [s.id], "an unseen ended session stays in the notch")
    }
    private func snapshot(_ used: [Double]) -> UsageSnapshot {
        UsageSnapshot(windows: used.enumerated().map { index, value in
            UsageWindow(id: index == 0 ? "primary" : "secondary", usedPercent: value, durationMinutes: index == 0 ? 300 : 10080, resetsAt: nil)
        }, fetchedAt: Date())
    }
    func testIdleUsageRingIsWeeklyAndNumberIsFiveHour() throws {
        let usage = try XCTUnwrap(IdleUsage(agent: .claude, snapshot: snapshot([24, 85])))
        XCTAssertEqual(usage.session.remaining, 76, "the number: 5-hour limit")
        XCTAssertEqual(usage.weekly.remaining, 15, "the ring: weekly limit")
        let reversed = UsageSnapshot(windows: snapshot([24, 85]).windows.reversed(), fetchedAt: Date())
        XCTAssertEqual(IdleUsage(agent: .claude, snapshot: reversed), usage, "picked by length, not order")
        let single = try XCTUnwrap(IdleUsage(agent: .codex, snapshot: snapshot([40])))
        XCTAssertEqual(single.session, single.weekly, "one limit: ring and number both show it")
        XCTAssertNil(IdleUsage(agent: .codex, snapshot: nil))
        XCTAssertNil(IdleUsage(agent: .codex, snapshot: snapshot([])))
    }
    func testIdleNotchShowsUsageUntilASessionStarts() throws {
        let usage = [try XCTUnwrap(IdleUsage(agent: .codex, snapshot: snapshot([32, 16]))),
                     try XCTUnwrap(IdleUsage(agent: .claude, snapshot: snapshot([23, 3])))]
        XCTAssertEqual(ClosedNotchLayout.usage(usage).wingWidth, 84, "two agents: one per side with numbers")
        XCTAssertEqual(ClosedNotchLayout.usage([usage[0]]).wingWidth, ClosedNotchLayout.singleWing)
        let model = AppModel()
        model.usage.enabled = false; model.claudeUsage.enabled = false
        model.sessions = []
        XCTAssertEqual(model.closedLayout, .idle, "usage display off: nothing to show")
        let session = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: "/tmp"), executable: "/bin/zsh", fontSize: 13)
        session.start(); defer { session.stop() }
        model.sessions = [session]
        XCTAssertEqual(model.closedLayout, .single(session.id), "a session takes over the notch")
    }
    func testQuietSessionsKeepShowingUsage() throws {
        let suite = "NotchAgent.quiet." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let codex = UsageService(snapshot: snapshot([32, 58])); codex.enabled = true
        let model = AppModel(defaults: defaults, usage: codex)
        model.claudeUsage.enabled = false
        let tabs = (0..<2).map { _ in TerminalSession(kind: .codex, directory: URL(fileURLWithPath: "/tmp"), executable: "/bin/zsh", fontSize: 13) }
        tabs.forEach { $0.start() }; defer { TerminalSession.stopAll(tabs, grace: 0.2) }
        model.sessions = tabs
        guard case .usage = model.closedLayout else { return XCTFail("quiet sessions: usage stays by default") }
        model.quietNotchShowsUsage = false
        XCTAssertEqual(model.closedLayout, .multi(left: [tabs[0].id], right: [tabs[1].id]), "setting off: session icons")
        model.quietNotchShowsUsage = true
        tabs[1].terminal.onBell?(); _ = tabs[1].tick(now: Date(), visible: false)
        XCTAssertEqual(model.closedLayout, .multi(left: [tabs[0].id], right: [tabs[1].id]), "a session needing you takes the notch")
    }
}

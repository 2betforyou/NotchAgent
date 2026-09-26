import XCTest
@testable import NotchAgent

@MainActor
final class NotchBannerTests: XCTestCase {
    private var saved: (Any?, Any?)!
    override func setUp() async throws {
        let d = UserDefaults.standard
        saved = (d.object(forKey: "workspace"), d.object(forKey: "workspaces"))
    }
    override func tearDown() async throws {
        UserDefaults.standard.set(saved.0, forKey: "workspace")
        UserDefaults.standard.set(saved.1, forKey: "workspaces")
    }
    private let t0 = Date(timeIntervalSince1970: 5_000)
    private func model(with sessions: [TerminalSession]) -> AppModel {
        let m = AppModel()
        m.notifyEnabled = true
        m.sessions = sessions
        return m
    }
    private func session(_ kind: AgentKind = .claude, folder: String = "/tmp/proj") -> TerminalSession {
        TerminalSession(kind: kind, directory: URL(fileURLWithPath: folder), executable: "/bin/zsh", fontSize: 13)
    }
    private func streamOutput(_ s: TerminalSession, seconds: TimeInterval) {
        for x in stride(from: 0, through: seconds, by: 0.5) { s.recordOutput(at: t0.addingTimeInterval(x)) }
    }

    func testFinishedWorkWhileCollapsedShowsBannerThenHides() {
        let s = session(); let m = model(with: [s])
        m.phase = .closed
        streamOutput(s, seconds: 8)
        m.tickActivity(now: t0.addingTimeInterval(8.5))
        XCTAssertTrue(s.isWorking)
        XCTAssertNil(m.banner)
        m.tickActivity(now: t0.addingTimeInterval(11))
        XCTAssertEqual(m.banner?.reason, .finished)
        XCTAssertEqual(m.banner?.folder, "proj")
        XCTAssertEqual(s.attention, .finished)
        XCTAssertGreaterThan(m.closedHeight, m.notchHeight, "notch grows to show the notice")
        m.tickActivity(now: t0.addingTimeInterval(11 + NotchAppModelBannerDuration + 0.1))
        XCTAssertNil(m.banner)
        XCTAssertEqual(s.attention, .finished, "the dot stays until the user looks")
        XCTAssertEqual(m.closedHeight, m.notchHeight)
    }
    func testSessionBeingWatchedDoesNotNotify() {
        let s = session(); let m = model(with: [s])
        m.phase = .terminal; m.selectedID = s.id
        streamOutput(s, seconds: 8)
        m.tickActivity(now: t0.addingTimeInterval(11))
        XCTAssertNil(m.banner)
        XCTAssertNil(s.attention)
    }
    func testBellFromHiddenTabMarksAttentionWithoutBannerWhenOpen() {
        let a = session(), b = session(.codex); let m = model(with: [a, b])
        m.phase = .terminal; m.selectedID = a.id
        b.terminal.onBell?()
        m.tickActivity(now: t0)
        XCTAssertEqual(b.attention, .bell)
        XCTAssertNil(m.banner, "the open workspace shows tab dots instead of a notch notice")
        XCTAssertEqual(m.attention(in: "/tmp/proj"), .bell)
        m.selectedID = b.id
        m.tickActivity(now: t0.addingTimeInterval(1))
        XCTAssertNil(b.attention, "looking at the session clears it")
    }
    func testNoticesCanBeTurnedOff() {
        let s = session(); let m = model(with: [s])
        m.notifyEnabled = false; m.phase = .closed
        s.terminal.onBell?()
        m.tickActivity(now: t0)
        XCTAssertNil(m.banner)
        XCTAssertEqual(s.attention, .bell)
    }
    func testOpeningTheBannerShowsThatSession() {
        let here = session(.shell, folder: "/tmp/a"), there = session(.claude, folder: "/tmp/b")
        let m = model(with: [here, there])
        m.workspaces = [SavedWorkspace(path: "/tmp/a"), SavedWorkspace(path: "/tmp/b")]
        m.activateWorkspace("/tmp/a")
        m.phase = .closed
        there.terminal.onBell?()
        m.tickActivity(now: t0)
        m.openBanner()
        XCTAssertEqual(m.workspacePath, "/tmp/b")
        XCTAssertEqual(m.selectedID, there.id)
        XCTAssertNil(m.banner)
    }
    func testProcessExitWhileCollapsedIsNoticed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentExit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("s.zsh")
        try "#!/bin/zsh -f\nsleep 0.2\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let s = TerminalSession(kind: .codex, directory: dir, executable: script.path, fontSize: 13)
        let m = model(with: [s]); m.phase = .closed
        s.start()
        let deadline = Date().addingTimeInterval(5)
        while !s.ended && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        m.tickActivity()
        XCTAssertEqual(m.banner?.reason, .exited)
        m.tickActivity()
        XCTAssertEqual(m.banner?.reason, .exited, "not re-raised or replaced")
    }
}

private let NotchAppModelBannerDuration = AppModel.bannerDuration

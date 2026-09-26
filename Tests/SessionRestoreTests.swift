import XCTest
@testable import NotchAgent

final class SessionRestoreTests: XCTestCase {
    func testOnlyFirstAgentTabPerFolderResumes() {
        let saved = [SavedSession(kind: .claude, path: "/p/a"), SavedSession(kind: .claude, path: "/p/a/"),
                     SavedSession(kind: .claude, path: "/p/b"), SavedSession(kind: .codex, path: "/p/a"),
                     SavedSession(kind: .shell, path: "/p/a"), SavedSession(kind: .gemini, path: "/p/a")]
        XCTAssertEqual(SessionRestore.plan(saved).map(\.resume), [true, false, true, true, false, false])
        XCTAssertEqual(SessionRestore.resumeArguments(for: .claude), ["--continue"])
        XCTAssertEqual(SessionRestore.resumeArguments(for: .codex), ["resume", "--last"])
    }

    @MainActor func testOpenTabsComeBackUnstartedAndEndedOnesDoNot() throws {
        let d = UserDefaults.standard
        let keys = ["savedSessions", "restoreSessions", "workspace", "workspaces"]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d.set(v, forKey: k) } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentRestore-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = Workspaces.normalize(dir.path)

        let before = AppModel()
        before.restoreSessions = true
        before.workspaces = [SavedWorkspace(path: path)]
        before.activateWorkspace(path)
        before.launch(.shell); before.launch(.shell)
        let finished = try XCTUnwrap(before.sessions.last)
        finished.start(); finished.stop()          // the user ended this one
        before.saveSessions()
        TerminalSession.stopAll(before.sessions)

        let after = AppModel()
        after.workspaces = [SavedWorkspace(path: path)]
        after.activateWorkspace(path)
        after.restoreSavedSessions()
        XCTAssertEqual(after.sessions.count, 1)
        XCTAssertEqual(after.sessions.first?.kind, .shell)
        XCTAssertEqual(after.sessions.first.map { Workspaces.normalize($0.initialDirectory.path) }, path)
        XCTAssertEqual(after.sessions.first?.started, false, "restored tabs start only when opened")
        XCTAssertEqual(after.runningCount, 0)
        XCTAssertEqual(after.selectedID, after.sessions.first?.id)

        after.restoreSessions = false
        XCTAssertNil(d.data(forKey: "savedSessions"), "turning it off forgets saved tabs")
    }
}

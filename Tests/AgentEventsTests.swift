import XCTest
@testable import NotchAgent

@MainActor
final class AgentEventsTests: XCTestCase {
    func testClaudeHookInputs() {
        func parse(_ json: [String: Any]) -> AgentEvent? { AgentEvents.parseClaude(json).event }
        XCTAssertEqual(parse(["hook_event_name": "UserPromptSubmit", "session_id": "s1"]), .started)
        XCTAssertEqual(parse(["hook_event_name": "Stop"]), .finished)
        XCTAssertEqual(parse(["hook_event_name": "Notification", "notification_type": "permission_prompt"]), .needsInput)
        XCTAssertNil(parse(["hook_event_name": "Notification", "notification_type": "idle_prompt"]), "idle reminders are not new events")
        let start = AgentEvents.parseClaude(["hook_event_name": "SessionStart", "session_id": "abc"])
        XCTAssertNil(start.event)
        XCTAssertEqual(start.conversation, "abc")
    }
    func testCodexNotifyPayloads() {
        let done = AgentEvents.parseCodex(["type": "agent-turn-complete", "thread-id": "t-9"])
        XCTAssertEqual(done.event, .finished); XCTAssertEqual(done.conversation, "t-9")
        XCTAssertEqual(AgentEvents.parseCodex(["type": "approval-requested"]).event, .needsInput)
        XCTAssertNil(AgentEvents.parseCodex(["type": "something-new"]).event)
    }
    func testReadsTheUsersOwnCodexNotifySoItKeepsWorking() {
        let config = """
        model = "gpt"
        notify = ["/Applications/My App.app/bin/client", 'turn-ended', "say \\"hi\\""]
        [tui]
        notify = ["not-top-level"]
        """
        XCTAssertEqual(AgentEvents.userCodexNotify(configText: config), .command(["/Applications/My App.app/bin/client", "turn-ended", "say \"hi\""]))
        XCTAssertEqual(AgentEvents.userCodexNotify(configText: "[tui]\nnotify = [\"x\"]"), .absent)
        XCTAssertEqual(AgentEvents.userCodexNotify(configText: "notify_other = [\"x\"]"), .absent)
    }
    func testOverridesAreWellFormed() throws {
        XCTAssertEqual(AgentEvents.codexNotifyOverride(executable: "/A B/Notch\"Agent"),
                       #"notify=["/A B/Notch\"Agent", "--agent-event", "codex"]"#)
        let json = ClaudeStatusLine.settingsJSON(executable: "/x/NotchAgent", statusLine: false, hooks: true)
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertNil(settings["statusLine"])
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["SessionStart", "UserPromptSubmit", "Stop", "Notification"])
        let stop = try XCTUnwrap((hooks["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(stop.first?["async"] as? Bool, true, "never slows Claude down")
        XCTAssertEqual(stop.first?["command"] as? String, "'/x/NotchAgent' --agent-event claude")
    }

    // MARK: Session behaviour with precise events

    private func session(_ kind: AgentKind) -> TerminalSession {
        TerminalSession(kind: kind, directory: URL(fileURLWithPath: "/tmp/p"), executable: "/bin/zsh", fontSize: 13)
    }
    func testClaudeWorkingIsExactAndFinishIsAnnouncedOnce() {
        let s = session(.claude), t0 = Date()
        s.receive(.started, conversation: "c1", now: t0)
        s.recordOutput(at: t0) // output timing is ignored once hooks report
        XCTAssertNil(s.tick(now: t0.addingTimeInterval(30), visible: false))
        XCTAssertTrue(s.isWorking, "a long silent think still counts as working")
        XCTAssertEqual(s.workingSince, t0)
        s.receive(.finished, conversation: "c1", now: t0.addingTimeInterval(40))
        XCTAssertEqual(s.tick(now: t0.addingTimeInterval(41), visible: false), .finished)
        XCTAssertFalse(s.isWorking)
        XCTAssertNil(s.tick(now: t0.addingTimeInterval(60), visible: false), "no second announcement")
        XCTAssertEqual(s.conversationID, "c1")
    }
    func testPermissionRequestAsksForTheUser() {
        let s = session(.claude)
        s.receive(.needsInput, conversation: nil, now: Date())
        XCTAssertEqual(s.tick(now: Date(), visible: false), .bell)
    }
    func testGuessAndNotifyForTheSameTurnAnnounceOnce() {
        let s = session(.codex), t0 = Date(timeIntervalSince1970: 1_000_000)
        for x in stride(from: 0.0, through: 8, by: 0.5) { s.recordOutput(at: t0.addingTimeInterval(x)) }
        XCTAssertEqual(s.tick(now: t0.addingTimeInterval(11), visible: false), .finished) // guessed
        s.receive(.finished, conversation: "thread", now: t0.addingTimeInterval(12))      // then notify arrives
        XCTAssertNil(s.tick(now: t0.addingTimeInterval(13), visible: false))
        XCTAssertEqual(s.conversationID, "thread")
    }
    func testRestoreUsesExactConversationIds() {
        let saved = [SavedSession(kind: .claude, path: "/p", conversation: "a"), SavedSession(kind: .claude, path: "/p", conversation: "b"),
                     SavedSession(kind: .claude, path: "/p"), SavedSession(kind: .claude, path: "/p")]
        XCTAssertEqual(SessionRestore.plan(saved).map(\.resume), [true, true, true, false])
        XCTAssertEqual(SessionRestore.resumeArguments(for: .claude, conversation: "a"), ["--resume", "a"])
        XCTAssertEqual(SessionRestore.resumeArguments(for: .codex, conversation: "t"), ["resume", "t"])
        let old = try? JSONDecoder().decode(SavedSession.self, from: Data(#"{"kind":"claude","path":"/p"}"#.utf8))
        XCTAssertEqual(old?.conversation, nil, "tabs saved by older versions still load")
    }

    // MARK: End to end through the real binary

    func testHelperDeliversEventsToTheApp() throws {
        let model = AppModel()
        let s = session(.claude)
        model.sessions = [s]
        let token = DistributedNotificationCenter.default().addObserver(forName: AgentEvents.notification, object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated {
                model.handleAgentEvent(session: info["session"] as? String ?? "", event: info["event"] as? String ?? "",
                                       conversation: info["conversation"] as? String ?? "")
            }
        }
        defer { DistributedNotificationCenter.default().removeObserver(token) }
        let process = Process(), stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: try XCTUnwrap(Bundle.main.executablePath))
        process.arguments = [AgentEvents.argument, "claude"]
        process.environment = [AgentEvents.sessionVariable: s.id.uuidString, "PATH": "/usr/bin:/bin"]
        process.standardInput = stdin
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: JSONSerialization.data(withJSONObject: ["hook_event_name": "UserPromptSubmit", "session_id": "live-1"]))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        while s.conversationID == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(s.conversationID, "live-1")
        _ = s.tick(now: Date(), visible: true)
        XCTAssertTrue(s.isWorking)
    }
    func testCodexNotifyReachesTheAppAndStillRunsTheUsersOwnProgram() throws {
        let model = AppModel()
        let s = session(.codex)
        model.sessions = [s]
        let token = DistributedNotificationCenter.default().addObserver(forName: AgentEvents.notification, object: nil, queue: .main) { note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated {
                model.handleAgentEvent(session: info["session"] as? String ?? "", event: info["event"] as? String ?? "",
                                       conversation: info["conversation"] as? String ?? "")
            }
        }
        defer { DistributedNotificationCenter.default().removeObserver(token) }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentChain-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: out) }
        // Stands in for the user's existing notify program: it records the payload it is given.
        let chain = try JSONSerialization.data(withJSONObject: ["/bin/sh", "-c", "printf '%s' \"$1\" > '\(out.path)'", "sh"])
        let payload = #"{"type":"agent-turn-complete","thread-id":"thread-42","turn-id":"1"}"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try XCTUnwrap(Bundle.main.executablePath))
        process.arguments = [AgentEvents.argument, "codex", payload]
        process.environment = [AgentEvents.sessionVariable: s.id.uuidString, AgentEvents.codexChainVariable: String(decoding: chain, as: UTF8.self)]
        try process.run(); process.waitUntilExit()
        let deadline = Date().addingTimeInterval(5)
        while (s.conversationID == nil || !FileManager.default.fileExists(atPath: out.path)) && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(s.conversationID, "thread-42")
        XCTAssertEqual(s.tick(now: Date(), visible: false), .finished)
        XCTAssertEqual(try? String(contentsOf: out, encoding: .utf8), payload, "the user's notify program got the same payload")
    }
}

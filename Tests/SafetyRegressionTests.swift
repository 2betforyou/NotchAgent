import AppKit
import Testing
@testable import NotchAgent

@Suite("Session and notification safety")
struct SafetyRegressionTests {
    @Test("Multiline Codex notify commands are chained")
    func multilineNotify() {
        let config = """
        model = "gpt"
        notify = [
          "/Applications/My App.app/bin/client", # keep this command
          'turn-ended',
          "say \\u263A",
        ]
        [tui]
        theme = "dark"
        """
        #expect(AgentEvents.userCodexNotify(configText: config) ==
                .command(["/Applications/My App.app/bin/client", "turn-ended", "say ☺"]))
    }

    @Test("Unknown Codex notify syntax is preserved rather than overridden")
    func unsupportedNotify() {
        #expect(AgentEvents.userCodexNotify(configText: #"notify = ["program", "bad \e escape"]"#) == .unsupported)
        #expect(AgentEvents.userCodexNotify(configText: #""notify" = ["program"]"#) == .command(["program"]))
    }

    @MainActor @Test("Failed worktree removal leaves its running agent alive")
    func failedWorktreeRemovalKeepsSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentSafety-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try Worktree.git(["init", "-b", "main"], in: repo.path)
        try "initial\n".write(to: repo.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try Worktree.git(["add", "."], in: repo.path)
        try Worktree.git(["-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-m", "init"], in: repo.path)
        let path = try Worktree.create(repository: repo.path, branch: "dirty")
        try "unsaved\n".write(toFile: path + "/README", atomically: true, encoding: .utf8)

        let session = TerminalSession(kind: .codex, directory: URL(fileURLWithPath: path), executable: "/bin/zsh", fontSize: 13)
        session.start()
        defer { session.stop(grace: 0.2) }
        #expect(session.isRunning)
        let model = AppModel()
        model.sessions = [session]
        await model.finishRemovingWorktree(path)
        #expect(model.lastError != nil)
        #expect(session.isRunning)
        #expect(model.sessions.contains { $0.id == session.id })
        #expect(FileManager.default.fileExists(atPath: path + "/README"))
    }
}

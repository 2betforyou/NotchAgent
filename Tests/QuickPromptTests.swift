import XCTest
@testable import NotchAgent

@MainActor
final class QuickPromptTests: XCTestCase {
    func testPromptArgumentsPerAgent() {
        for kind in [AgentKind.codex, .claude, .gemini] {
            XCTAssertNotNil(AgentLogo.artwork[kind], "Bundled official icon must load for \(kind)")
        }
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .claude, prompt: "테스트 고쳐줘"), ["테스트 고쳐줘"])
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .codex, prompt: "fix it"), ["fix it"])
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .gemini, prompt: "hi"), ["--prompt-interactive", "hi"])
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .claude, prompt: "-v 옵션 설명"), [" -v 옵션 설명"], "not parsed as a flag")
    }
    func testSubmittingStartsTheChosenAgentInTheCurrentFolder() throws {
        let suite = "NotchAgent.QuickPromptTests." + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("/bin/echo", forKey: "codexPath") // stands in for codex; never started by this test
        let model = AppModel(defaults: d)
        let folder = Workspaces.normalize(FileManager.default.temporaryDirectory.path)
        model.workspaces = [SavedWorkspace(path: folder)]
        model.activateWorkspace(folder)
        var opened = false
        model.showTerminal = { opened = true }
        model.quickAgent = .codex
        model.quickPromptActive = true
        model.submitQuickPrompt("README 요약해줘")
        let session = try XCTUnwrap(model.sessions.last)
        XCTAssertEqual(session.kind, .codex)
        XCTAssertEqual(session.commandLine.first, "/bin/echo")
        XCTAssertEqual(session.commandLine.last, "README 요약해줘", "the prompt comes last")
        XCTAssertEqual(session.commandLine[1], "--no-alt-screen", "Codex uses inline terminal mode")
        XCTAssertEqual(session.commandLine[2], "-c", "Codex also gets NotchAgent's notify hook")
        XCTAssertEqual(Workspaces.normalize(session.initialDirectory.path), folder)
        XCTAssertFalse(model.quickPromptActive)
        XCTAssertTrue(opened, "the terminal opens on the new session")
        XCTAssertEqual(model.selectedID, session.id)
    }
    func testCancelReleasesFocus() {
        let model = AppModel()
        var collapsed = false
        model.collapse = { collapsed = true }
        model.quickPromptActive = true
        model.cancelQuickPrompt()
        XCTAssertFalse(model.quickPromptActive)
        XCTAssertTrue(collapsed)
    }
    func testTemporaryChatIsIndependentAndNotPersisted() throws {
        let suite = "NotchAgent.TempChatTests." + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("/bin/echo", forKey: "codexPath")
        let model = AppModel(defaults: d)
        model.restoreSessions = true
        model.keepRecentActivities = true
        let project = model.workspacePath
        let workspaces = model.workspaces
        model.quickChatIsTemporary = true
        XCTAssertTrue(model.submitQuickPrompt("Explain a concept"))
        let first = try XCTUnwrap(model.selected)
        defer { try? FileManager.default.removeItem(at: first.initialDirectory) }
        XCTAssertTrue(first.isTemporary)
        XCTAssertNotEqual(first.initialDirectory.path, project)
        XCTAssertTrue(first.initialDirectory.path.contains("NotchAgent-Chats/"))
        XCTAssertTrue(model.showsTemporaryChats)
        XCTAssertEqual(model.visibleSessions.map(\.id), [first.id])
        XCTAssertEqual(model.workspacePath, project)
        XCTAssertEqual(model.workspaces, workspaces)
        let saved = try JSONDecoder().decode([SavedSession].self, from: XCTUnwrap(d.data(forKey: "savedSessions")))
        XCTAssertTrue(saved.isEmpty)
        model.recordActivity(.finished, for: first, now: Date())
        XCTAssertNil(d.data(forKey: "recentActivities"))
        XCTAssertNil(model.recentActivities.first?.projectPath)
        model.activateWorkspace(project)
        XCTAssertTrue(model.visibleSessions.isEmpty)
        model.selectTemporaryChats()
        XCTAssertEqual(model.selectedID, first.id)
        XCTAssertTrue(model.launch(.codex))
        let second = try XCTUnwrap(model.selected)
        defer { try? FileManager.default.removeItem(at: second.initialDirectory) }
        XCTAssertTrue(second.isTemporary)
        XCTAssertNotEqual(second.initialDirectory, first.initialDirectory)
    }
}

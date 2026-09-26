import XCTest
@testable import NotchAgent

@MainActor
final class QuickPromptTests: XCTestCase {
    func testPromptArgumentsPerAgent() {
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .claude, prompt: "테스트 고쳐줘"), ["테스트 고쳐줘"])
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .codex, prompt: "fix it"), ["fix it"])
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .gemini, prompt: "hi"), ["--prompt-interactive", "hi"])
        XCTAssertEqual(SessionRestore.initialPromptArguments(for: .claude, prompt: "-v 옵션 설명"), [" -v 옵션 설명"], "not parsed as a flag")
    }
    func testSubmittingStartsTheChosenAgentInTheCurrentFolder() throws {
        let d = UserDefaults.standard
        let keys = ["codexPath", "quickAgent", "workspace", "workspaces", "savedSessions"]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d.set(v, forKey: k) } }
        d.set("/bin/echo", forKey: "codexPath") // stands in for codex; never started by this test
        let model = AppModel()
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
        XCTAssertEqual(session.commandLine[1], "-c", "Codex also gets NotchAgent's notify hook")
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
}

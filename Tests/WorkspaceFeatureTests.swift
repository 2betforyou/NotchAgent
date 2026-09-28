import AppKit
import Testing
@testable import NotchAgent

@MainActor
@Suite("Workspace usability")
struct WorkspaceFeatureTests {
    private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let name = "NotchAgent.FeatureTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(AppModel(defaults: defaults), defaults)
    }
    private func session(_ folder: URL, title: String? = nil) -> TerminalSession {
        TerminalSession(kind: .shell, directory: folder, executable: "/bin/zsh", fontSize: 13, title: title)
    }

    @Test("A custom tab name survives restoration and can return to the terminal title")
    func namedTabRestoration() throws {
        try withModel { model, defaults in
            let folder = FileManager.default.temporaryDirectory
            let original = session(folder, title: "Implement sign-in")
            model.sessions = [original]
            model.setSessionName(original, name: "  로그인 작업\n  ")
            #expect(original.displayTitle == "로그인 작업")
            let restored = AppModel(defaults: defaults)
            restored.restoreSavedSessions()
            let tab = try #require(restored.sessions.first)
            #expect(tab.displayTitle == "로그인 작업")
            #expect(tab.title == "Implement sign-in")
            #expect(!tab.started)
            restored.setSessionName(tab, name: " ")
            #expect(tab.displayTitle == "Implement sign-in")
            let old = try JSONDecoder().decode(SavedSession.self, from: Data(#"{"kind":"shell","path":"/tmp"}"#.utf8))
            #expect(old.customTitle == nil)
        }
    }

    @Test("Dropped folders are added once, selected, and restored")
    func folderDrop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentDrop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("image.png")
        try Data().write(to: file)
        try withModel { model, defaults in
            var opened = 0
            model.showTerminal = { opened += 1 }
            #expect(!model.addDroppedFolders([file]))
            #expect(model.addDroppedFolders([root, file, root]))
            #expect(opened == 1)
            #expect(model.workspacePath == Workspaces.normalize(root.path))
            #expect(model.workspaces.filter { $0.path == Workspaces.normalize(root.path) }.count == 1)
            #expect(AppModel(defaults: defaults).workspacePath == model.workspacePath)
        }
    }

    @Test("File paths are quoted and never contain terminal control characters")
    func filePathSafety() {
        let urls = [URL(fileURLWithPath: "/tmp/a b.png"), URL(fileURLWithPath: "/tmp/it's $(touch nope).txt")]
        #expect(FileDrop.text(for: urls) == "'/tmp/a b.png' '/tmp/it'\\''s $(touch nope).txt' ")
        #expect(FileDrop.text(for: [URL(fileURLWithPath: "/tmp/line\nbreak")]) == nil)
        #expect(FileDrop.text(for: [URL(string: "https://example.com/file")!]) == nil)
        #expect(FileDrop.text(for: []) == nil)
    }

    @Test("Missed events remain after the banner disappears, and opening them marks them read")
    func recentActivityNavigation() throws {
        try withModel { model, _ in
            let s = session(URL(fileURLWithPath: "/tmp/other-project"), title: "Tests")
            model.sessions = [s]
            model.phase = .closed
            var delivered = 0
            model.activityOccurred = { _ in delivered += 1 }
            let now = Date()
            s.receive(.finished, conversation: nil, now: now)
            model.tickActivity(now: now)
            model.tickActivity(now: now.addingTimeInterval(10))
            #expect(model.banner == nil)
            #expect(model.recentActivities.count == 1)
            #expect(delivered == 1)
            #expect(model.unreadActivityCount == 1)
            model.openSession(id: s.id)
            #expect(model.selectedID == s.id)
            #expect(model.workspacePath == "/tmp/other-project")
            #expect(model.unreadActivityCount == 0)
            #expect(model.recentActivities.count == 1)
        }
    }

    @Test("An inactive expanded terminal still records missed events, with bounded history")
    func inactiveTerminalAndHistoryLimit() throws {
        try withModel { model, _ in
            let s = session(URL(fileURLWithPath: "/tmp/project"))
            model.sessions = [s]; model.selectedID = s.id; model.phase = .terminal
            let now = Date()
            s.receive(.needsInput, conversation: nil, now: now)
            model.tickActivity(now: now, terminalIsVisible: true)
            #expect(model.recentActivities.isEmpty)
            s.receive(.needsInput, conversation: nil, now: now)
            model.tickActivity(now: now, terminalIsVisible: false)
            #expect(model.unreadActivityCount == 1)
            for offset in 1...60 {
                model.recordActivity(.finished, for: s, now: now.addingTimeInterval(Double(offset)))
            }
            #expect(model.recentActivities.count == AppModel.activityLimit)
            #expect(model.recentActivities.first?.date == now.addingTimeInterval(60))
            model.clearRecentActivities()
            #expect(model.unreadActivityCount == 0)
        }
    }

    @Test("Window presets fit smaller screens and preferences survive relaunch")
    func windowPreferences() throws {
        let screen = CGSize(width: 1024, height: 768)
        #expect(TerminalSize.large.fitted(to: screen) == CGSize(width: 960, height: 668))
        try withModel { model, defaults in
            #expect(!model.systemNotificationsEnabled && !model.activitySoundEnabled)
            var resized = false
            model.layoutChanged = { resized = true }
            model.terminalSize = .large; model.collapseOnDeactivate = true
            let restored = AppModel(defaults: defaults)
            #expect(resized)
            #expect(restored.terminalSize == .large)
            #expect(restored.collapseOnDeactivate)
        }
    }
}

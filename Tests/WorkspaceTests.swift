import XCTest
@testable import NotchAgent

final class WorkspaceTests: XCTestCase {
    func testNormalizeMakesEquivalentPathsEqual() {
        XCTAssertEqual(Workspaces.normalize("/tmp/a/../b/"), "/tmp/b")
        XCTAssertEqual(Workspaces.normalize("~/x"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("x").path)
        XCTAssertEqual(Workspaces.normalize("/"), "/")
    }
    func testMigrationKeepsPreviousFoldersWithActiveFirstAndNoDuplicates() {
        let recent = [SavedWorkspace(path: "/p/b"), SavedWorkspace(path: "/p/a/"), SavedWorkspace(path: "/p/c")]
        XCTAssertEqual(Workspaces.migrate(saved: nil, recent: recent, active: "/p/a").map(\.path), ["/p/a", "/p/b", "/p/c"])
        // Once saved, the user's own order wins and the active folder is always present.
        let saved = [SavedWorkspace(path: "/p/c"), SavedWorkspace(path: "/p/b")]
        XCTAssertEqual(Workspaces.migrate(saved: saved, recent: recent, active: "/p/b").map(\.path), ["/p/c", "/p/b"])
        XCTAssertEqual(Workspaces.migrate(saved: saved, recent: [], active: "/p/z").map(\.path), ["/p/z", "/p/c", "/p/b"])
    }
    func testSameNamedFoldersAreDisambiguated() {
        let labels = Workspaces.labels([SavedWorkspace(path: "/work/alpha/app"), SavedWorkspace(path: "/work/beta/app"), SavedWorkspace(path: "/work/site")])
        XCTAssertEqual(labels["/work/alpha/app"], "app — alpha")
        XCTAssertEqual(labels["/work/beta/app"], "app — beta")
        XCTAssertEqual(labels["/work/site"], "site")
    }
    func testGitBranchForRepositoryWorktreeAndDetachedHead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentGit-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo"), git = repo.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: git.appendingPathComponent("worktrees/feature"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Workspaces.gitBranch(at: repo.path), "main")
        // Linked worktree: `.git` is a file pointing at the per-worktree git dir.
        let tree = root.appendingPathComponent("feature")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try "gitdir: ../repo/.git/worktrees/feature\n".write(to: tree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "ref: refs/heads/feature/checkout\n".write(to: git.appendingPathComponent("worktrees/feature/HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Workspaces.gitBranch(at: tree.path), "feature/checkout")
        try "8e7a1e154f470e19c709a00a8768df348ba5fc43\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Workspaces.gitBranch(at: repo.path), "8e7a1e1")
        XCTAssertNil(Workspaces.gitBranch(at: root.path))
    }
    /// Switching folders shows only that folder's sessions and remembers each folder's last tab;
    /// removing a folder ends only its sessions.
    @MainActor func testSwitchingAndRemovingFolders() {
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "workspace"), defaults.object(forKey: "workspaces"))
        defer { defaults.set(saved.0, forKey: "workspace"); defaults.set(saved.1, forKey: "workspaces") }
        let tmp = FileManager.default.temporaryDirectory
        let a = Workspaces.normalize(tmp.appendingPathComponent("A").path), b = Workspaces.normalize(tmp.appendingPathComponent("B").path)
        let model = AppModel()
        model.workspaces = [SavedWorkspace(path: a), SavedWorkspace(path: b)]
        func session(_ path: String) -> TerminalSession {
            TerminalSession(kind: .shell, directory: URL(fileURLWithPath: path), executable: "/bin/zsh", fontSize: 13)
        }
        let a1 = session(a), b1 = session(b), a2 = session(a)
        model.sessions = [a1, b1, a2]
        model.activateWorkspace(a)
        XCTAssertEqual(model.visibleSessions.map(\.id), [a1.id, a2.id])
        XCTAssertEqual(model.selectedID, a2.id)
        model.selectedID = a1.id
        model.activateWorkspace(b)
        XCTAssertEqual(model.visibleSessions.map(\.id), [b1.id])
        XCTAssertEqual(model.selectedID, b1.id)
        model.activateWorkspace(a)
        XCTAssertEqual(model.selectedID, a1.id, "last tab per folder is remembered")
        XCTAssertEqual(model.runningCount(in: b), 1)

        var asked = false
        model.runAlert = { _ in asked = true; return .alertSecondButtonReturn }
        model.removeWorkspace(b)
        XCTAssertTrue(asked, "removing a folder with running sessions asks first")
        XCTAssertEqual(model.workspaces.map(\.path), [a])
        XCTAssertEqual(model.sessions.map(\.id), [a1.id, a2.id])
        XCTAssertEqual(model.workspacePath, a)

        model.runAlert = { _ in .alertFirstButtonReturn } // cancel keeps everything
        model.workspaces.append(SavedWorkspace(path: b)); model.sessions.append(b1)
        model.removeWorkspace(b)
        XCTAssertEqual(model.workspaces.count, 2)
    }
}

import XCTest
@testable import NotchAgent

final class WorktreeTests: XCTestCase {
    private var root: URL!
    private var repo: String!
    override func setUpWithError() throws {
        AppLanguage.current = .korean
        root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentWT-" + UUID().uuidString)
        let url = root.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        repo = Workspaces.normalize(url.path)
        try Worktree.git(["init", "-b", "main"], in: repo)
        try "hello\n".write(to: url.appendingPathComponent("README"), atomically: true, encoding: .utf8)
        try Worktree.git(["add", "."], in: repo)
        try Worktree.git(["-c", "user.name=test", "-c", "user.email=test@example.com", "commit", "-m", "init"], in: repo)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCreatesWorktreeOnNewBranchBesideTheRepository() throws {
        let path = try Worktree.create(repository: repo, branch: "feature/login")
        XCTAssertEqual(path, root.appendingPathComponent("app.worktrees/feature-login").path)
        XCTAssertTrue(Worktree.isLinked(path))
        XCTAssertFalse(Worktree.isLinked(repo))
        XCTAssertTrue(Worktree.isRepository(repo))
        XCTAssertEqual(Workspaces.gitBranch(at: path), "feature/login")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "/README"))
    }
    func testExistingBranchIsCheckedOut() throws {
        try Worktree.git(["branch", "fix"], in: repo)
        let path = try Worktree.create(repository: repo, branch: "fix")
        XCTAssertEqual(Workspaces.gitBranch(at: path), "fix")
    }
    func testRejectsBadNamesAndCollisions() throws {
        XCTAssertThrowsError(try Worktree.create(repository: repo, branch: "  ")) { error in
            XCTAssertEqual(error.localizedDescription, "브랜치 이름을 입력하세요.")
        }
        XCTAssertThrowsError(try Worktree.create(repository: repo, branch: "bad..name"))
        _ = try Worktree.create(repository: repo, branch: "same")
        XCTAssertThrowsError(try Worktree.create(repository: repo, branch: "same"), "folder already exists")
    }
    func testRemoveCleanWorktreeButKeepDirtyOne() throws {
        let clean = try Worktree.create(repository: repo, branch: "clean")
        try Worktree.remove(clean)
        XCTAssertFalse(FileManager.default.fileExists(atPath: clean))
        XCTAssertNoThrow(try Worktree.git(["rev-parse", "--verify", "refs/heads/clean"], in: repo), "the branch survives")

        let dirty = try Worktree.create(repository: repo, branch: "dirty")
        try "work in progress\n".write(toFile: dirty + "/README", atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Worktree.remove(dirty))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirty + "/README"), "uncommitted work is never deleted")
    }

    @MainActor func testNewWorktreeChipGoesNextToItsRepository() {
        let d = UserDefaults.standard
        let saved = (d.object(forKey: "workspace"), d.object(forKey: "workspaces"))
        defer { d.set(saved.0, forKey: "workspace"); d.set(saved.1, forKey: "workspaces") }
        let model = AppModel()
        model.workspaces = [SavedWorkspace(path: repo), SavedWorkspace(path: "/tmp/other")]
        model.finishCreatingWorktree(.success(repo + ".worktrees/x"), after: repo)
        XCTAssertEqual(model.workspaces.map(\.path), [repo, repo + ".worktrees/x", "/tmp/other"])
        XCTAssertEqual(model.workspacePath, repo + ".worktrees/x")
        model.finishCreatingWorktree(.failure(Worktree.Failure.git("boom")), after: repo)
        XCTAssertEqual(model.lastError, "boom")
    }
}

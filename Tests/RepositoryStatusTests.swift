import XCTest
@testable import NotchAgent

final class RepositoryStatusTests: XCTestCase {
    func testGitHubRemoteParsingAndLinkValidation() throws {
        let expected = GitHubRepository(owner: "owner", name: "repo")
        for remote in ["git@github.com:owner/repo.git", "https://github.com/owner/repo.git", "ssh://git@github.com/owner/repo.git"] {
            XCTAssertEqual(GitHubRepository.parse(remote), expected)
        }
        for remote in ["https://github.com.evil.test/owner/repo", "git@gitlab.com:owner/repo", "https://github.com/owner/repo/extra", "https://github.com/../repo"] {
            XCTAssertNil(GitHubRepository.parse(remote))
        }
        XCTAssertNotNil(expected.safeURL("https://github.com/owner/repo/pull/1"))
        XCTAssertNil(expected.safeURL("https://evil.test/owner/repo/pull/1"))
        XCTAssertNil(expected.safeURL("https://github.com/owner/repository/pull/1"))
    }
    func testPorcelainHandlesRenamesAndSpacesWithoutDoubleCounting() {
        XCTAssertEqual(RepositoryProbe.changedFiles(""), 0)
        XCTAssertEqual(RepositoryProbe.changedFiles(" M file one.swift\0?? image.png\0R  new name\0old name\0"), 3)
    }
    func testChecksDoNotReportPendingOrMissingAsPassed() {
        XCTAssertEqual(RepositoryChecks.resolve([]), .none)
        XCTAssertEqual(RepositoryChecks.resolve([["conclusion": "SUCCESS"], ["state": "SUCCESS"]]), .passed)
        XCTAssertEqual(RepositoryChecks.resolve([["conclusion": "", "status": "IN_PROGRESS"]]), .pending)
        XCTAssertEqual(RepositoryChecks.resolve([["conclusion": "SUCCESS"], ["conclusion": "FAILURE"]]), .failed)
        XCTAssertEqual(RepositoryChecks.resolve([["state": "PENDING"]]), .pending)
    }
    func testPRParsingRejectsForeignURL() throws {
        let repo = GitHubRepository(owner: "owner", name: "repo")
        let json: [[String: Any]] = [["number": 42, "title": "Improve UI", "url": "https://github.com/owner/repo/pull/42", "isDraft": true,
                                     "statusCheckRollup": [["conclusion": "SUCCESS"]]]]
        let pr = try XCTUnwrap(RepositoryPullRequest.parse(JSONSerialization.data(withJSONObject: json), repository: repo))
        XCTAssertEqual(pr.number, 42)
        XCTAssertTrue(pr.draft)
        XCTAssertEqual(pr.checks, .passed)
        XCTAssertNil(RepositoryPullRequest.parse(Data("[]".utf8), repository: repo))
        XCTAssertNil(RepositoryPullRequest.parse(Data("[{\"number\":1,\"url\":\"https://evil.test/\"}]".utf8), repository: repo))
    }
    func testLocalRepositoryAndNonRepository() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgent-Repo-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertNil(RepositoryProbe.read(path: root.path, github: false))
        try Worktree.git(["init"], in: root.path)
        try Worktree.git(["remote", "add", "origin", "git@github.com:owner/repo.git"], in: root.path)
        try "sample".write(to: root.appendingPathComponent("sample.txt"), atomically: true, encoding: .utf8)
        let result = try XCTUnwrap(RepositoryProbe.read(path: root.path, github: false))
        XCTAssertEqual(result.changedFiles, 1)
        XCTAssertNotNil(result.repository)
        XCTAssertFalse(result.githubUnavailable)
        XCTAssertFalse(result.detached)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "one".write(to: nested.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: nested.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RepositoryProbe.read(path: root.path, github: false)?.changedFiles, 3)
    }
    func testCommandHasABoundedTimeout() throws {
        let start = Date()
        XCTAssertNil(RepositoryProbe.command("/bin/sleep", ["5"], directory: "/tmp", timeout: 0.05))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testLocalDiskUsageIncludesFilesButNotSymlinkTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgent-Size-Test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try XCTUnwrap(RepositoryProbe.diskUsage(path: root.path))
        try Data(repeating: 42, count: 65536).write(to: root.appendingPathComponent("sample.bin"))
        let after = try XCTUnwrap(RepositoryProbe.diskUsage(path: root.path))
        XCTAssertGreaterThanOrEqual(after, before + 65536)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("external"), withDestinationURL: URL(fileURLWithPath: "/Applications"))
        let linked = try XCTUnwrap(RepositoryProbe.diskUsage(path: root.path))
        XCTAssertLessThan(linked - after, 65536)
        XCTAssertNil(RepositoryProbe.diskUsage(path: root.appendingPathComponent("missing").path))
    }
}

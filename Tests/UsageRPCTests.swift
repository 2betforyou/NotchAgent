import XCTest
@testable import NotchAgent

/// Drives the real UsageRPC against scripted stand-ins for `codex app-server`.
@MainActor
final class UsageRPCTests: XCTestCase {
    private var directory: URL!
    override func setUp() async throws {
        AppLanguage.current = .korean
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentUsage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    private static let limits = #"{"id":3,"result":{"rateLimits":{"primary":{"usedPercent":40.0,"windowDurationMins":300},"secondary":{"usedPercent":10.0,"windowDurationMins":10080}}}}"#
    /// `replies` maps request id → JSON line; missing ids are never answered (offline/hung server).
    private func fakeCodex(initialize: String = #"{"id":1,"result":{}}"#, replies: [Int: String], exitImmediately: Bool = false) throws -> String {
        var script = "#!/bin/zsh -f\n"
        if exitImmediately { script += "exit 1\n" }
        script += "while IFS= read -r line; do\n  case $line in\n"
        script += "    *'\"method\":\"initialize\"'*) print -r -- \(ShellSafety.quote(initialize));;\n"
        for (id, reply) in replies.sorted(by: { $0.key < $1.key }) {
            script += "    *'\"id\":\(id)'*) print -r -- \(ShellSafety.quote(reply));;\n"
        }
        script += "  esac\ndone\n"
        let url = directory.appendingPathComponent("codex")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
    private func fetch(_ path: String, timeout: Duration = .seconds(5)) -> Result<UsageSnapshot, Error>? {
        var result: Result<UsageSnapshot, Error>?
        let rpc = UsageRPC()
        rpc.fetch(path: path, timeout: timeout) { result = $0 }
        let deadline = Date().addingTimeInterval(10)
        while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return result
    }
    private func message(_ result: Result<UsageSnapshot, Error>?) -> String? {
        guard case .failure(let error)? = result else { return nil }
        return error.localizedDescription
    }

    func testLoggedInReportsRemainingQuota() throws {
        let path = try fakeCodex(replies: [2: #"{"id":2,"result":{"account":{"planType":"plus"}}}"#, 3: Self.limits,
                                           4: #"{"id":4,"result":{"summary":{"lifetimeTokens":42}}}"#])
        guard case .success(let snapshot)? = fetch(path) else { return XCTFail("expected quota") }
        XCTAssertEqual(snapshot.windows.map(\.remaining), [60, 90])
        XCTAssertEqual(snapshot.plan, "plus")
        XCTAssertEqual(snapshot.lifetimeTokens, 42)
    }
    func testLoggedOutAsksToSignIn() throws {
        let path = try fakeCodex(replies: [2: #"{"id":2,"result":{}}"#, 3: #"{"id":3,"error":{"code":-32600,"message":"not logged in"}}"#])
        XCTAssertEqual(message(fetch(path)), "사용량을 읽을 수 없습니다. ChatGPT 계정으로 Codex CLI에 로그인하세요.")
    }
    func testOfflineTimesOutWithoutInventingNumbers() throws {
        let path = try fakeCodex(replies: [:])
        XCTAssertEqual(message(fetch(path, timeout: .milliseconds(600))), "사용량 응답 시간이 초과됐습니다. 네트워크와 Codex 로그인을 확인하세요.")
    }
    func testQuotaStillShownWhenOptionalTokenCountHangs() throws {
        let path = try fakeCodex(replies: [2: #"{"id":2,"result":{}}"#, 3: Self.limits])
        guard case .success(let snapshot)? = fetch(path, timeout: .milliseconds(600)) else { return XCTFail("expected quota") }
        XCTAssertNil(snapshot.lifetimeTokens)
    }
    func testAccountWithoutLimitsIsReportedNotZero() throws {
        let path = try fakeCodex(replies: [2: #"{"id":2,"result":{}}"#, 3: #"{"id":3,"result":{}}"#, 4: #"{"id":4,"result":{}}"#])
        XCTAssertEqual(message(fetch(path)), "이 계정에서 표시할 구독 한도를 제공하지 않습니다.")
    }
    func testCrashedServerIsReported() throws {
        let path = try fakeCodex(replies: [:], exitImmediately: true)
        XCTAssertNotNil(message(fetch(path)))
    }
    func testIncompatibleVersionIsReported() throws {
        let path = try fakeCodex(initialize: #"{"id":1,"error":{"code":-32601,"message":"unknown"}}"#, replies: [:])
        XCTAssertEqual(message(fetch(path)), "Codex 버전이 호환되지 않습니다. CLI를 업데이트하세요.")
    }
    func testMissingExecutableIsReported() {
        // The test host shares the app's defaults domain; never lose the user's real settings.
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "codexPath"), defaults.object(forKey: "usageEnabled"))
        defer {
            defaults.set(saved.0, forKey: "codexPath")
            defaults.set(saved.1, forKey: "usageEnabled")
        }
        defaults.set("/definitely/not/codex", forKey: "codexPath")
        let service = UsageService()
        service.enabled = true
        service.refresh()
        XCTAssertEqual(service.error, "Codex CLI를 찾을 수 없습니다. 설정에서 실행 파일을 지정하세요.")
        XCTAssertNil(service.snapshot)
    }
    /// Opt-in: TEST_RUNNER_NOTCHAGENT_LIVE_CODEX=1 bash Scripts/test.sh — uses the installed, signed-in CLI.
    func testLiveCodexWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NOTCHAGENT_LIVE_CODEX"] == "1")
        let path = try XCTUnwrap(ShellSafety.executable("codex"))
        let result = fetch(path, timeout: .seconds(20))
        switch result {
        case .success(let snapshot)?: XCTAssertFalse(snapshot.windows.isEmpty)
        case .failure(let error)?: XCTFail("live Codex: " + error.localizedDescription)
        case nil: XCTFail("no answer")
        }
    }
}

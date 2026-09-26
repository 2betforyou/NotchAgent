import AppKit
import Observation

@MainActor @Observable
final class UsageService {
    private(set) var snapshot: UsageSnapshot?
    private(set) var isLoading = false
    private(set) var error: String?
    var enabled = UserDefaults.standard.bool(forKey: "usageEnabled")
    @ObservationIgnored private var client: UsageRPC?
    @ObservationIgnored private var refreshTimer: Timer?

    func start() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if enabled { refresh() }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "usageEnabled")
        if value { refresh() }
        else { stopRequest(); snapshot = nil; error = nil }
    }
    func refresh() {
        guard enabled, !isLoading else { return }
        let override = UserDefaults.standard.string(forKey: "codexPath") ?? ""
        guard let path = ShellSafety.executable("codex", override: override) else {
            error = L("Codex CLI를 찾을 수 없습니다. 설정에서 실행 파일을 지정하세요.", "Codex CLI not found. Set its path in Settings.")
            return
        }
        isLoading = true
        error = nil
        let rpc = UsageRPC()
        client = rpc
        rpc.fetch(path: path) { [weak self] result in
            guard let self else { return }
            self.isLoading = false
            switch result {
            case .success(let snapshot): self.snapshot = snapshot; self.error = nil
            case .failure(let error):
                self.error = error.localizedDescription
                Log.usage.notice("codex usage refresh failed")
            }
            self.client = nil
        }
    }
    func stopRequest() { client?.stop(); client = nil; isLoading = false }
    func stop() { refreshTimer?.invalidate(); refreshTimer = nil; stopRequest() }
}

enum UsageFailure: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let text) = self { return text }; return nil }
}

/// One bounded stdio connection per refresh. It never starts an agent turn.
@MainActor
final class UsageRPC {
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = Data()
    private var completion: ((Result<UsageSnapshot, Error>) -> Void)?
    private var timeout: Task<Void, Never>?
    private var results: [Int: [String: Any]] = [:]
    private var received = Set<Int>()

    func fetch(path: String, timeout limit: Duration = .seconds(20), completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        self.completion = completion
        let process = Process(), input = Pipe(), output = Pipe()
        self.process = process; self.input = input; self.output = output
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        process.environment = ShellSafety.environment()
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = input; process.standardOutput = output
        // Never surface auth data, raw provider responses, or CLI diagnostics in logs.
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // At EOF the handler would otherwise fire continuously.
            if data.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                // Let output that arrived just before exit be consumed first.
                try? await Task.sleep(for: .milliseconds(300))
                Log.usage.error("codex app-server exited early (status \(status, privacy: .public))")
                self?.finish(.failure(UsageFailure.unavailable(L("Codex 연결이 종료됐습니다. CLI 로그인 상태를 확인하세요.", "The Codex connection closed. Check that the CLI is signed in."))))
            }
        }
        do {
            try process.run()
            send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "notch_agent", "title": "NotchAgent", "version": "0.1.0"]]])
            timeout = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // Optional lifetime-token support must not block valid quota data.
                if self.results[3] != nil { self.completeSnapshot() }
                else { self.finish(.failure(UsageFailure.unavailable(L("사용량 응답 시간이 초과됐습니다. 네트워크와 Codex 로그인을 확인하세요.", "Usage request timed out. Check your network and Codex sign-in.")))) }
            }
        } catch { finish(.failure(UsageFailure.unavailable(L("Codex를 실행할 수 없습니다. 설정의 실행 경로를 확인하세요.", "Could not run Codex. Check its path in Settings.")))) }
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message), let handle = input?.fileHandleForWriting else { return }
        do { try handle.write(contentsOf: data + Data([10])) }
        catch { finish(.failure(UsageFailure.unavailable(L("Codex 연결에 쓸 수 없습니다.", "Could not write to the Codex connection.")))) }
    }
    private func consume(_ data: Data) {
        guard completion != nil, !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 4_000_000 else {
            finish(.failure(UsageFailure.unavailable(L("Codex 응답이 예상 크기를 초과했습니다.", "The Codex response was larger than expected.")))); return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            if id == 1 {
                guard message["error"] == nil else {
                    finish(.failure(UsageFailure.unavailable(L("Codex 버전이 호환되지 않습니다. CLI를 업데이트하세요.", "This Codex version is not supported. Update the CLI.")))); return
                }
                send(["method": "initialized", "params": [:]])
                send(["id": 2, "method": "account/read", "params": ["refreshToken": false]])
                send(["id": 3, "method": "account/rateLimits/read", "params": [:]])
                send(["id": 4, "method": "account/usage/read", "params": [:]])
            } else if (2...4).contains(id) {
                received.insert(id)
                results[id] = message["result"] as? [String: Any]
                if id == 3 && message["error"] != nil {
                    finish(.failure(UsageFailure.unavailable(L("사용량을 읽을 수 없습니다. ChatGPT 계정으로 Codex CLI에 로그인하세요.", "Could not read usage. Sign in to the Codex CLI with a ChatGPT account.")))); return
                }
                if received == Set([2, 3, 4]) { completeSnapshot(); return }
            }
        }
    }
    private func completeSnapshot() {
        let account = results[2]?["account"] as? [String: Any]
        guard let limits = results[3], let snapshot = UsageSnapshot.parse(limits: limits, activity: results[4], plan: account?["planType"] as? String) else {
            finish(.failure(UsageFailure.unavailable(L("이 계정에서 표시할 구독 한도를 제공하지 않습니다.", "This account does not report subscription limits.")))); return
        }
        finish(.success(snapshot))
    }
    private func finish(_ result: Result<UsageSnapshot, Error>) {
        guard let completion else { return }
        self.completion = nil
        stop()
        completion(result)
    }
    func stop() {
        completion = nil
        timeout?.cancel(); timeout = nil
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        let child = process
        child?.terminationHandler = nil
        if child?.isRunning == true {
            child?.terminate()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                if let child, child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil; input = nil; output = nil
    }
}

import AppKit
import Observation

/// Claude Code reports subscription limits only to its status line command (`rate_limits` in the
/// status line JSON, Pro/Max plans, after the first response of a session). Claude sessions started
/// from NotchAgent use NotchAgent's binary as that command: it records the limits locally and then
/// runs the user's own status line command unchanged. No credentials are read.
enum ClaudeStatusLine {
    static let argument = "--claude-statusline"
    static let chainVariable = "NOTCHAGENT_CLAUDE_STATUSLINE_CHAIN"

    static var storeURL: URL {
        let base = ProcessInfo.processInfo.environment["NOTCHAGENT_SUPPORT_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NotchAgent")
        return base.appendingPathComponent("claude-rate-limits.json")
    }

    /// `--settings` value for `claude`, overriding the status line for this session only.
    static func settingsJSON(executable: String) -> String {
        let command = ShellSafety.quote(executable) + " " + argument
        let data = try! JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": command]])
        return String(decoding: data, as: UTF8.self)
    }

    /// The status line the user configured for this folder (local > project > user settings).
    static func userCommand(workspace: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let files = [workspace.appendingPathComponent(".claude/settings.local.json"),
                     workspace.appendingPathComponent(".claude/settings.json"),
                     home.appendingPathComponent(".claude/settings.json")]
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let line = json["statusLine"] as? [String: Any] else { continue }
            guard (line["type"] as? String ?? "command") == "command",
                  let command = line["command"] as? String, !command.isEmpty,
                  !command.contains(argument) else { return nil }
            return command
        }
        return nil
    }

    /// Entry point when Claude Code runs NotchAgent as its status line command.
    static func run() -> Int32 {
        // A user status line that exits without reading stdin must not kill us with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
        if let limits = json?["rate_limits"] as? [String: Any] { record(limits) }
        if let chain = ProcessInfo.processInfo.environment[chainVariable], !chain.isEmpty {
            return runChained(chain, input: input)
        }
        if let json { print(defaultLine(json)) }
        return 0
    }
    static func record(_ limits: [String: Any], now: Date = Date()) {
        let payload: [String: Any] = ["rate_limits": limits, "fetched_at": now.timeIntervalSince1970]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let url = storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
    private static func runChained(_ command: String, input: Data) -> Int32 {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardInput = pipe
        do { try process.run() } catch { return 1 }
        try? pipe.fileHandleForWriting.write(contentsOf: input)
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return process.terminationStatus
    }
    /// Shown when the user has no status line of their own.
    static func defaultLine(_ json: [String: Any], now: Date = Date()) -> String {
        let model = (json["model"] as? [String: Any])?["display_name"] as? String
        let usage = (json["rate_limits"] as? [String: Any])
            .flatMap { ClaudeUsage.parse(limits: $0, fetchedAt: now, now: now) }?
            .windows.map { L("\($0.title) \(Int($0.remaining))% 남음", "\($0.title) \(Int($0.remaining))% left") } ?? []
        return ([model].compactMap { $0 } + usage).joined(separator: " · ")
    }
}

enum ClaudeUsage {
    /// Windows whose reset time has passed are dropped: their old percentage no longer applies.
    static func parse(limits: [String: Any], fetchedAt: Date, now: Date = Date()) -> UsageSnapshot? {
        let windows = [("five_hour", "primary", 300), ("seven_day", "secondary", 10080)].compactMap { key, id, minutes -> UsageWindow? in
            guard let w = limits[key] as? [String: Any], let used = (w["used_percentage"] as? NSNumber)?.doubleValue,
                  used.isFinite else { return nil }
            let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            if let reset, reset <= now { return nil }
            return UsageWindow(id: id, usedPercent: used, durationMinutes: minutes, resetsAt: reset)
        }
        return windows.isEmpty ? nil : UsageSnapshot(windows: windows, plan: nil, lifetimeTokens: nil, fetchedAt: fetchedAt)
    }
    static func load(from url: URL = ClaudeStatusLine.storeURL, now: Date = Date()) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = json["rate_limits"] as? [String: Any],
              let fetched = (json["fetched_at"] as? NSNumber)?.doubleValue else { return nil }
        return parse(limits: limits, fetchedAt: Date(timeIntervalSince1970: fetched), now: now)
    }
}

@MainActor @Observable
final class ClaudeUsageService {
    private(set) var snapshot: UsageSnapshot?
    var enabled = UserDefaults.standard.bool(forKey: "claudeUsageEnabled")
    @ObservationIgnored private var timer: Timer?

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    static var refreshHelp: String {
        L("Claude 사용량은 직접 조회할 수 없어, NotchAgent에서 연 Claude 세션이 응답할 때마다 계정 전체 기준으로 갱신됩니다. 새로고침은 마지막으로 받은 값을 다시 읽습니다.",
          "Claude usage cannot be queried directly; it updates, account-wide, whenever a Claude session opened in NotchAgent responds. Refresh re-reads the latest value.")
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "claudeUsageEnabled")
        if !value { try? FileManager.default.removeItem(at: ClaudeStatusLine.storeURL) }
        reload()
    }
    func reload() {
        let next = enabled ? ClaudeUsage.load() : nil
        if next != snapshot { snapshot = next }
    }
}

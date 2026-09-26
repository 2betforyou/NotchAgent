import Foundation

enum IslandPhase: Equatable { case closed, preview, terminal }

enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case shell, codex, claude, gemini
    var id: String { rawValue }
    var name: String {
        switch self {
        case .shell: "Terminal"
        case .codex: "Codex"
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        }
    }
    var symbol: String { self == .shell ? "terminal" : "sparkle" }
}

enum ShellSafety {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.bun/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        env["PATH"] = ([env["PATH"] ?? ""] + paths).filter { !$0.isEmpty }.joined(separator: ":")
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "NotchAgent"
        env["TERM_PROGRAM_VERSION"] = "0.1.0"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }
    static func executable(_ name: String, override: String = "") -> String? {
        let fm = FileManager.default
        if !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? path : nil
        }
        if name == "shell" { return "/bin/zsh" }
        for dir in (environment()["PATH"] ?? "").split(separator: ":") {
            let path = String(dir) + "/" + name
            if fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

/// How long the pointer must rest on the notch before the preview opens.
enum HoverSpeed: String, CaseIterable, Identifiable {
    case instant, fast, standard, relaxed, slow
    static let `default` = HoverSpeed.standard
    var id: String { rawValue }
    var delay: TimeInterval {
        switch self {
        case .instant: 0.05
        case .fast: 0.12
        case .standard: 0.22
        case .relaxed: 0.4
        case .slow: 0.7
        }
    }
    var name: String {
        switch self {
        case .instant: "즉시"
        case .fast: "빠르게"
        case .standard: "기본"
        case .relaxed: "여유 있게"
        case .slow: "느리게"
        }
    }
    var label: String { name + " · " + (delay * 1000).formatted(.number.precision(.fractionLength(0))) + "ms" }
}

enum UsageAge {
    static func label(since date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "방금 전" }
        if minutes < 60 { return "\(minutes)분 전" }
        if minutes < 1440 { return "\(minutes / 60)시간 전" }
        return "\(minutes / 1440)일 전"
    }
}

enum ProcessCleanup {
    /// SwiftTerm reports the raw waitpid status; users expect the shell's `$?` value.
    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }
    static func groups(shell: pid_t, foreground: pid_t, excluding own: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        for group in [foreground, shell] where group > 1 && group != own && !result.contains(group) { result.append(group) }
        return result
    }
    static func isAlive(group: pid_t) -> Bool { kill(-group, 0) == 0 || errno == EPERM }
    /// Waits up to `grace` for the groups to exit, then SIGKILLs survivors and reaps the shells.
    static func finish(groups: [pid_t], shells: [pid_t], grace: TimeInterval) {
        let deadline = Date().addingTimeInterval(grace)
        var status: Int32 = 0
        while Date() < deadline, groups.contains(where: isAlive(group:)) {
            for shell in shells where shell > 0 { _ = waitpid(shell, &status, WNOHANG) }
            usleep(20_000)
        }
        for group in groups where isAlive(group: group) { kill(-group, SIGKILL) }
        for shell in shells where shell > 0 {
            for _ in 0..<50 where waitpid(shell, &status, WNOHANG) == 0 { usleep(10_000) }
        }
    }
}

struct UsageWindow: Equatable, Identifiable {
    let id: String
    let usedPercent: Double
    let durationMinutes: Int?
    let resetsAt: Date?
    var remaining: Double { min(100, max(0, 100 - usedPercent)) }
    var title: String {
        guard let minutes = durationMinutes else { return id == "primary" ? "현재 한도" : "추가 한도" }
        if minutes == 10080 { return "주간 한도" }
        if minutes % 60 == 0 { return "\(minutes / 60)시간 한도" }
        return "\(minutes)분 한도"
    }
    func resetLabel(now: Date = Date()) -> String {
        guard let reset = resetsAt else { return "초기화 시간 없음" }
        let minutes = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "갱신 대기" }
        if minutes >= 1440 { return "\(minutes / 1440)일 \((minutes % 1440) / 60)시간 후 초기화" }
        if minutes >= 60 { return "\(minutes / 60)시간 \(minutes % 60)분 후 초기화" }
        return "\(minutes)분 후 초기화"
    }
}

struct UsageSnapshot: Equatable {
    var windows: [UsageWindow]
    var plan: String?
    var lifetimeTokens: Int64?
    var fetchedAt: Date
    static func parse(limits: [String: Any], activity: [String: Any]?, plan: String?, now: Date = Date()) -> UsageSnapshot? {
        let buckets = limits["rateLimitsByLimitId"] as? [String: Any]
        let bucket: [String: Any]?
        if let codex = buckets?["codex"] as? [String: Any] { bucket = codex }
        else { bucket = limits["rateLimits"] as? [String: Any] }
        guard let bucket else { return nil }
        let windows = ["primary", "secondary"].compactMap { id -> UsageWindow? in
            guard let w = bucket[id] as? [String: Any], let used = w["usedPercent"] as? Double,
                  used.isFinite else { return nil }
            let reset = (w["resetsAt"] as? Double).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
            let duration = (w["windowDurationMins"] as? NSNumber)?.intValue
            return UsageWindow(id: id, usedPercent: used, durationMinutes: duration.flatMap { $0 > 0 ? $0 : nil }, resetsAt: reset)
        }
        guard !windows.isEmpty else { return nil }
        let summary = activity?["summary"] as? [String: Any]
        return UsageSnapshot(windows: windows, plan: bucket["planType"] as? String ?? plan,
                             lifetimeTokens: (summary?["lifetimeTokens"] as? NSNumber)?.int64Value, fetchedAt: now)
    }
    var isStale: Bool { Date().timeIntervalSince(fetchedAt) > 600 }
}

struct SavedWorkspace: Codable, Identifiable, Equatable {
    var id: String { path }
    var path: String
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var exists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

/// The user's managed set of work folders, in the order they added them.
enum Workspaces {
    static func normalize(_ path: String) -> String {
        let p = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
    }
    /// First launch after the upgrade: keep the folders used before, active one first.
    static func migrate(saved: [SavedWorkspace]?, recent: [SavedWorkspace], active: String) -> [SavedWorkspace] {
        var result: [SavedWorkspace] = []
        for item in (saved ?? [SavedWorkspace(path: active)] + recent) {
            let path = normalize(item.path)
            if !result.contains(where: { $0.path == path }) { result.append(SavedWorkspace(path: path)) }
        }
        if !result.contains(where: { $0.path == normalize(active) }) { result.insert(SavedWorkspace(path: normalize(active)), at: 0) }
        return result
    }
    /// Chip labels; folders with the same name get their parent folder appended.
    static func labels(_ items: [SavedWorkspace]) -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            let twins = items.filter { $0.name == item.name }.count > 1
            let parent = URL(fileURLWithPath: item.path).deletingLastPathComponent().lastPathComponent
            result[item.path] = twins && !parent.isEmpty ? "\(item.name) — \(parent)" : item.name
        }
        return result
    }
    /// Current git branch (or short commit) without spawning git; supports linked worktrees.
    static func gitBranch(at path: String) -> String? {
        var gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: gitDir, encoding: .utf8), pointer.hasPrefix("gitdir:") {
            let target = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = URL(fileURLWithPath: target, relativeTo: URL(fileURLWithPath: path, isDirectory: true)).standardizedFileURL
        }
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !head.isEmpty else { return nil }
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst("ref: refs/heads/".count)) }
        return String(head.prefix(7))
    }
}

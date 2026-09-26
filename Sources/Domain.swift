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
        case .instant: L("즉시", "Instant")
        case .fast: L("빠르게", "Fast")
        case .standard: L("기본", "Default")
        case .relaxed: L("여유 있게", "Relaxed")
        case .slow: L("느리게", "Slow")
        }
    }
    var label: String { name + " · " + (delay * 1000).formatted(.number.precision(.fractionLength(0))) + "ms" }
}

enum AttentionReason: Equatable {
    case finished, bell, exited
    /// Which one to show when several sessions want attention: a question beats a result.
    var priority: Int {
        switch self {
        case .bell: 3
        case .finished: 2
        case .exited: 1
        }
    }
    var message: String {
        switch self {
        case .finished: L("작업을 마쳤어요", "finished")
        case .bell: L("확인이 필요해요", "needs you")
        case .exited: L("세션이 종료됐어요", "session ended")
        }
    }
}

enum Reorder {
    /// Moves the element with `id` to where `target` is, the way a dragged tab settles:
    /// dragging right lands after the target, dragging left lands before it.
    static func move<T, ID: Equatable>(_ items: inout [T], id: ID, onto target: ID, key: (T) -> ID) {
        guard let from = items.firstIndex(where: { key($0) == id }),
              let to = items.firstIndex(where: { key($0) == target }), from != to else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
    }
}

struct SavedSession: Codable, Equatable {
    let kind: AgentKind
    let path: String
}

enum SessionRestore {
    /// Flags that reopen the most recent conversation in the working directory.
    static func resumeArguments(for kind: AgentKind) -> [String] {
        switch kind {
        case .claude: ["--continue"]
        case .codex: ["resume", "--last"]
        case .shell, .gemini: []
        }
    }
    /// Starts an interactive session that begins with `prompt`. A leading space keeps a prompt
    /// such as "-v 옵션 설명" from being parsed as a flag.
    static func initialPromptArguments(for kind: AgentKind, prompt: String) -> [String] {
        let text = prompt.hasPrefix("-") ? " " + prompt : prompt
        switch kind {
        case .claude, .codex: return [text]
        case .gemini: return ["--prompt-interactive", text]
        case .shell: return []
        }
    }
    /// Both CLIs only continue a folder's *latest* conversation, so only the first tab per
    /// agent and folder resumes; duplicates start fresh instead of opening the same chat twice.
    static func plan(_ saved: [SavedSession]) -> [(session: SavedSession, resume: Bool)] {
        var seen = Set<String>()
        return saved.map { item in
            let key = item.kind.rawValue + "\u{0}" + Workspaces.normalize(item.path)
            let first = seen.insert(key).inserted
            return (item, first && !resumeArguments(for: item.kind).isEmpty)
        }
    }
}

/// The single thing the closed notch shows on the right, most important first.
enum NotchStatus: Equatable {
    case attention(AttentionReason)
    case working(since: Date)
    case lowQuota(AgentKind, remaining: Double)
    case sessions(Int)
    case empty

    static let lowQuotaThreshold: Double = 20

    static func resolve(attention: [AttentionReason], workingSince: [Date],
                        quotas: [(agent: AgentKind, remaining: Double)], running: Int) -> NotchStatus {
        if let top = attention.max(by: { $0.priority < $1.priority }) { return .attention(top) }
        if let oldest = workingSince.min() { return .working(since: oldest) }
        if let low = quotas.filter({ $0.remaining <= lowQuotaThreshold }).min(by: { $0.remaining < $1.remaining }) {
            return .lowQuota(low.agent, remaining: low.remaining)
        }
        return running > 0 ? .sessions(running) : .empty
    }
    /// "2:31" under an hour, "1h04" after that; fits the narrow notch wing.
    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 3600 { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        return String(format: "%dh%02d", seconds / 3600, (seconds % 3600) / 60)
    }
}

struct NotchBanner: Equatable {
    let sessionID: UUID
    let kind: AgentKind
    let reason: AttentionReason
    let folder: String
    let shownAt: Date
}

/// Infers "working" and "just finished" from output timing. Agents stream spinners and text
/// while they work and go quiet when they wait for the user.
struct ActivityTracker {
    static let idleAfter: TimeInterval = 2.5   // silence that means the program stopped
    static let minimumWork: TimeInterval = 4   // shorter bursts (echo, banners) are not "work"
    private(set) var lastOutput: Date?
    private(set) var busySince: Date?

    mutating func output(at date: Date) {
        if let lastOutput, date.timeIntervalSince(lastOutput) < Self.idleAfter {} else { busySince = date }
        lastOutput = date
    }
    func isWorking(now: Date) -> Bool {
        lastOutput.map { now.timeIntervalSince($0) < Self.idleAfter } ?? false
    }
    /// True exactly once when a long enough burst of output has ended.
    mutating func finishedWork(now: Date) -> Bool {
        guard let lastOutput, let start = busySince, now.timeIntervalSince(lastOutput) >= Self.idleAfter else { return false }
        busySince = nil
        return lastOutput.timeIntervalSince(start) >= Self.minimumWork
    }
}

enum UsageAge {
    static func label(since date: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return L("방금 전", "just now") }
        if minutes < 60 { return L("\(minutes)분 전", "\(minutes)m ago") }
        if minutes < 1440 { return L("\(minutes / 60)시간 전", "\(minutes / 60)h ago") }
        return L("\(minutes / 1440)일 전", "\(minutes / 1440)d ago")
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
        guard let minutes = durationMinutes else { return id == "primary" ? L("현재 한도", "Current limit") : L("추가 한도", "Extra limit") }
        if minutes == 10080 { return L("주간 한도", "Weekly") }
        if minutes % 60 == 0 { return L("\(minutes / 60)시간 한도", "\(minutes / 60)-hour") }
        return L("\(minutes)분 한도", "\(minutes)-minute")
    }
    func resetLabel(now: Date = Date()) -> String {
        guard let reset = resetsAt else { return L("초기화 시간 없음", "No reset time") }
        let minutes = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes == 0 { return L("갱신 대기", "Resetting") }
        if minutes >= 1440 { return L("\(minutes / 1440)일 \((minutes % 1440) / 60)시간 후 초기화", "Resets in \(minutes / 1440)d \((minutes % 1440) / 60)h") }
        if minutes >= 60 { return L("\(minutes / 60)시간 \(minutes % 60)분 후 초기화", "Resets in \(minutes / 60)h \(minutes % 60)m") }
        return L("\(minutes)분 후 초기화", "Resets in \(minutes)m")
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

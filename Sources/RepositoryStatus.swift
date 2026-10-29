import AppKit
import Observation
import SwiftUI

struct GitHubRepository: Equatable, Sendable {
    let owner: String
    let name: String
    var slug: String { owner + "/" + name }
    var url: URL { URL(string: "https://github.com/" + slug)! }
    static func parse(_ remote: String) -> Self? {
        let text = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if text.hasPrefix("git@github.com:") { path = String(text.dropFirst("git@github.com:".count)) }
        else {
            guard let url = URL(string: text), url.host?.lowercased() == "github.com",
                  ["https", "ssh"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            path = String(url.path.drop(while: { $0 == "/" }))
        }
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[1].hasSuffix(".git") { parts[1].removeLast(4) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return Self(owner: parts[0], name: parts[1])
    }
    func safeURL(_ text: String) -> URL? {
        guard let candidate = URL(string: text), candidate.scheme == "https", candidate.host == "github.com",
              candidate.user == nil, candidate.password == nil,
              candidate.path.hasPrefix("/" + slug + "/") else { return nil }
        return candidate
    }
}

enum RepositoryChecks: String, Sendable {
    case passed, failed, pending, none
    var title: String {
        switch self {
        case .passed: L("검사 통과", "Checks passed")
        case .failed: L("검사 실패", "Checks failed")
        case .pending: L("검사 중", "Checks running")
        case .none: L("검사 없음", "No checks")
        }
    }
    static func resolve(_ checks: [[String: Any]]) -> Self {
        guard !checks.isEmpty else { return .none }
        let states = checks.map { ($0["conclusion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ($0["state"] as? String) ?? ($0["status"] as? String) ?? "UNKNOWN" }.map { $0.uppercased() }
        if states.contains(where: { ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"].contains($0) }) { return .failed }
        if states.contains(where: { !["SUCCESS", "NEUTRAL", "SKIPPED"].contains($0) }) { return .pending }
        return .passed
    }
}

struct RepositoryPullRequest: Equatable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let draft: Bool
    let review: String
    let checks: RepositoryChecks
    static func parse(_ data: Data, repository: GitHubRepository) -> Self? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let item = items.first, let number = item["number"] as? Int,
              let url = repository.safeURL(item["url"] as? String ?? "") else { return nil }
        return Self(number: number, title: item["title"] as? String ?? "PR #\(number)", url: url,
                    draft: item["isDraft"] as? Bool ?? false, review: item["reviewDecision"] as? String ?? "",
                    checks: RepositoryChecks.resolve(item["statusCheckRollup"] as? [[String: Any]] ?? []))
    }
    var label: String {
        let state = draft ? L("초안", "Draft") : review == "APPROVED" ? L("승인됨", "Approved") : review == "CHANGES_REQUESTED" ? L("수정 요청", "Changes requested") : L("리뷰 대기", "Awaiting review")
        return "PR #\(number) · " + state
    }
}

struct RepositorySnapshot: Equatable, Sendable {
    let root: String
    let branch: String
    let detached: Bool
    let changedFiles: Int
    let repository: GitHubRepository?
    var pullRequest: RepositoryPullRequest?
    var githubUnavailable = false
    var branchChecks: RepositoryChecks?
    var checksURL: URL?
    var sizeBytes: Int64?
    var sizeCalculatedAt: Date?
}

enum RepositoryProbe {
    static func diskUsage(path: String) -> Int64? {
        guard let text = command("/usr/bin/du", ["-sk", path], directory: path, timeout: 8),
              let first = text.split(whereSeparator: { $0.isWhitespace }).first,
              let kilobytes = Int64(first), kilobytes >= 0 else { return nil }
        let result = kilobytes.multipliedReportingOverflow(by: 1024)
        return result.overflow ? nil : result.partialValue
    }
    /// Counts porcelain -z records, treating a rename's two paths as one file.
    static func changedFiles(_ output: String) -> Int {
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true)
        var index = 0, count = 0
        while index < entries.count {
            let status = entries[index].prefix(2)
            count += 1; index += status.contains("R") || status.contains("C") ? 2 : 1
        }
        return count
    }
    static func read(path: String, github: Bool) -> RepositorySnapshot? {
        guard let git = ShellSafety.executable("git"),
              let root = command(git, ["-C", path, "rev-parse", "--show-toplevel"], directory: path),
              !root.isEmpty else { return nil }
        let branch = command(git, ["-C", path, "symbolic-ref", "--quiet", "--short", "HEAD"], directory: path)
        let hash = branch == nil ? command(git, ["-C", path, "rev-parse", "--short", "HEAD"], directory: path) : nil
        guard let status = command(git, ["-C", path, "status", "--porcelain=v1", "-z", "--untracked-files=all"], directory: path) else { return nil }
        let remote = command(git, ["-C", path, "remote", "get-url", "origin"], directory: path) ?? ""
        var result = RepositorySnapshot(root: root, branch: branch ?? hash ?? "HEAD", detached: branch == nil,
                                        changedFiles: changedFiles(status), repository: GitHubRepository.parse(remote))
        if github, let repository = result.repository, let branch {
            guard let gh = ShellSafety.executable("gh"),
                  let output = command(gh, ["pr", "list", "--repo", repository.slug, "--head", branch, "--state", "open", "--limit", "20",
                                            "--json", "number,title,url,isDraft,reviewDecision,statusCheckRollup,headRepositoryOwner"], directory: path, timeout: 12),
                  let items = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]] else {
                result.githubUnavailable = true
                return result
            }
            let matching = items.filter { (($0["headRepositoryOwner"] as? [String: Any])?["login"] as? String)?.lowercased() == repository.owner.lowercased() }
            if !matching.isEmpty, let data = try? JSONSerialization.data(withJSONObject: matching) {
                result.pullRequest = RepositoryPullRequest.parse(data, repository: repository)
                result.githubUnavailable = result.pullRequest == nil
            }
            if result.pullRequest == nil,
               let head = command(git, ["-C", path, "rev-parse", "HEAD"], directory: path),
               let runs = command(gh, ["run", "list", "--repo", repository.slug, "--branch", branch, "--commit", head, "--limit", "1", "--json", "status,conclusion,url"], directory: path, timeout: 12),
               let items = try? JSONSerialization.jsonObject(with: Data(runs.utf8)) as? [[String: Any]] {
                result.branchChecks = RepositoryChecks.resolve(items)
                result.checksURL = items.first.flatMap { repository.safeURL($0["url"] as? String ?? "") }
            }
        }
        return result
    }
    /// Temp-file output prevents pipe deadlocks; all subprocess work stays off the main thread.
    static func command(_ executable: String, _ arguments: [String], directory: String, timeout: TimeInterval = 4) -> String? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgent-Repo-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: url.path, contents: nil), let output = try? FileHandle(forWritingTo: url) else { return nil }
        defer { try? output.close(); try? FileManager.default.removeItem(at: url) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ShellSafety.environment().merging(["GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0", "GH_PROMPT_DISABLED": "1", "GH_HOST": "github.com", "GH_PAGER": "cat"]) { $1 }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(0.3)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return nil
        }
        guard process.terminationStatus == 0, let data = try? Data(contentsOf: url), data.count <= 2_000_000 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}

@MainActor @Observable
final class RepositoryStatusService {
    private(set) var snapshot: RepositorySnapshot?
    private(set) var isLoading = false
    private(set) var path: String?
    var githubEnabled: Bool {
        didSet { defaults.set(githubEnabled, forKey: "repositoryGitHubEnabled") }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let load: @Sendable (String, Bool) -> RepositorySnapshot?
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var sizeCache: [String: (bytes: Int64, at: Date)] = [:]
    init(defaults: UserDefaults = .standard, snapshot: RepositorySnapshot? = nil,
         load: @escaping @Sendable (String, Bool) -> RepositorySnapshot? = { RepositoryProbe.read(path: $0, github: $1) }) {
        self.defaults = defaults
        self.load = load
        self.snapshot = snapshot
        self.path = snapshot?.root
        githubEnabled = defaults.bool(forKey: "repositoryGitHubEnabled")
    }
    func refresh(path: String, forceSize: Bool = false) async {
        let token = UUID(); request = token
        if self.path != path { snapshot = nil }
        self.path = path; isLoading = true
        let github = githubEnabled
        let load = self.load
        let next = await Task.detached(priority: .utility) { load(path, github) }.value
        guard request == token else { return }
        isLoading = false
        guard !Task.isCancelled else { return }
        snapshot = next
        guard var result = next else { return }
        if !forceSize, let cached = sizeCache[result.root], Date().timeIntervalSince(cached.at) < 300 {
            result.sizeBytes = cached.bytes; result.sizeCalculatedAt = cached.at
        } else {
            let root = result.root
            let bytes = await Task.detached(priority: .utility) { RepositoryProbe.diskUsage(path: root) }.value
            guard request == token, !Task.isCancelled else { return }
            if let bytes {
                let now = Date()
                sizeCache[root] = (bytes, now)
                result.sizeBytes = bytes; result.sizeCalculatedAt = now
            }
        }
        snapshot = result
    }
}

struct RepositoryStatusRow: View {
    @Bindable var service: RepositoryStatusService
    let path: String
    @State private var showingChanges = false
    @State private var showingInfo = false
    var body: some View {
        Group {
            if let snapshot = service.snapshot, service.path == path {
                HStack(spacing: 12) {
                    Label(snapshot.branch + (snapshot.detached ? " · detached" : ""), systemImage: "arrow.triangle.branch")
                        .lineLimit(1).truncationMode(.middle).help(snapshot.root)
                    Button { showingChanges.toggle() } label: {
                        Text(snapshot.changedFiles == 0 ? L("변경 없음", "Clean") : L("변경 \(snapshot.changedFiles)개", "\(snapshot.changedFiles) changed"))
                            .foregroundStyle(snapshot.changedFiles == 0 ? Palette.muted : Palette.mint)
                    }.buttonStyle(.plain)
                    .popover(isPresented: $showingChanges) { RepositoryChangesView(path: snapshot.root) }
                    Button { showingInfo.toggle() } label: {
                        Text(snapshot.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? L("용량 —", "Size —"))
                            .foregroundStyle(Palette.muted).fixedSize()
                    }.buttonStyle(.plain)
                    .help(L("로컬 폴더의 디스크 사용량 · 클릭하여 상세 보기", "Local folder disk usage · click for details"))
                    .popover(isPresented: $showingInfo) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("로컬 프로젝트 용량", "Local project size")).font(.headline)
                            Text(snapshot.root).textSelection(.enabled)
                            Text(L(".git, 의존성, 빌드 결과물을 포함한 디스크 사용량입니다. 외부 심볼릭 링크의 대상은 따라가지 않습니다.", "Disk usage includes .git, dependencies, and build output. External symbolic-link targets aren't followed."))
                            if let at = snapshot.sizeCalculatedAt {
                                Text(L("계산 시각: ", "Calculated: ") + at.formatted(date: .omitted, time: .standard))
                            } else {
                                Text(L("계산 중이거나 용량을 읽지 못했습니다.", "Calculating, or unable to read folder size."))
                            }
                            Button(L("용량 다시 계산", "Recalculate size")) { Task { await service.refresh(path: path, forceSize: true) } }
                        }.font(.caption).padding(16).frame(width: 300)
                    }
                    if let repository = snapshot.repository {
                        Rectangle().fill(Palette.line).frame(width: 1, height: 12)
                        if !service.githubEnabled {
                            Button(L("PR·검사 연결", "Connect PR & checks")) { service.githubEnabled = true }
                                .buttonStyle(.plain).foregroundStyle(Palette.mint)
                                .help(L("GitHub CLI(gh)의 기존 로그인으로 조회합니다.", "Uses your existing GitHub CLI (gh) sign-in."))
                        } else if snapshot.githubUnavailable {
                            Text(L("GitHub 조회 실패", "GitHub unavailable")).foregroundStyle(.orange)
                                .help(L("gh 설치·로그인과 네트워크를 확인한 뒤 새로고침하세요. gh auth login", "Check gh installation, sign-in, and network, then refresh. gh auth login"))
                        } else if let pr = snapshot.pullRequest {
                            Link(pr.label, destination: pr.url).lineLimit(1).help(pr.title)
                            Link(destination: pr.url.appendingPathComponent("checks")) {
                                Label(pr.checks.title, systemImage: pr.checks == .passed ? "checkmark.circle" : pr.checks == .failed ? "xmark.circle" : "clock")
                                    .foregroundStyle(pr.checks == .failed ? Palette.low : pr.checks == .passed ? Palette.mint : Palette.muted)
                            }
                        } else {
                            Text(snapshot.detached ? L("분리된 HEAD", "Detached HEAD") : L("열린 PR 없음", "No open PR")).foregroundStyle(Palette.muted)
                            if let checks = snapshot.branchChecks, let url = snapshot.checksURL {
                                Link(checks.title, destination: url)
                                    .foregroundStyle(checks == .failed ? Palette.low : checks == .passed ? Palette.mint : Palette.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        Link(destination: repository.url) { Label("GitHub", systemImage: "arrow.up.right") }
                    } else { Spacer(minLength: 0) }
                    RefreshButton(help: L("저장소 상태 새로고침", "Refresh repository status")) {
                        Task { await service.refresh(path: path, forceSize: true) }
                    }.disabled(service.isLoading)
                }
                .font(.caption).padding(.horizontal, 12).padding(.vertical, 10)
                .background(Palette.surface).clipShape(.rect(cornerRadius: 9))
            }
        }
    }
}

private struct RepositoryChangesView: View {
    let path: String
    @State private var text: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("변경 파일", "Changed files")).font(.headline)
            ScrollView {
                Text(text ?? L("확인 중…", "Loading…")).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 220)
        }.padding(16).frame(width: 360)
        .task {
            text = await Task.detached(priority: .utility) {
                guard let git = ShellSafety.executable("git") else { return L("git을 찾지 못했습니다.", "git not found.") }
                return RepositoryProbe.command(git, ["-C", path, "status", "--short", "--untracked-files=all"], directory: path)
                    .map { $0.isEmpty ? L("변경 없음", "No changes") : $0 }
                    ?? L("변경 목록을 읽지 못했습니다.", "Could not read changes.")
            }.value
        }
    }
}

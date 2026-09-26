import AppKit
import Observation

@MainActor @Observable
final class AppModel {
    var phase: IslandPhase = .closed
    var sessions: [TerminalSession] = []
    var selectedID: UUID?
    var lastError: String?
    var compactWidth: CGFloat = 200
    var notchHeight: CGFloat = 32
    var panelWidth: CGFloat = 900
    var panelHeight: CGFloat = 570
    var hasPhysicalNotch = true
    var displayName = ""
    var workspaces: [SavedWorkspace] = []
    var workspacePath: String
    var hoverEnabled: Bool { didSet { defaults.set(hoverEnabled, forKey: "hoverEnabled") } }
    var hoverSpeed: HoverSpeed { didSet { defaults.set(hoverSpeed.rawValue, forKey: "hoverSpeed") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var language: AppLanguage {
        didSet { AppLanguage.current = language; defaults.set(language.rawValue, forKey: "language"); languageChanged?() }
    }
    /// Rebuilds AppKit menus and window titles, which SwiftUI does not re-render.
    @ObservationIgnored var languageChanged: (() -> Void)?
    var accent: Accent { didSet { Accent.current = accent; defaults.set(accent.rawValue, forKey: "accent") } }
    var terminalTheme: TerminalTheme { didSet { defaults.set(terminalTheme.rawValue, forKey: "terminalTheme") } }
    var terminalFont: String { didSet { defaults.set(terminalFont, forKey: "terminalFont") } }
    var appearance: TerminalAppearance { TerminalAppearance(theme: terminalTheme, font: terminalFont, size: fontSize, accent: accent) }
    var preferredDisplay: String { didSet { defaults.set(preferredDisplay, forKey: "display") } }
    var hotkey: Hotkey {
        didSet { if let data = try? JSONEncoder().encode(hotkey) { defaults.set(data, forKey: "hotkey") } }
    }
    /// Registers a new global shortcut; false when another app already owns it.
    @ObservationIgnored var applyHotkey: ((Hotkey) -> Bool)?
    /// Lets the shortcut recorder capture the current combination.
    @ObservationIgnored var suspendHotkey: ((Bool) -> Void)?
    /// The preview's quick prompt has keyboard focus; the preview stays open meanwhile.
    var quickPromptActive = false
    var quickAgent: AgentKind { didSet { defaults.set(quickAgent.rawValue, forKey: "quickAgent") } }
    @ObservationIgnored var beginQuickPrompt: (() -> Void)?
    /// The Terminal/Codex/Claude/Gemini buttons beside the tabs can be folded behind one button.
    var showsNewSessionButtons: Bool { didSet { defaults.set(showsNewSessionButtons, forKey: "showsNewSessionButtons") } }
    var notifyEnabled: Bool { didSet { defaults.set(notifyEnabled, forKey: "notifyEnabled") } }
    var restoreSessions: Bool {
        didSet { defaults.set(restoreSessions, forKey: "restoreSessions"); saveSessions() }
    }
    /// Dynamic-Island style notice under the closed notch.
    var banner: NotchBanner?
    let usage = UsageService()
    let claudeUsage = ClaudeUsageService()
    @ObservationIgnored var showTerminal: (() -> Void)?
    @ObservationIgnored var collapse: (() -> Void)?
    @ObservationIgnored var showSettings: (() -> Void)?
    /// Runs a modal alert where the user can see it (the island sits above modal windows).
    @ObservationIgnored var runAlert: ((NSAlert) -> NSApplication.ModalResponse)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        workspacePath = d.string(forKey: "workspace") ?? FileManager.default.homeDirectoryForCurrentUser.path
        hoverEnabled = d.object(forKey: "hoverEnabled") as? Bool ?? true
        hoverSpeed = d.string(forKey: "hoverSpeed").flatMap(HoverSpeed.init(rawValue:)) ?? .default
        fontSize = max(11, min(20, d.object(forKey: "fontSize") as? Double ?? 13))
        language = d.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? .system
        accent = d.string(forKey: "accent").flatMap(Accent.init(rawValue:)) ?? .mint
        terminalTheme = d.string(forKey: "terminalTheme").flatMap(TerminalTheme.init(rawValue:)) ?? .standard
        terminalFont = d.string(forKey: "terminalFont") ?? TerminalFont.system
        preferredDisplay = d.string(forKey: "display") ?? "builtin"
        notifyEnabled = d.object(forKey: "notifyEnabled") as? Bool ?? true
        showsNewSessionButtons = d.object(forKey: "showsNewSessionButtons") as? Bool ?? true
        quickAgent = d.string(forKey: "quickAgent").flatMap(AgentKind.init(rawValue:)).flatMap { $0 == .shell ? nil : $0 } ?? .claude
        hotkey = d.data(forKey: "hotkey").flatMap { try? JSONDecoder().decode(Hotkey.self, from: $0) } ?? .default
        restoreSessions = d.object(forKey: "restoreSessions") as? Bool ?? true
        let decode = { (key: String) in d.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedWorkspace].self, from: $0) } }
        workspacePath = Workspaces.normalize(workspacePath)
        workspaces = Workspaces.migrate(saved: decode("workspaces"), recent: decode("recentWorkspaces") ?? [], active: workspacePath)
        Accent.current = accent
        AppLanguage.current = language
    }
    /// Measured by the view; the island and its hover area use the same height.
    var previewContentHeight: CGFloat = 0
    var previewHeight: CGFloat {
        previewContentHeight > 0 ? previewContentHeight : 310 + notchHeight + (claudeUsage.enabled ? 90 : 0)
    }
    var attentionCount: Int { sessions.filter { $0.attention != nil }.count }
    /// The most important unseen event among a folder's sessions.
    func attention(in path: String) -> AttentionReason? {
        sessions.filter { Workspaces.normalize($0.initialDirectory.path) == path }
            .compactMap(\.attention).max { $0.priority < $1.priority }
    }
    /// What the closed notch shows on the right: attention, elapsed work, a low quota, or the count.
    var notchStatus: NotchStatus {
        var quotas: [(agent: AgentKind, remaining: Double)] = []
        if usage.enabled, let snapshot = usage.snapshot { quotas += snapshot.windows.map { (.codex, $0.remaining) } }
        if claudeUsage.enabled, let snapshot = claudeUsage.snapshot { quotas += snapshot.windows.map { (.claude, $0.remaining) } }
        return NotchStatus.resolve(attention: sessions.compactMap(\.attention),
                                   workingSince: sessions.compactMap(\.workingSince),
                                   quotas: quotas, running: runningCount)
    }
    /// Preview text for the *current* folder, so switching folders updates it.
    var previewHeadline: String {
        let here = runningCount(in: workspacePath)
        return here == 0 ? L("작업은 가까이. 화면은 여유롭게.", "Work close by. Screen kept clear.")
                         : L("\(here)개의 세션이 열려 있어요.", "\(here) session(s) open.")
    }
    var previewSubtitle: String {
        if let session = selected, visibleSessions.contains(where: { $0.id == session.id }) {
            return session.kind.name + " · " + session.initialDirectory.lastPathComponent
        }
        let elsewhere = runningCount - runningCount(in: workspacePath)
        return elsewhere > 0 ? L("다른 폴더에서 \(elsewhere)개 실행 중", "\(elsewhere) running in other folders")
                             : L("터미널과 에이전트를 노치에서 바로.", "Terminal and agents, right from the notch.")
    }
    var closedWidth: CGFloat { banner == nil ? compactWidth : max(compactWidth, 400) }
    var closedHeight: CGFloat { banner == nil ? notchHeight : notchHeight + 34 }
    static let bannerDuration: TimeInterval = 4.5
    /// Called once a second: updates working state and raises notices for unseen sessions.
    func tickActivity(now: Date = Date()) {
        for session in sessions {
            let visible = phase == .terminal && session.id == selectedID
            guard let reason = session.tick(now: now, visible: visible) else { continue }
            if notifyEnabled, phase == .closed {
                banner = NotchBanner(sessionID: session.id, kind: session.kind, reason: reason,
                                     folder: session.initialDirectory.lastPathComponent, shownAt: now)
            }
        }
        if let banner, phase != .closed || now.timeIntervalSince(banner.shownAt) > Self.bannerDuration { self.banner = nil }
    }
    func openBanner() {
        guard let banner, let session = sessions.first(where: { $0.id == banner.sessionID }) else { self.banner = nil; return }
        self.banner = nil
        activateWorkspace(Workspaces.normalize(session.initialDirectory.path))
        selectedID = session.id
        showTerminal?()
    }
    var selected: TerminalSession? { sessions.first { $0.id == selectedID } }
    var runningCount: Int { sessions.filter(\.isRunning).count }
    var workspaceName: String { URL(fileURLWithPath: workspacePath).lastPathComponent }
    func executable(for kind: AgentKind) -> String? {
        ShellSafety.executable(kind.rawValue, override: defaults.string(forKey: kind.rawValue + "Path") ?? "")
    }
    /// Sessions of the active work folder; the others keep running in the background.
    var visibleSessions: [TerminalSession] { sessions.filter { Workspaces.normalize($0.initialDirectory.path) == workspacePath } }
    func runningCount(in path: String) -> Int {
        sessions.filter { $0.isRunning && Workspaces.normalize($0.initialDirectory.path) == path }.count
    }
    @ObservationIgnored private var lastSelection: [String: UUID] = [:]
    func addWorkspace() {
        // The always-on-top island must not cover the system file picker.
        collapse?()
        defer { showTerminal?() }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L("작업 폴더 추가", "Add Folder")
        panel.message = L("NotchAgent에서 관리할 작업 폴더를 선택하세요. 여러 개를 한 번에 추가할 수 있습니다.", "Choose work folders for NotchAgent. You can add several at once.")
        panel.directoryURL = URL(fileURLWithPath: workspacePath)
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = Workspaces.normalize(url.path)
            if !workspaces.contains(where: { $0.path == path }) { workspaces.append(SavedWorkspace(path: path)) }
        }
        saveWorkspaces()
        if let last = panel.urls.last { activateWorkspace(Workspaces.normalize(last.path)) }
    }
    func activateWorkspace(_ path: String) {
        if let current = selectedID { lastSelection[workspacePath] = current }
        workspacePath = path; defaults.set(path, forKey: "workspace")
        let visible = visibleSessions
        selectedID = lastSelection[path].flatMap { id in visible.first { $0.id == id }?.id } ?? visible.last?.id
    }
    func removeWorkspace(_ path: String) {
        let running = sessions.filter { $0.isRunning && Workspaces.normalize($0.initialDirectory.path) == path }.count
        if running > 0 {
            let alert = NSAlert()
            alert.messageText = L("이 작업 폴더를 목록에서 제거할까요?", "Remove this folder from the list?")
            alert.informativeText = L("이 폴더에서 실행 중인 \(running)개의 세션이 종료됩니다. 폴더와 파일은 삭제되지 않습니다.", "\(running) running session(s) in this folder will end. The folder and its files are not deleted.")
            alert.addButton(withTitle: L("취소", "Cancel")); alert.addButton(withTitle: L("세션 종료 후 제거", "End Sessions and Remove"))
            guard (runAlert?(alert) ?? alert.runModal()) == .alertSecondButtonReturn else { return }
        }
        forgetWorkspace(path)
    }
    /// Drops a folder from the list and ends its sessions, without asking.
    private func forgetWorkspace(_ path: String) {
        let affected = sessions.filter { Workspaces.normalize($0.initialDirectory.path) == path }
        TerminalSession.stopAll(affected)
        sessions.removeAll { session in affected.contains { $0.id == session.id } }
        saveSessions()
        let index = workspaces.firstIndex { $0.path == path } ?? 0
        workspaces.removeAll { $0.path == path }
        if workspaces.isEmpty { workspaces = [SavedWorkspace(path: Workspaces.normalize(FileManager.default.homeDirectoryForCurrentUser.path))] }
        saveWorkspaces()
        if workspacePath == path { activateWorkspace(workspaces[min(index, workspaces.count - 1)].path) }
    }
    /// Asks for a branch, creates `<repo>.worktrees/<branch>` beside the repository, and switches to it.
    func createWorktree(from repository: String) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = L("feature/새-작업", "feature/new-task")
        let alert = NSAlert()
        alert.messageText = L("새 worktree 만들기", "New Worktree")
        let repoName = URL(fileURLWithPath: repository).lastPathComponent
        alert.informativeText = L("\(repoName) 저장소 옆에 이 브랜치의 작업 폴더를 만듭니다. 에이전트마다 서로 다른 브랜치에서 동시에 작업할 때 쓰세요. 이미 있는 브랜치면 그대로 체크아웃합니다.",
                                  "Creates a folder for this branch next to the \(repoName) repository, so agents can work on different branches at the same time. An existing branch is checked out as is.")
        alert.accessoryView = field
        alert.addButton(withTitle: L("만들기", "Create")); alert.addButton(withTitle: L("취소", "Cancel"))
        alert.window.initialFirstResponder = field
        guard (runAlert?(alert) ?? alert.runModal()) == .alertFirstButtonReturn else { return }
        let branch = field.stringValue
        Task.detached {
            let result = Result { try Worktree.create(repository: repository, branch: branch) }
            await MainActor.run { self.finishCreatingWorktree(result, after: repository) }
        }
    }
    func finishCreatingWorktree(_ result: Result<String, Error>, after repository: String) {
        switch result {
        case .success(let created):
            let path = Workspaces.normalize(created)
            if !workspaces.contains(where: { $0.path == path }) {
                let index = (workspaces.firstIndex { $0.path == repository } ?? workspaces.count - 1) + 1
                workspaces.insert(SavedWorkspace(path: path), at: min(index, workspaces.count))
                saveWorkspaces()
            }
            activateWorkspace(path)
            lastError = nil
        case .failure(let error):
            Log.app.notice("worktree creation failed")
            lastError = error.localizedDescription
        }
    }
    /// Ends the folder's sessions and runs `git worktree remove` (never forced).
    func removeWorktree(_ path: String) {
        let running = sessions.filter { $0.isRunning && Workspaces.normalize($0.initialDirectory.path) == path }.count
        let alert = NSAlert()
        alert.messageText = L("이 worktree를 제거할까요?", "Remove this worktree?")
        alert.informativeText = L("\(URL(fileURLWithPath: path).lastPathComponent) 작업 폴더를 지웁니다. 브랜치와 커밋은 저장소에 남고, 커밋하지 않은 변경이 있으면 제거하지 않습니다.", "Deletes the \(URL(fileURLWithPath: path).lastPathComponent) folder. The branch and its commits stay in the repository, and nothing is removed if there are uncommitted changes.")
            + (running > 0 ? L(" 실행 중인 \(running)개의 세션이 종료됩니다.", " \(running) running session(s) will end.") : "")
        alert.addButton(withTitle: L("취소", "Cancel")); alert.addButton(withTitle: L("worktree 제거", "Remove Worktree"))
        guard (runAlert?(alert) ?? alert.runModal()) == .alertSecondButtonReturn else { return }
        TerminalSession.stopAll(sessions.filter { Workspaces.normalize($0.initialDirectory.path) == path })
        Task.detached {
            let result = Result { try Worktree.remove(path) }
            await MainActor.run {
                switch result {
                case .success: self.forgetWorkspace(path); self.lastError = nil
                case .failure(let error): self.lastError = error.localizedDescription
                }
            }
        }
    }
    func moveWorkspace(_ path: String, onto target: String) {
        Reorder.move(&workspaces, id: path, onto: target, key: \.path)
        saveWorkspaces()
    }
    /// Reorders tabs; sessions of other folders keep their relative places.
    func moveSession(_ id: UUID, onto target: UUID) {
        Reorder.move(&sessions, id: id, onto: target, key: \.id)
        saveSessions()
    }
    private func saveWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) { defaults.set(data, forKey: "workspaces") }
    }
    func submitQuickPrompt(_ prompt: String) {
        quickPromptActive = false
        launch(quickAgent, prompt: prompt)
    }
    func cancelQuickPrompt() {
        quickPromptActive = false
        collapse?()
    }
    func launch(_ kind: AgentKind, prompt: String? = nil) {
        guard sessions.count < 8 else { lastError = L("최대 8개 세션을 열 수 있습니다. 사용하지 않는 세션을 닫아주세요.", "Up to 8 sessions can be open. Close one you no longer need."); return }
        guard let executable = executable(for: kind) else {
            lastError = L("\(kind.name) 실행 파일을 찾을 수 없습니다. 설정에서 경로를 지정하세요.", "\(kind.name) was not found. Set its path in Settings.")
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspacePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            lastError = L("작업 폴더가 없습니다. 다른 폴더를 선택하세요.", "The work folder no longer exists. Choose another folder."); return
        }
        let session = makeSession(kind: kind, executable: executable, directory: URL(fileURLWithPath: workspacePath), resume: false,
                                  extra: prompt.map { SessionRestore.initialPromptArguments(for: kind, prompt: $0) } ?? [])
        sessions.append(session); selectedID = session.id; lastError = nil
        saveSessions()
        showTerminal?()
    }
    private func makeSession(kind: AgentKind, executable: String, directory: URL, resume: Bool, extra: [String] = []) -> TerminalSession {
        var arguments: [String] = [], environment: [String: String] = [:]
        if kind == .claude, claudeUsage.enabled, let helper = Bundle.main.executablePath {
            arguments = ["--settings", ClaudeStatusLine.settingsJSON(executable: helper)]
            environment[ClaudeStatusLine.chainVariable] = ClaudeStatusLine.userCommand(workspace: directory) ?? ""
        }
        if resume { arguments += SessionRestore.resumeArguments(for: kind) }
        arguments += extra
        let session = TerminalSession(kind: kind, directory: directory, executable: executable, fontSize: fontSize,
                                      arguments: arguments, environment: environment)
        session.apply(appearance)
        return session
    }
    /// Remembers open sessions (not ones the user already ended) for the next launch.
    func saveSessions() {
        guard restoreSessions else { defaults.removeObject(forKey: "savedSessions"); return }
        let open = sessions.filter { !$0.ended }.map { SavedSession(kind: $0.kind, path: $0.initialDirectory.path) }
        if let data = try? JSONEncoder().encode(open) { defaults.set(data, forKey: "savedSessions") }
    }
    /// Recreates last time's tabs. Each starts when opened; the first Claude/Codex tab of a
    /// folder continues that folder's latest conversation.
    func restoreSavedSessions() {
        guard restoreSessions, let data = defaults.data(forKey: "savedSessions"),
              let saved = try? JSONDecoder().decode([SavedSession].self, from: data) else { return }
        for plan in SessionRestore.plan(saved) where sessions.count < 8 {
            guard SavedWorkspace(path: plan.session.path).exists, let executable = executable(for: plan.session.kind) else { continue }
            sessions.append(makeSession(kind: plan.session.kind, executable: executable,
                                        directory: URL(fileURLWithPath: plan.session.path), resume: plan.resume))
        }
        selectedID = visibleSessions.last?.id
    }
    func select(_ session: TerminalSession) { selectedID = session.id; showTerminal?() }
    func closeSession(_ session: TerminalSession) {
        if session.isBusy {
            let alert = NSAlert()
            alert.messageText = L("작업 중인 세션을 종료할까요?", "End a session that is working?")
            alert.informativeText = L("진행 중인 작업이 중단됩니다. 노치만 접으려면 \(hotkey.label)를 누르세요.", "The work in progress will stop. To just close the notch, press \(hotkey.label).")
            alert.addButton(withTitle: L("취소", "Cancel")); alert.addButton(withTitle: L("세션 종료", "End Session"))
            let response = runAlert?(alert) ?? alert.runModal()
            guard response == .alertSecondButtonReturn else { return }
        }
        session.stop()
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id { selectedID = visibleSessions.last?.id }
        saveSessions()
    }
}

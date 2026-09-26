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
    var preferredDisplay: String { didSet { defaults.set(preferredDisplay, forKey: "display") } }
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
        preferredDisplay = d.string(forKey: "display") ?? "builtin"
        let decode = { (key: String) in d.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedWorkspace].self, from: $0) } }
        workspacePath = Workspaces.normalize(workspacePath)
        workspaces = Workspaces.migrate(saved: decode("workspaces"), recent: decode("recentWorkspaces") ?? [], active: workspacePath)
    }
    /// Measured by the view; the island and its hover area use the same height.
    var previewContentHeight: CGFloat = 0
    var previewHeight: CGFloat {
        previewContentHeight > 0 ? previewContentHeight : 310 + notchHeight + (claudeUsage.enabled ? 90 : 0)
    }
    var selected: TerminalSession? { sessions.first { $0.id == selectedID } }
    var runningCount: Int { sessions.filter { !$0.ended }.count }
    var workspaceName: String { URL(fileURLWithPath: workspacePath).lastPathComponent }
    func executable(for kind: AgentKind) -> String? {
        ShellSafety.executable(kind.rawValue, override: defaults.string(forKey: kind.rawValue + "Path") ?? "")
    }
    /// Sessions of the active work folder; the others keep running in the background.
    var visibleSessions: [TerminalSession] { sessions.filter { Workspaces.normalize($0.initialDirectory.path) == workspacePath } }
    func runningCount(in path: String) -> Int {
        sessions.filter { !$0.ended && Workspaces.normalize($0.initialDirectory.path) == path }.count
    }
    @ObservationIgnored private var lastSelection: [String: UUID] = [:]
    func addWorkspace() {
        // The always-on-top island must not cover the system file picker.
        collapse?()
        defer { showTerminal?() }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "작업 폴더 추가"
        panel.message = "NotchAgent에서 관리할 작업 폴더를 선택하세요. 여러 개를 한 번에 추가할 수 있습니다."
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
        let affected = sessions.filter { Workspaces.normalize($0.initialDirectory.path) == path }
        let running = affected.filter { !$0.ended }.count
        if running > 0 {
            let alert = NSAlert()
            alert.messageText = "이 작업 폴더를 목록에서 제거할까요?"
            alert.informativeText = "이 폴더에서 실행 중인 \(running)개의 세션이 종료됩니다. 폴더와 파일은 삭제되지 않습니다."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "세션 종료 후 제거")
            guard (runAlert?(alert) ?? alert.runModal()) == .alertSecondButtonReturn else { return }
        }
        TerminalSession.stopAll(affected)
        sessions.removeAll { session in affected.contains { $0.id == session.id } }
        let index = workspaces.firstIndex { $0.path == path } ?? 0
        workspaces.removeAll { $0.path == path }
        if workspaces.isEmpty { workspaces = [SavedWorkspace(path: Workspaces.normalize(FileManager.default.homeDirectoryForCurrentUser.path))] }
        saveWorkspaces()
        if workspacePath == path { activateWorkspace(workspaces[min(index, workspaces.count - 1)].path) }
    }
    private func saveWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) { defaults.set(data, forKey: "workspaces") }
    }
    func launch(_ kind: AgentKind) {
        guard sessions.count < 8 else { lastError = "최대 8개 세션을 열 수 있습니다. 사용하지 않는 세션을 닫아주세요."; return }
        guard let executable = executable(for: kind) else {
            lastError = "\(kind.name) 실행 파일을 찾을 수 없습니다. 설정에서 경로를 지정하세요."
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workspacePath, isDirectory: &isDirectory), isDirectory.boolValue else {
            lastError = "작업 폴더가 없습니다. 다른 폴더를 선택하세요."; return
        }
        let directory = URL(fileURLWithPath: workspacePath)
        var arguments: [String] = [], environment: [String: String] = [:]
        if kind == .claude, claudeUsage.enabled, let helper = Bundle.main.executablePath {
            arguments = ["--settings", ClaudeStatusLine.settingsJSON(executable: helper)]
            environment[ClaudeStatusLine.chainVariable] = ClaudeStatusLine.userCommand(workspace: directory) ?? ""
        }
        let session = TerminalSession(kind: kind, directory: directory, executable: executable, fontSize: fontSize,
                                      arguments: arguments, environment: environment)
        session.terminal.onCollapse = { [weak self] in self?.collapse?() }
        sessions.append(session); selectedID = session.id; lastError = nil
        showTerminal?()
    }
    func select(_ session: TerminalSession) { selectedID = session.id; showTerminal?() }
    func closeSession(_ session: TerminalSession) {
        if !session.ended {
            let alert = NSAlert()
            alert.messageText = "이 터미널 세션을 종료할까요?"
            alert.informativeText = "실행 중인 명령과 에이전트가 중단됩니다. 노치만 접으려면 ⌘W를 사용하세요."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "세션 종료")
            let response = runAlert?(alert) ?? alert.runModal()
            guard response == .alertSecondButtonReturn else { return }
        }
        session.stop()
        sessions.removeAll { $0.id == session.id }
        if selectedID == session.id { selectedID = visibleSessions.last?.id }
    }
}

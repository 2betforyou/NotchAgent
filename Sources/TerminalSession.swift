import AppKit
import Observation
import SwiftTerm
import SwiftUI

class AgentTerminalView: LocalProcessTerminalView {
    var onActivity: (() -> Void)?
    var onBell: (() -> Void)?
    // BEL is how CLIs ask for attention (approval prompts, finished turns).
    override func bell(source: Terminal) {
        super.bell(source: source)
        onBell?()
    }
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        // Echo moves the caret; keep the composing syllable next to it instead of over the
        // character that was just committed.
        if !markedText.isEmpty { updateComposition() }
        onActivity?()
    }
    // A new or reselected session appears after the panel became key; take keyboard focus as
    // soon as the view is actually in the window instead of requiring a click.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.isKeyWindow { window.makeFirstResponder(self) }
    }
    // Remote programs must not overwrite the system clipboard via OSC 52.
    override func clipboardCopy(source: TerminalView, content: Data) {}

    // MARK: Input-method composition (Korean, Japanese, Chinese)
    // SwiftTerm ignores marked text, so an in-progress syllable was invisible until committed.
    // Composition is shown at the caret and only committed text is written to the PTY.
    private(set) var markedText = ""
    private lazy var compositionLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.drawsBackground = true
        label.isHidden = true
        addSubview(label)
        return label
    }()
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        markedText = Self.plainText(string)
        updateComposition()
    }
    override func unmarkText() {
        super.unmarkText()
        markedText = ""
        updateComposition()
    }
    override func hasMarkedText() -> Bool { !markedText.isEmpty }
    override func markedRange() -> NSRange {
        markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: (markedText as NSString).length)
    }
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = Self.plainText(string)
        let wasComposing = !markedText.isEmpty
        markedText = ""
        updateComposition()
        guard wasComposing else {
            // Some input methods commit NSAttributedString, which SwiftTerm would silently drop.
            super.insertText(text as NSString, replacementRange: replacementRange)
            return
        }
        // Text committed by an input method is not what the physical key produces. Under the
        // kitty keyboard protocol (Codex, Claude Code) SwiftTerm would encode the commit as the
        // key that triggered it: typing ㄴ after 안 sent "ㄴ" instead of "안". Send it as text,
        // as the protocol specifies for IME output, and leave the composing state so the next
        // key (for example Enter) is not swallowed.
        send(txt: text)
        super.unmarkText()
    }
    /// Control/Option shortcuts bypass the input method (the panel calls this before delivering
    /// them); commit the syllable first so it is neither lost nor merged with the next keystroke.
    func commitComposition(before event: NSEvent) {
        guard hasMarkedText(), !event.modifierFlags.intersection([.control, .option]).isEmpty else { return }
        let pending = markedText
        inputContext?.discardMarkedText()
        insertText(pending, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    private static func plainText(_ string: Any) -> String {
        (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }
    private func updateComposition() {
        let label = compositionLabel
        guard !markedText.isEmpty, let window else { label.isHidden = true; return }
        label.attributedStringValue = NSAttributedString(string: markedText, attributes: [
            .font: font, .foregroundColor: nativeForegroundColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        label.backgroundColor = nativeBackgroundColor
        label.sizeToFit()
        let caret = firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)
        let origin = convert(window.convertFromScreen(caret).origin, from: nil)
        label.frame.origin = NSPoint(x: min(origin.x, max(0, bounds.width - label.frame.width)), y: origin.y)
        label.isHidden = false
    }
}

@MainActor @Observable
final class TerminalSession: NSObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let kind: AgentKind
    let initialDirectory: URL
    let startedAt = Date()
    private(set) var title: String
    private(set) var directory: URL
    private(set) var exitCode: Int32?
    private(set) var ended = false
    /// Output is streaming right now (an agent thinking or a command running).
    private(set) var isWorking = false
    /// Something happened while the user was not looking: work finished, a bell, or exit.
    private(set) var attention: AttentionReason?
    @ObservationIgnored private var tracker = ActivityTracker()
    @ObservationIgnored private var rang = false
    @ObservationIgnored private var exitNoticed = false
    @ObservationIgnored let terminal: AgentTerminalView
    /// Restored tabs stay unstarted until the user opens them.
    private(set) var started = false
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private let executable: String
    @ObservationIgnored private let arguments: [String]
    @ObservationIgnored private let environment: [String: String]
    static let scrollbackLines = 5_000

    init(kind: AgentKind, directory: URL, executable: String, fontSize: Double,
         arguments: [String] = [], environment: [String: String] = [:]) {
        self.kind = kind; self.initialDirectory = directory; self.directory = directory
        self.executable = executable; self.arguments = arguments; self.environment = environment
        title = directory.lastPathComponent
        terminal = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 848, height: 372))
        super.init()
        terminal.processDelegate = self
        terminal.nativeBackgroundColor = NSColor(srgbRed: 0.035, green: 0.04, blue: 0.045, alpha: 1)
        terminal.nativeForegroundColor = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.89, alpha: 1)
        terminal.caretColor = NSColor(srgbRed: 0.65, green: 0.96, blue: 0.72, alpha: 1)
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        // SwiftTerm keeps 500 lines by default; agent transcripts are much longer.
        terminal.changeScrollback(Self.scrollbackLines)
        // Recorded without touching observed state; the model samples it once per second.
        terminal.onActivity = { [weak self] in self?.recordOutput(at: Date()) }
        terminal.onBell = { [weak self] in self?.rang = true }
    }
    func start() {
        guard !started else { return }
        started = true
        let env = ShellSafety.environment().merging(environment) { $1 }.map { "\($0.key)=\($0.value)" }
        let command = ([executable] + arguments).map(ShellSafety.quote).joined(separator: " ")
        let args = kind == .shell ? ["-l"] : ["-lc", "exec " + command]
        terminal.startProcess(executable: "/bin/zsh", args: args, environment: env, currentDirectory: directory.path)
        if !terminal.process.running {
            ended = true; exitCode = -1
            Log.session.error("PTY start failed for \(self.kind.rawValue, privacy: .public)")
            terminal.feed(text: "\r\n\u{1b}[31mNotchAgent: " + L("터미널을 시작하지 못했습니다. 작업 폴더 권한과 /bin/zsh를 확인하세요.", "Could not start the terminal. Check the work folder permissions and /bin/zsh.") + "\u{1b}[0m\r\n")
        }
    }
    /// Ends the session and everything it started. Children that ignore SIGHUP/SIGTERM
    /// are killed after a short grace period, and the shell is reaped so no zombie remains.
    func stop(grace: TimeInterval = 0.8) {
        Self.stopAll([self], grace: grace)
    }
    /// Signals every session first and waits once, so quitting with many sessions stays fast.
    static func stopAll(_ sessions: [TerminalSession], grace: TimeInterval = 0.8) {
        var pending: [(groups: [pid_t], shell: pid_t)] = []
        for session in sessions {
            guard session.started, !session.ended, !session.stopping else { continue }
            session.stopping = true
            let fd = session.terminal.process.childfd
            let foreground = fd >= 0 ? tcgetpgrp(fd) : -1
            let shell = session.terminal.process.shellPid
            let groups = ProcessCleanup.groups(shell: shell, foreground: foreground, excluding: getpgrp())
            for group in groups { kill(-group, SIGHUP) }
            session.terminal.terminate()
            session.ended = true
            pending.append((groups, shell))
        }
        guard !pending.isEmpty else { return }
        ProcessCleanup.finish(groups: pending.flatMap(\.groups), shells: pending.map(\.shell), grace: grace)
    }
    @ObservationIgnored private var appliedAppearance: TerminalAppearance?
    /// Theme, font and caret color; cheap to call repeatedly.
    func apply(_ appearance: TerminalAppearance) {
        guard appearance != appliedAppearance else { return }
        appliedAppearance = appearance
        let theme = appearance.theme
        terminal.nativeBackgroundColor = TerminalTheme.ns(theme.background)
        terminal.nativeForegroundColor = TerminalTheme.ns(theme.foreground)
        terminal.installColors(theme.ansi.map(TerminalTheme.term))
        terminal.caretColor = appearance.accent.nsColor
        terminal.font = TerminalFont.font(appearance.font, size: appearance.size)
    }
    var isRunning: Bool { started && !ended }
    /// Closing now would interrupt work: an agent is streaming output, or the shell is running
    /// a command (its foreground process group is not the shell itself). Idle sessions close
    /// without asking; the CLIs keep their conversations for /resume.
    var isBusy: Bool {
        guard isRunning else { return false }
        if isWorking { return true }
        guard kind == .shell else { return false }
        let fd = terminal.process.childfd
        let foreground = fd >= 0 ? tcgetpgrp(fd) : -1
        return foreground > 0 && foreground != terminal.process.shellPid
    }
    /// When the current stretch of work began (nil while idle).
    var workingSince: Date? { isWorking ? tracker.busySince : nil }
    /// The program and arguments this session runs (inside a login shell).
    var commandLine: [String] { [executable] + arguments }
    func recordOutput(at date: Date) { tracker.output(at: date) }
    /// Samples activity. Returns a reason when the session newly needs the user's attention.
    func tick(now: Date, visible: Bool) -> AttentionReason? {
        let working = !ended && tracker.isWorking(now: now)
        if working != isWorking { isWorking = working }
        let finished = tracker.finishedWork(now: now)
        let bell = rang; rang = false
        var reason: AttentionReason?
        if ended, started, !exitNoticed { exitNoticed = true; if !stopping { reason = .exited } }
        else if bell { reason = .bell }
        else if finished { reason = .finished }
        if visible {
            if attention != nil { attention = nil }
            return nil
        }
        if let reason { attention = reason }
        return reason
    }
    func clearAttention() { if attention != nil { attention = nil } }
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let clean = String(title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        if !clean.isEmpty { Task { @MainActor [weak self] in self?.title = String(clean.prefix(90)) } }
    }
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost" || url.host == ProcessInfo.processInfo.hostName else { return }
        Task { @MainActor [weak self] in self?.directory = url }
    }
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let code = exitCode.map(ProcessCleanup.exitCode(fromWaitStatus:))
        Task { @MainActor [weak self] in self?.exitCode = code; self?.ended = true }
    }
}

struct EmbeddedTerminal: NSViewRepresentable {
    let session: TerminalSession
    let appearance: TerminalAppearance
    func makeNSView(context: Context) -> NSView {
        let host = NSView()
        let terminal = session.terminal
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            terminal.topAnchor.constraint(equalTo: host.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        Task { @MainActor in
            await Task.yield()
            session.start()
            host.window?.makeFirstResponder(terminal)
        }
        return host
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        session.apply(appearance)
    }
    // Removing the view never closes its PTY. SessionStore owns the lifetime.
}

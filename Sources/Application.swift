import AppKit
import SwiftUI
import Carbon

@main
enum NotchAgentApp {
    @MainActor static func main() {
        // NOTCHAGENT_LANGUAGE lets tests pin the status line helper's language.
        AppLanguage.current = (ProcessInfo.processInfo.environment["NOTCHAGENT_LANGUAGE"] ?? UserDefaults.standard.string(forKey: "language"))
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        if CommandLine.arguments.dropFirst().first == ClaudeStatusLine.argument { exit(ClaudeStatusLine.run()) }
        if CommandLine.arguments.dropFirst().first == AgentEvents.argument { exit(AgentEvents.run(Array(CommandLine.arguments.dropFirst(2)))) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class IslandPanel: NSPanel {
    var acceptsKeyboard = false
    /// Tab shortcuts (⌘1–8, ⇧⌘[ ], ⌘T) handled before the terminal sees the key.
    var onTabShortcut: ((String, Bool) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags == .command || flags == [.command, .shift], let key = event.charactersIgnoringModifiers?.lowercased(),
           onTabShortcut?(Self.usKey(event) ?? key, flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    /// Layout-independent key for shortcuts (a Korean input source reports "ㅅ" for T).
    private static func usKey(_ event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case 18: "1"; case 19: "2"; case 20: "3"; case 21: "4"; case 23: "5"; case 22: "6"; case 26: "7"; case 28: "8"
        case 17: "t"; case 30: "]"; case 33: "["
        default: nil
        }
    }
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    // AppKit pushes windows below the menu bar by default; the island must sit on the notch itself.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let terminal = firstResponder as? AgentTerminalView {
            terminal.commitComposition(before: event)
        }
        super.sendEvent(event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: IslandPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var activityTimer: Timer?
    private var menuTracking = false
    private var hoverStart: Date?
    private var leaveStart: Date?
    private var previousApp: NSRunningApplication?
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var screen: NSScreen?
    private var locked = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests must not register shortcuts, open windows, or start CLI processes.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        // A second copy (Xcode build, another folder, login item) would stack a second island on
        // the notch and fight over the shortcut. Hand over to the copy that is already running.
        let me = NSRunningApplication.current
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0 != me && !$0.isTerminated }) {
            Log.app.notice("another instance is running (pid \(other.processIdentifier, privacy: .public)); exiting")
            other.activate()
            exit(0)
        }
        // Preview never becomes key. Explicit expansion uses a normal key panel so
        // keyboard focus and input-method ownership behave like a native terminal.
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true; panel.isMovable = false
        // Set after isFloatingPanel, which resets the level to .floating; must sit above the menu bar.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: IslandView(model: model))
        panel.setAccessibilityLabel("NotchAgent")
        model.showTerminal = { [weak self] in self?.expand() }
        model.collapse = { [weak self] in self?.collapse() }
        model.showSettings = { [weak self] in self?.showSettings() }
        model.runAlert = { [weak self] alert in self?.runAlert(alert) ?? alert.runModal() }
        model.beginQuickPrompt = { [weak self] in self?.beginQuickPrompt() }
        panel.onTabShortcut = { [weak self] key, shift in
            guard let self, self.model.phase == .terminal else { return false }
            return self.model.handleTabShortcut(key: key, shift: shift)
        }
        DistributedNotificationCenter.default().addObserver(forName: AgentEvents.notification, object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            let session = info["session"] as? String ?? "", event = info["event"] as? String ?? "", conversation = info["conversation"] as? String ?? ""
            MainActor.assumeIsolated { self?.model.handleAgentEvent(session: session, event: event, conversation: conversation) }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            // Clicking another app while typing a quick prompt cancels it.
            MainActor.assumeIsolated {
                guard let self, self.model.quickPromptActive else { return }
                self.model.quickPromptActive = false
                self.collapse()
            }
        }
        positionPanel()
        panel.orderFrontRegardless()
        installMenu()
        installShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // A menu opened from the preview (folder switcher) must not be closed by hover-out.
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = true }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = false; self?.leaveStart = nil }
        }
        // Displays can come back in a different arrangement after sleep.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        schedulePointerTimer(PointerPolling.fast)
        activityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tickActivity() }
        }
        RunLoop.main.add(activityTimer!, forMode: .common)
        model.usage.start()
        model.claudeUsage.start()
        model.restoreSavedSessions()
        if !UserDefaults.standard.bool(forKey: "onboarded") { showWelcome() }
    }
    private func positionPanel() {
        let target = model.preferredDisplay == "pointer"
            ? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            : NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let target = target ?? NSScreen.main ?? NSScreen.screens.first else { return }
        screen = target
        model.displayName = target.localizedName
        let notch = target.safeAreaInsets.top
        model.hasPhysicalNotch = notch > 0
        model.notchHeight = max(30, notch)
        let physicalWidth: CGFloat
        if let left = target.auxiliaryTopLeftArea, let right = target.auxiliaryTopRightArea, notch > 0 {
            physicalWidth = max(0, right.minX - left.maxX)
        } else { physicalWidth = 110 }
        model.compactWidth = physicalWidth + 100
        model.physicalNotchWidth = notch > 0 ? physicalWidth : 0
        model.panelWidth = min(940, target.frame.width - 64)
        model.panelHeight = min(620, target.frame.height - 100)
        let size = NSSize(width: model.panelWidth + 32, height: model.panelHeight + 32)
        panel.setFrame(NSRect(x: target.frame.midX - size.width / 2, y: target.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
    private var pointerInterval: TimeInterval = 0
    /// Re-arms the pointer timer only when the rate changes; a small tolerance lets macOS
    /// coalesce wakeups with other timers.
    private func schedulePointerTimer(_ interval: TimeInterval) {
        guard interval != pointerInterval else { return }
        pointerInterval = interval
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    private func trackPointer() {
        guard !locked, !menuTracking, var screen else { return }
        // "Pointer" mode: the closed island follows the mouse to whichever display it is on.
        if model.preferredDisplay == "pointer", model.phase == .closed,
           let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }), pointerScreen != screen {
            positionPanel(); screen = self.screen ?? screen
        }
        let width = model.phase == .closed ? model.closedWidth : model.phase == .preview ? min(570, model.panelWidth) : model.panelWidth
        let height = model.phase == .closed ? model.closedHeight : model.phase == .preview ? model.previewHeight : model.panelHeight
        let rect = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        let inside = rect.contains(NSEvent.mouseLocation)
        let near = rect.insetBy(dx: -PointerPolling.nearMargin, dy: -PointerPolling.nearMargin).contains(NSEvent.mouseLocation)
        schedulePointerTimer(PointerPolling.interval(near: near, phase: model.phase, pending: hoverStart != nil || leaveStart != nil))
        // Keep delivering a drag (for example a terminal selection) that leaves the island.
        if NSEvent.pressedMouseButtons != 0, !panel.ignoresMouseEvents { return }
        panel.ignoresMouseEvents = !inside
        if model.phase == .terminal { hoverStart = nil; leaveStart = nil; return }
        if model.quickPromptActive { panel.ignoresMouseEvents = false; leaveStart = nil; return }
        if inside {
            leaveStart = nil
            if hoverStart == nil { hoverStart = Date() }
            if model.hoverEnabled, model.phase == .closed, Date().timeIntervalSince(hoverStart!) > model.hoverSpeed.delay { model.phase = .preview }
        } else {
            hoverStart = nil
            if leaveStart == nil { leaveStart = Date() }
            if model.phase == .preview, Date().timeIntervalSince(leaveStart!) > 0.28 {
                // If the preview holds keyboard focus (after a quick prompt), hand it back too.
                if panel.isKeyWindow { collapse() } else { model.phase = .closed }
            }
        }
    }
    private func beginQuickPrompt() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        panel.acceptsKeyboard = true; panel.ignoresMouseEvents = false
        NSApp.activate(); panel.makeKeyAndOrderFront(nil)
        model.quickPromptActive = true
    }
    @objc func expand() {
        if model.phase != .terminal {
            if let front = NSWorkspace.shared.frontmostApplication,
               front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            positionPanel()
        }
        model.phase = .terminal
        panel.acceptsKeyboard = true; panel.ignoresMouseEvents = false
        NSApp.activate(); panel.makeKeyAndOrderFront(nil)
        if let terminal = model.selected?.terminal { panel.makeFirstResponder(terminal) }
    }
    @objc func collapse() {
        let hadFocus = panel.isKeyWindow
        model.phase = .closed; panel.acceptsKeyboard = false
        panel.resignKey()
        hoverStart = nil; leaveStart = nil
        if hadFocus, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
    }
    /// The island floats above the menu bar, which is also above modal windows. Without lowering
    /// it, a confirmation alert opened behind the terminal and the app looked frozen.
    func runAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let response = Self.runAlert(alert, below: panel)
        if model.phase == .terminal {
            panel.makeKeyAndOrderFront(nil)
            if let terminal = model.selected?.terminal { panel.makeFirstResponder(terminal) }
        }
        return response
    }
    static func runAlert(_ alert: NSAlert, below panel: NSWindow) -> NSApplication.ModalResponse {
        let level = panel.level
        panel.level = .floating
        defer { panel.level = level }
        NSApp.activate()
        return alert.runModal()
    }
    @objc func toggle() { model.phase == .terminal ? collapse() : expand() }
    @objc private func displaysChanged() { positionPanel() }
    @objc private func screenLocked() { locked = true; collapse(); panel.orderOut(nil) }
    @objc private func screenUnlocked() { locked = false; positionPanel(); panel.orderFrontRegardless() }
    private func installMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "NotchAgent")
        buildMenus()
        model.languageChanged = { [weak self] in
            self?.buildMenus()
            self?.settingsWindow?.title = L("NotchAgent 설정", "NotchAgent Settings")
        }
    }
    /// Status item menu and the main menu (edit commands for the terminal); rebuilt on language change.
    private func buildMenus() {
        let menu = NSMenu()
        menu.addItem(withTitle: L("NotchAgent 열기 / 접기", "Open / Close NotchAgent"), action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: L("설정…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: L("NotchAgent 종료", "Quit NotchAgent"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        // Main menu supplies standard edit actions to the embedded terminal and text fields.
        let main = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = menu.copy() as? NSMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title: L("편집", "Edit"), action: nil, keyEquivalent: "")
        let edit = NSMenu(title: L("편집", "Edit"))
        edit.addItem(withTitle: L("복사", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("붙여넣기", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("모두 선택", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        // The terminal's own find bar (SwiftTerm handles these text finder actions).
        for (title, key, shift, action) in [(L("찾기…", "Find…"), "f", false, NSTextFinder.Action.showFindInterface),
                                            (L("다음 찾기", "Find Next"), "g", false, .nextMatch),
                                            (L("이전 찾기", "Find Previous"), "g", true, .previousMatch)] {
            let item = NSMenuItem(title: title, action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            item.tag = action.rawValue
            edit.addItem(item)
        }
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
    }
    private func installShortcut() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if !register(model.hotkey) {
            model.lastError = L("\(model.hotkey.label) 단축키를 등록할 수 없습니다. 다른 앱의 단축키와 충돌하는지 확인하세요. 메뉴 막대로 열 수 있습니다.", "Could not register \(model.hotkey.label). Another app may be using it. You can still open NotchAgent from the menu bar.")
        }
        model.applyHotkey = { [weak self] new in self?.changeHotkey(to: new) ?? false }
        model.suspendHotkey = { [weak self] suspended in
            guard let self else { return }
            if suspended { self.unregisterHotkey() } else { _ = self.register(self.model.hotkey) }
        }
    }
    private func register(_ key: Hotkey) -> Bool {
        unregisterHotkey()
        let result = RegisterEventHotKey(key.keyCode, key.modifiers, EventHotKeyID(signature: 0x4E414754, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { Log.app.error("hotkey registration failed: \(result, privacy: .public)"); hotKey = nil }
        return result == noErr
    }
    private func unregisterHotkey() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
    /// Switches the global shortcut; keeps the old one if the new combination is taken.
    private func changeHotkey(to new: Hotkey) -> Bool {
        guard register(new) else { _ = register(model.hotkey); return false }
        model.hotkey = new
        return true
    }
    @objc func showSettings() {
        collapse()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("NotchAgent 설정", "NotchAgent Settings"); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, displayChanged: { [weak self] in self?.positionPanel() }))
            window.center(); settingsWindow = window
        }
        NSApp.activate(); settingsWindow?.makeKeyAndOrderFront(nil)
    }
    private func showWelcome() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 530), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NotchAgent"; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView { [weak self] in
            UserDefaults.standard.set(true, forKey: "onboarded")
            self?.welcomeWindow?.close(); self?.expand()
        })
        window.center(); welcomeWindow = window
        NSApp.activate(); window.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Idle sessions are saved and come back next launch; only interrupting work needs a yes.
        let busy = model.sessions.filter(\.isBusy).count
        if busy > 0 {
            let alert = NSAlert()
            alert.messageText = L("NotchAgent를 종료할까요?", "Quit NotchAgent?")
            alert.informativeText = L("작업 중인 \(busy)개의 세션이 중단됩니다.", "\(busy) session(s) that are working will stop.")
            alert.addButton(withTitle: L("취소", "Cancel")); alert.addButton(withTitle: L("종료", "Quit"))
            if runAlert(alert) != .alertSecondButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); activityTimer?.invalidate(); model.usage.stop(); model.claudeUsage.stop()
        model.saveSessions() // before stopping, which marks every session ended
        TerminalSession.stopAll(model.sessions)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

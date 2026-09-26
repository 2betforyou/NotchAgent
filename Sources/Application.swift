import AppKit
import SwiftUI
import Carbon

@main
enum NotchAgentApp {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == ClaudeStatusLine.argument { exit(ClaudeStatusLine.run()) }
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
    var onCollapse: (() -> Void)?
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
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            onCollapse?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panel: IslandPanel!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
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
        panel.onCollapse = model.collapse
        model.showSettings = { [weak self] in self?.showSettings() }
        model.runAlert = { [weak self] alert in self?.runAlert(alert) ?? alert.runModal() }
        positionPanel()
        panel.orderFrontRegardless()
        installMenu()
        installShortcut()
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Displays can come back in a different arrangement after sleep.
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displaysChanged), name: NSWorkspace.screensDidWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        model.usage.start()
        model.claudeUsage.start()
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
        model.panelWidth = min(940, target.frame.width - 64)
        model.panelHeight = min(620, target.frame.height - 100)
        let size = NSSize(width: model.panelWidth + 32, height: model.panelHeight + 32)
        panel.setFrame(NSRect(x: target.frame.midX - size.width / 2, y: target.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
    private func trackPointer() {
        guard !locked, var screen else { return }
        // "Pointer" mode: the closed island follows the mouse to whichever display it is on.
        if model.preferredDisplay == "pointer", model.phase == .closed,
           let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }), pointerScreen != screen {
            positionPanel(); screen = self.screen ?? screen
        }
        let width = model.phase == .closed ? model.compactWidth : model.phase == .preview ? min(570, model.panelWidth) : model.panelWidth
        let height = model.phase == .closed ? model.notchHeight : model.phase == .preview ? model.previewHeight : model.panelHeight
        let rect = NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        let inside = rect.contains(NSEvent.mouseLocation)
        // Keep delivering a drag (for example a terminal selection) that leaves the island.
        if NSEvent.pressedMouseButtons != 0, !panel.ignoresMouseEvents { return }
        panel.ignoresMouseEvents = !inside
        if model.phase == .terminal { hoverStart = nil; leaveStart = nil; return }
        if inside {
            leaveStart = nil
            if hoverStart == nil { hoverStart = Date() }
            if model.hoverEnabled, model.phase == .closed, Date().timeIntervalSince(hoverStart!) > model.hoverSpeed.delay { model.phase = .preview }
        } else {
            hoverStart = nil
            if leaveStart == nil { leaveStart = Date() }
            if model.phase == .preview, Date().timeIntervalSince(leaveStart!) > 0.28 { model.phase = .closed }
        }
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
        let menu = NSMenu()
        menu.addItem(withTitle: "NotchAgent 열기 / 접기", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "설정…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "NotchAgent 종료", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        // Main menu supplies standard edit actions to the embedded terminal and text fields.
        let main = NSMenu()
        let appItem = NSMenuItem(); appItem.submenu = menu.copy() as? NSMenu; main.addItem(appItem)
        let editItem = NSMenuItem(title: "편집", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
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
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4E414754, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if result != noErr { Log.app.error("hotkey registration failed: \(result, privacy: .public)") }
        if result != noErr { model.lastError = "⌃⌥Space 단축키를 등록할 수 없습니다. 다른 앱의 단축키와 충돌하는지 확인하세요. 메뉴 막대로 열 수 있습니다." }
    }
    @objc func showSettings() {
        collapse()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 580), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "NotchAgent 설정"; window.isReleasedWhenClosed = false
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
        if model.runningCount > 0 {
            let alert = NSAlert()
            alert.messageText = "NotchAgent를 종료할까요?"
            alert.informativeText = "열려 있는 \(model.runningCount)개의 터미널 세션과 실행 중인 작업이 종료됩니다."
            alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "종료")
            if runAlert(alert) != .alertSecondButtonReturn { return .terminateCancel }
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); model.usage.stop(); model.claudeUsage.stop()
        TerminalSession.stopAll(model.sessions)
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

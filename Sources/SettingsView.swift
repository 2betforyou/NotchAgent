import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable var model: AppModel
    let displayChanged: () -> Void
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("geminiPath") private var geminiPath = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        Form {
            Section(L("일반", "General")) {
                Picker(L("언어", "Language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                }
                ShortcutRecorder(model: model)
                Toggle(L("로그인 시 실행", "Launch at login"), isOn: $loginEnabled).onChange(of: loginEnabled) { _, value in
                    // Writing loginEnabled below re-enters this handler; act only on real changes.
                    guard value != (SMAppService.mainApp.status == .enabled) else { return }
                    loginError = nil
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { loginError = error.localizedDescription }
                    if SMAppService.mainApp.status == .requiresApproval {
                        loginError = L("시스템 설정 → 일반 → 로그인 항목에서 NotchAgent를 허용하세요.", "Allow NotchAgent in System Settings → General → Login Items.")
                    }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
            Section(L("노치", "Notch")) {
                LabeledContent(L("현재 위치", "Current display"), value: model.displayName)
                Text(model.hasPhysicalNotch ? L("실제 카메라 노치 위치에 정렬됨 · 메뉴바 높이와 카메라 폭 자동 감지", "Aligned to the camera notch · menu bar height and camera width detected") : L("활성 화면에서 실제 노치를 감지하지 못했습니다. 맥북 내장 화면이 활성화되면 자동으로 노치로 이동합니다.", "No camera notch on the active display. NotchAgent moves to the notch when the built-in display is active."))
                    .font(.caption).foregroundStyle(model.hasPhysicalNotch ? Color.secondary : .orange)
                Picker(L("표시 화면", "Display"), selection: $model.preferredDisplay) {
                    Text(L("내장 노치 화면 우선", "Built-in notch display first")).tag("builtin")
                    Text(L("열 때 마우스가 있는 화면", "Display with the pointer")).tag("pointer")
                }.onChange(of: model.preferredDisplay) { _, _ in displayChanged() }
                Toggle(L("마우스를 올리면 미리보기", "Preview on hover"), isOn: $model.hoverEnabled)
                Picker(L("호버 반응 속도", "Hover delay"), selection: $model.hoverSpeed) {
                    ForEach(HoverSpeed.allCases) { Text($0.label).tag($0) }
                }.disabled(!model.hoverEnabled)
                Toggle(L("작업 알림 표시", "Show activity notices"), isOn: $model.notifyEnabled)
                Text(L("노치를 접어 둔 동안 보고 있지 않은 세션이 작업을 마치거나 확인을 요청하면 노치 아래에 잠깐 알려 줍니다.", "While the notch is closed, briefly shows below it when a session you are not watching finishes or asks for you."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("모양", "Appearance")) {
                Picker(L("강조색", "Accent color"), selection: $model.accent) {
                    ForEach(Accent.allCases) { accent in
                        Label { Text(accent.name) } icon: { Image(nsImage: Self.swatch(accent.nsColor)) }.tag(accent)
                    }
                }
                Picker(L("터미널 테마", "Terminal theme"), selection: $model.terminalTheme) {
                    ForEach(TerminalTheme.allCases) { Text($0.name).tag($0) }
                }
                Picker(L("글꼴", "Font"), selection: $model.terminalFont) {
                    ForEach(TerminalFont.available, id: \.id) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Text(L("글자 크기", "Font size"))
                    Slider(value: $model.fontSize, in: 11...20, step: 1)
                    Text("\(Int(model.fontSize)) pt").monospacedDigit().frame(width: 44)
                }
            }
            Section(L("세션", "Sessions")) {
                Toggle(L("다시 열 때 세션 복원", "Restore sessions on relaunch"), isOn: $model.restoreSessions)
                Text(L("앱을 다시 열면 열려 있던 탭을 복원하고, 탭을 열 때 시작합니다. Claude Code와 Codex는 그 폴더의 마지막 대화를 이어 엽니다.", "Reopens your tabs when NotchAgent starts; each starts when you open it. Claude Code and Codex continue the folder's latest conversation."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                pathField("Codex", text: $codexPath, kind: .codex)
                pathField("Claude", text: $claudePath, kind: .claude)
                pathField("Gemini", text: $geminiPath, kind: .gemini)
            } header: { Text(L("CLI 실행 파일", "CLI executables")) } footer: {
                Text(L("비워두면 Homebrew와 일반 설치 경로에서 찾습니다. 설치와 로그인은 각 CLI에서 진행하세요. API 키를 NotchAgent에 입력하지 않습니다.", "Leave empty to search Homebrew and common install paths. Install and sign in with each CLI; never enter API keys into NotchAgent."))
            }
            Section(L("사용량과 개인정보", "Usage & Privacy")) {
                Toggle(L("Codex 계정 사용량 조회", "Show Codex account usage"), isOn: Binding(get: { model.usage.enabled }, set: { model.usage.setEnabled($0) }))
                Text(L("기존 Codex CLI의 읽기 전용 계정 조회를 사용합니다. 5분마다 갱신하며, 구독 한도와 누적 토큰은 서로 다른 값입니다.", "Uses the Codex CLI's read-only account query, every 5 minutes. Subscription limits and lifetime tokens are different numbers."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.usage.enabled, let snapshot = model.usage.snapshot {
                    LabeledContent(L("Codex 마지막 갱신", "Codex last updated"), value: snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                    if let tokens = snapshot.lifetimeTokens { LabeledContent(L("CLI가 보고한 누적 토큰", "Lifetime tokens reported by the CLI"), value: tokens.formatted()) }
                }
                Toggle(L("Claude 계정 사용량 표시", "Show Claude account usage"), isOn: Binding(get: { model.claudeUsage.enabled }, set: { model.claudeUsage.setEnabled($0) }))
                Text(L("NotchAgent에서 새로 여는 Claude Code 세션이 보고하는 5시간·주간 한도를 표시합니다(Pro/Max, 첫 응답 이후). 로그인 정보는 읽지 않으며, 기존 상태 표시줄 설정은 그대로 동작합니다.", "Shows the 5-hour and weekly limits reported by Claude Code sessions you open in NotchAgent (Pro/Max, after the first response). Sign-in data is never read, and your own status line keeps working."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.claudeUsage.enabled, let snapshot = model.claudeUsage.snapshot {
                    LabeledContent(L("Claude 마지막 갱신", "Claude last updated"), value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Text(L("터미널 내용·API 키는 저장하거나 별도 서버로 전송하지 않습니다. 실행한 CLI 자체의 네트워크·파일 접근은 해당 CLI의 정책을 따릅니다.", "Terminal content and API keys are never stored or sent anywhere. Network and file access by the CLIs you run follows their own policies."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("NotchAgent \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · SwiftTerm (MIT)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).frame(width: 590, height: 640)
        .id(model.language) // subviews such as the shortcut recorder re-render in the new language
    }
    /// Menus show images, not SwiftUI views; a small color dot per accent.
    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill(); return true
        }
    }
    private func pathField(_ title: String, text: Binding<String>, kind: AgentKind) -> some View {
        HStack {
            TextField(title, text: text, prompt: Text(L("자동 탐색", "Auto-detect")))
            Image(systemName: model.executable(for: kind) == nil ? "questionmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(model.executable(for: kind) == nil ? Color.secondary : .green)
                .help(model.executable(for: kind) ?? L("실행 파일을 찾을 수 없습니다", "Executable not found"))
        }
    }
}

/// Click, then press the new combination. Esc cancels. The current shortcut is paused while
/// recording so pressing it again can be captured instead of toggling the notch.
struct ShortcutRecorder: View {
    @Bindable var model: AppModel
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("열기 / 접기 단축키", "Open / close shortcut"))
                Spacer()
                if model.hotkey != .default, !recording {
                    Button(L("기본값", "Default")) { apply(.default) }.buttonStyle(.borderless)
                }
                Button { recording ? stop() : start() } label: {
                    Text(recording ? L("새 단축키를 누르세요…", "Press new shortcut…") : model.hotkey.label)
                        .monospaced().frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
                .accessibilityLabel(recording ? L("단축키 녹화 중", "Recording shortcut") : L("단축키 \(model.hotkey.label), 변경", "Shortcut \(model.hotkey.label), change"))
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange)
            } else if recording {
                Text(L("⌘, ⌃, ⌥ 중 하나 이상과 함께 누르세요. Esc를 누르면 취소합니다.", "Include ⌘, ⌃ or ⌥. Press Esc to cancel.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }
    private func start() {
        message = nil; recording = true
        model.suspendHotkey?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                stop(); return nil
            }
            if let key = Hotkey(keyCode: event.keyCode, flags: event.modifierFlags) { apply(key) }
            else { message = L("⌘, ⌃, ⌥ 중 하나 이상과 함께 누르세요.", "Include ⌘, ⌃ or ⌥.") }
            return nil
        }
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; model.suspendHotkey?(false) }
    }
    private func apply(_ key: Hotkey) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false
        if model.applyHotkey?(key) == false {
            message = L("\(key.label)는 다른 앱이 사용 중이라 등록할 수 없습니다. 기존 단축키를 유지합니다.", "\(key.label) is used by another app, so the current shortcut is kept.")
        } else {
            message = nil
        }
    }
}

struct WelcomeView: View {
    let start: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill").foregroundStyle(Palette.mint)
                Text("NotchAgent").fontWeight(.semibold)
                Spacer()
                Text("EARLY ACCESS").font(.caption2.monospaced()).foregroundStyle(Palette.muted)
            }
            Text("Your agents.\nOne notch away.").font(.system(size: 38, weight: .semibold)).tracking(-1.2)
            Text(L("화면 위 작은 작업 공간.\n쓰던 터미널과 CLI 에이전트를 그대로 가져오세요.", "A small workspace at the top of your screen.\nBring the terminal and CLI agents you already use."))
                .foregroundStyle(Palette.muted).lineSpacing(5)
            VStack(alignment: .leading, spacing: 15) {
                row("cursorarrow", L("올려서 확인", "Hover to glance"), L("노치에 마우스를 올리면 미리보기가 열립니다.", "Move the pointer onto the notch to open a preview."))
                row("keyboard", L("눌러서 작업", "Press to work"), L("⌃⌥Space로 열고 닫습니다. 단축키는 설정에서 바꿀 수 있습니다.", "Open and close with ⌃⌥Space. You can change it in Settings."))
                row("rectangle.stack", L("접어도 계속", "Keeps running"), L("세션은 유지됩니다. 앱을 종료하면 작업도 종료됩니다.", "Sessions keep going when closed. Quitting the app ends them."))
            }
            Spacer(minLength: 0)
            HStack {
                Text(L("별도 계정 없이 시작 · 사용량 연결은 선택", "No account needed · usage display is optional")).font(.caption2).foregroundStyle(Palette.muted)
                Spacer()
                Button(L("시작하기", "Get Started"), action: start).buttonStyle(MintButton()).keyboardShortcut(.defaultAction)
            }
        }.padding(36).frame(width: 560, height: 530).background(Color(white: 0.045)).foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).foregroundStyle(Palette.mint).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
}

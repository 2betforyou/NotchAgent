import SwiftUI
import ServiceManagement

struct NotificationRoutingView: View {
    @Bindable var model: AppModel
    private let events: [AttentionReason] = [.finished, .bell, .exited]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            GridRow {
                Text(L("이벤트", "Event"))
                ForEach(ActivityChannel.allCases, id: \.rawValue) { channel in
                    Text(channel.title).frame(maxWidth: .infinity)
                }
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(events, id: \.rawValue) { event in
                GridRow {
                    Text(event == .finished ? L("작업 완료", "Completed") : event == .bell ? L("확인 요청", "Needs input") : L("세션 종료·오류", "Ended / error"))
                    ForEach(ActivityChannel.allCases, id: \.rawValue) { channel in
                        Toggle(event.message + " · " + channel.title, isOn: $model[delivery: event, channel: channel])
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(event.message + " · " + channel.title)
                    }
                }
            }
        }
    }
}

private enum SettingsPage: CaseIterable {
    case general, notch, alerts, appearance, agents, about
    var title: String {
        switch self {
        case .general: L("일반", "General")
        case .notch: L("노치", "Notch")
        case .alerts: L("알림", "Alerts")
        case .appearance: L("모양", "Appearance")
        case .agents: L("에이전트", "Agents")
        case .about: L("정보", "About")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .notch: "rectangle.topthird.inset.filled"
        case .alerts: "bell"
        case .appearance: "paintpalette"
        case .agents: "terminal"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let displayChanged: () -> Void
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("claudePath") private var claudePath = ""
    @AppStorage("geminiPath") private var geminiPath = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var selectedPage: SettingsPage = .general
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.line).frame(width: 1)
            Group {
            switch selectedPage {
            case .general:
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
            }
            .formStyle(.grouped)
            case .notch:
            Form {
            Section(L("화면", "Display")) {
                LabeledContent(L("현재 위치", "Current display"), value: model.displayName)
                Text(model.hasPhysicalNotch ? L("실제 카메라 노치 위치에 정렬됨 · 메뉴바 높이와 카메라 폭 자동 감지", "Aligned to the camera notch · menu bar height and camera width detected") : L("활성 화면에서 실제 노치를 감지하지 못했습니다. 맥북 내장 화면이 활성화되면 자동으로 노치로 이동합니다.", "No camera notch on the active display. NotchAgent moves to the notch when the built-in display is active."))
                    .font(.caption).foregroundStyle(model.hasPhysicalNotch ? Color.secondary : .orange)
                Picker(L("표시 화면", "Display"), selection: $model.preferredDisplay) {
                    Text(L("내장 노치 화면 우선", "Built-in notch display first")).tag("builtin")
                    Text(L("열 때 마우스가 있는 화면", "Display with the pointer")).tag("pointer")
                }.onChange(of: model.preferredDisplay) { _, _ in displayChanged() }
            }
            Section(L("열기와 접기", "Opening and closing")) {
                Toggle(L("마우스를 올리면 미리보기", "Preview on hover"), isOn: $model.hoverEnabled)
                Picker(L("호버 반응 속도", "Hover delay"), selection: $model.hoverSpeed) {
                    ForEach(HoverSpeed.allCases) { Text($0.label).tag($0) }
                }.disabled(!model.hoverEnabled)
                Toggle(L("다른 앱을 클릭하면 자동으로 접기", "Collapse when switching to another app"), isOn: $model.collapseOnDeactivate)
                Text(L("접혀도 터미널과 에이전트는 계속 실행됩니다.", "Terminal and agent sessions keep running while collapsed."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("표시 내용", "Content")) {
                Picker(L("큰 화면 크기", "Terminal size"), selection: $model.terminalSize) {
                    ForEach(TerminalSize.allCases) { Text($0.name).tag($0) }
                }
            }
            Section(L("최소화 화면", "Collapsed notch")) {
                Toggle(L("쉬는 동안 사용량 표시", "Show usage while idle"), isOn: $model.quietNotchShowsUsage)
                Toggle(L("작업 중 표시", "Show ongoing work"), isOn: $model.notchShowsWorking)
                Toggle(L("작업 중인 개수 표시", "Show working session count"), isOn: $model.notchShowsWorkCount)
                    .disabled(!model.notchShowsWorking)
                Text(L("작업 중이 아니면 사용량을 표시합니다. 완료·확인 요청의 표시 방식은 알림 페이지에서 선택하세요.", "Usage appears when no work is running. Choose completion and input request delivery on the Alerts page."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
            case .alerts:
            Form {
            Section(L("이벤트별 알림", "Event delivery")) {
                NotificationRoutingView(model: model)
                Text(L("이벤트마다 받을 위치를 선택하세요. 노치 알림은 약 6초 뒤 사라집니다. 모든 알림을 꺼도 최근 활동에는 기록됩니다.", "Choose where each event appears. Notch notices disappear after about six seconds. Events still appear in Recent Activity when delivery is off."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("알림 센터와 개인정보", "Notification Center and privacy")) {
                Toggle(L("macOS 알림에 작업 제목·폴더 표시", "Show task title and folder in macOS notifications"), isOn: $model.showNotificationDetails)
                    .disabled(!model.systemNotificationsEnabled)
                if let message = model.notificationPermissionMessage, model.systemNotificationsEnabled {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
            Section(L("최근 활동", "Recent activity")) {
                Toggle(L("최근 활동을 재실행 후에도 보관", "Keep recent activity after relaunch"), isOn: $model.keepRecentActivities)
                Text(L("최근 활동은 최대 50개를 기기에 24시간 저장합니다. 보관을 끄면 저장본을 삭제합니다. 알림 센터·소리·상세 내용은 기본 꺼짐입니다.", "Up to 50 events are stored locally for 24 hours. Disabling retention deletes the saved copy. Notification Center, sound, and details are off by default."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
            case .appearance:
            Form {
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
            }
            .formStyle(.grouped)
            case .agents:
            Form {
            Section(L("세션", "Sessions")) {
                Toggle(L("다시 열 때 세션 복원", "Restore sessions on relaunch"), isOn: $model.restoreSessions)
                Text(L("탭을 복원하고 열 때 시작합니다. Claude·Codex는 저장된 대화 ID가 있으면 같은 대화를 이어가고, 없으면 폴더의 마지막 대화로 이어질 수 있습니다. 미제출 입력과 실행 중인 프로세스는 복원하지 않습니다.", "Restores tabs and starts them when opened. Claude and Codex resume a saved conversation ID when available; otherwise they may continue the folder's latest conversation. Drafts and running processes aren't restored."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                pathField("Codex", text: $codexPath, kind: .codex)
                pathField("Claude", text: $claudePath, kind: .claude)
                pathField("Gemini", text: $geminiPath, kind: .gemini)
            } header: { Text(L("CLI 실행 파일", "CLI executables")) } footer: {
                Text(L("비워두면 Homebrew와 일반 설치 경로에서 찾습니다. 설치와 로그인은 각 CLI에서 진행하세요. API 키를 NotchAgent에 입력하지 않습니다.", "Leave empty to search Homebrew and common install paths. Install and sign in with each CLI; never enter API keys into NotchAgent."))
            }
            Section(L("사용량", "Usage")) {
                Toggle(L("Codex 계정 사용량 조회", "Show Codex account usage"), isOn: Binding(get: { model.usage.enabled }, set: { model.usage.setEnabled($0) }))
                if model.usage.enabled {
                    UsageReadingStatus(agent: .codex, snapshot: model.usage.snapshot, loading: model.usage.isLoading,
                                       error: model.usage.error, refresh: { model.usage.refresh() })
                }
                Text(L("기존 Codex CLI의 읽기 전용 계정 조회를 사용합니다. 5분마다 갱신하며, 구독 한도와 누적 토큰은 서로 다른 값입니다.", "Uses the Codex CLI's read-only account query, every 5 minutes. Subscription limits and lifetime tokens are different numbers."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.usage.enabled, let snapshot = model.usage.snapshot {
                    LabeledContent(L("Codex 마지막 갱신", "Codex last updated"), value: snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                    if let tokens = snapshot.lifetimeTokens { LabeledContent(L("CLI가 보고한 누적 토큰", "Lifetime tokens reported by the CLI"), value: tokens.formatted()) }
                }
                Toggle(L("Claude 계정 사용량 표시", "Show Claude account usage"), isOn: Binding(get: { model.claudeUsage.enabled }, set: { model.claudeUsage.setEnabled($0) }))
                if model.claudeUsage.enabled {
                    UsageReadingStatus(agent: .claude, snapshot: model.claudeUsage.snapshot, refresh: { model.claudeUsage.reload() })
                }
                Text(L("NotchAgent에서 새로 여는 Claude Code 세션이 보고하는 5시간·주간 한도를 표시합니다(Pro/Max, 첫 응답 이후). 로그인 정보는 읽지 않으며, 기존 상태 표시줄 설정은 그대로 동작합니다.", "Shows the 5-hour and weekly limits reported by Claude Code sessions you open in NotchAgent (Pro/Max, after the first response). Sign-in data is never read, and your own status line keeps working."))
                    .font(.caption).foregroundStyle(.secondary)
                if model.claudeUsage.enabled, let snapshot = model.claudeUsage.snapshot {
                    LabeledContent(L("Claude 마지막 갱신", "Claude last updated"), value: snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section(L("프로젝트 활동", "Project activity")) {
                Toggle(L("GitHub PR·검사 상태 조회", "Show GitHub PR and check status"), isOn: Binding(get: { model.repositoryStatus.githubEnabled }, set: { model.repositoryStatus.githubEnabled = $0 }))
                Text(L("홈에서 현재 브랜치의 열린 PR과 검사를 조회합니다. 설치된 gh의 기존 로그인을 사용하며, 저장소를 변경하지 않습니다.", "Reads the current branch's open PR and checks on Home using your existing gh sign-in. Does not modify repositories."))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("프로젝트별 에이전트 응답 기록", "Record agent replies by project"), isOn: $model.projectActivityEnabled)
                Button {
                    model.importPastActivity()
                } label: {
                    Label(L("현재 프로젝트의 과거 대화 가져오기", "Import past conversations for this project"), systemImage: "arrow.down.to.line")
                }
                .disabled(!model.projectActivityEnabled || model.projectImportRunning)
                if model.projectImportRunning { ProgressView(L("로컬 대화를 확인하는 중…", "Checking local conversations…")) }
                if let message = model.projectImportMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                Text(L("Codex·Claude의 로컬 완료 기록을 읽어 날짜별 횟수만 저장합니다. 과거 기록은 추정치이며, 프롬프트·출력·토큰은 저장하지 않습니다. 기록을 끄면 가져온 횟수도 즉시 삭제합니다.", "Reads local Codex and Claude completion records and saves daily counts only. Past counts are estimates; prompts, output and tokens are not stored. Turning recording off also deletes imported counts."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("개인정보", "Privacy")) {
                Text(L("터미널 내용·API 키는 저장하거나 별도 서버로 전송하지 않습니다. 실행한 CLI 자체의 네트워크·파일 접근은 해당 CLI의 정책을 따릅니다.", "Terminal content and API keys are never stored or sent anywhere. Network and file access by the CLIs you run follows their own policies."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
            case .about:
            Form {
            Section(L("앱", "Application")) {
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label(L("앱 종료", "Quit App"), systemImage: "power")
                }
                Text(L("앱을 종료하면 열려 있는 터미널과 에이전트 세션도 종료됩니다.", "Quitting the app also ends open terminal and agent sessions."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("NotchAgent \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · SwiftTerm (MIT)")
                .font(.caption2).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black).foregroundStyle(.white).tint(Palette.mint).preferredColorScheme(.dark)
        .id(model.language) // subviews such as the shortcut recorder re-render in the new language
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label { Text(L("설정", "Settings")) } icon: { Image(systemName: "gearshape").foregroundStyle(Palette.mint) }
                .font(.headline).padding(.horizontal, 12).padding(.bottom, 15)
            ForEach(SettingsPage.allCases, id: \.self) { page in
                Button { selectedPage = page } label: {
                    Label(page.title, systemImage: page.symbol)
                        .font(.subheadline.weight(selectedPage == page ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .foregroundStyle(selectedPage == page ? Color.white : Palette.muted)
                        .background(selectedPage == page ? Color.white.opacity(0.08) : Color.clear)
                        .clipShape(.rect(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.surface)
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
                AppMark(size: 22)
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

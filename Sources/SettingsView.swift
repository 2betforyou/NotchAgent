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
            Section("노치와 터미널") {
                LabeledContent("현재 위치", value: model.displayName)
                Text(model.hasPhysicalNotch ? "실제 카메라 노치 위치에 정렬됨 · 메뉴바 높이와 카메라 폭 자동 감지" : "활성 화면에서 실제 노치를 감지하지 못했습니다. 맥북 내장 화면이 활성화되면 자동으로 노치로 이동합니다.")
                    .font(.caption).foregroundStyle(model.hasPhysicalNotch ? Color.secondary : .orange)
                Toggle("마우스를 올리면 미리보기", isOn: $model.hoverEnabled)
                Picker("호버 반응 속도", selection: $model.hoverSpeed) {
                    ForEach(HoverSpeed.allCases) { Text($0.label).tag($0) }
                }.disabled(!model.hoverEnabled)
                Picker("표시 화면", selection: $model.preferredDisplay) {
                    Text("내장 노치 화면 우선").tag("builtin")
                    Text("열 때 마우스가 있는 화면").tag("pointer")
                }.onChange(of: model.preferredDisplay) { _, _ in displayChanged() }
                HStack {
                    Text("터미널 글자 크기")
                    Slider(value: $model.fontSize, in: 11...20, step: 1)
                    Text("\(Int(model.fontSize)) pt").monospacedDigit().frame(width: 44)
                }
                LabeledContent("열기 / 접기", value: "Control + Option + Space")
                LabeledContent("터미널에서 접기", value: "⌘W · 세션 유지")
                Toggle("로그인 시 실행", isOn: $loginEnabled).onChange(of: loginEnabled) { _, value in
                    // Writing loginEnabled below re-enters this handler; act only on real changes.
                    guard value != (SMAppService.mainApp.status == .enabled) else { return }
                    loginError = nil
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { loginError = error.localizedDescription }
                    if SMAppService.mainApp.status == .requiresApproval {
                        loginError = "시스템 설정 → 일반 → 로그인 항목에서 NotchAgent를 허용하세요."
                    }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.orange) }
            }
            Section {
                pathField("Codex", text: $codexPath, kind: .codex)
                pathField("Claude", text: $claudePath, kind: .claude)
                pathField("Gemini", text: $geminiPath, kind: .gemini)
            } header: { Text("CLI 실행 파일") } footer: {
                Text("비워두면 Homebrew와 일반 설치 경로에서 찾습니다. 설치와 로그인은 각 CLI에서 진행하세요. API 키를 NotchAgent에 입력하지 않습니다.")
            }
            Section("사용량과 개인정보") {
                Toggle("Codex 계정 사용량 조회", isOn: Binding(get: { model.usage.enabled }, set: { model.usage.setEnabled($0) }))
                Text("기존 Codex CLI의 읽기 전용 계정 조회를 사용합니다. 5분마다 갱신하며, 구독 한도와 누적 토큰은 서로 다른 값입니다. Gemini 사용량은 아직 지원하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Claude 계정 사용량 표시", isOn: Binding(get: { model.claudeUsage.enabled }, set: { model.claudeUsage.setEnabled($0) }))
                Text("NotchAgent에서 새로 여는 Claude Code 세션이 보고하는 5시간·주간 한도를 표시합니다(Pro/Max, 첫 응답 이후). 로그인 정보는 읽지 않으며, 기존 상태 표시줄 설정은 그대로 동작합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if let snapshot = model.usage.snapshot {
                    LabeledContent("마지막 갱신", value: snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))
                    if let tokens = snapshot.lifetimeTokens { LabeledContent("CLI가 보고한 누적 토큰", value: tokens.formatted()) }
                }
                Text("터미널 내용·API 키는 저장하거나 별도 서버로 전송하지 않습니다. 실행한 CLI 자체의 네트워크·파일 접근은 해당 CLI의 정책을 따릅니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("NotchAgent 0.1.0 · SwiftTerm (MIT)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).frame(width: 590, height: 580)
    }
    private func pathField(_ title: String, text: Binding<String>, kind: AgentKind) -> some View {
        HStack {
            TextField(title, text: text, prompt: Text("자동 탐색"))
            Image(systemName: model.executable(for: kind) == nil ? "questionmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(model.executable(for: kind) == nil ? Color.secondary : .green)
                .help(model.executable(for: kind) ?? "실행 파일을 찾을 수 없습니다")
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
            Text("화면 위 작은 작업 공간.\n쓰던 터미널과 CLI 에이전트를 그대로 가져오세요.")
                .foregroundStyle(Palette.muted).lineSpacing(5)
            VStack(alignment: .leading, spacing: 15) {
                row("cursorarrow", "올려서 확인", "노치에 마우스를 올리면 미리보기가 열립니다.")
                row("keyboard", "눌러서 작업", "⌃⌥Space로 열고, ⌘W로 접습니다.")
                row("rectangle.stack", "접어도 계속", "세션은 유지됩니다. 앱을 종료하면 작업도 종료됩니다.")
            }
            Spacer(minLength: 0)
            HStack {
                Text("별도 계정 없이 시작 · 사용량 연결은 선택").font(.caption2).foregroundStyle(Palette.muted)
                Spacer()
                Button("시작하기", action: start).buttonStyle(MintButton()).keyboardShortcut(.defaultAction)
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

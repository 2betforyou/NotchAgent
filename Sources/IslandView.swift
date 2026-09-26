import AppKit
import SwiftUI

enum Palette {
    static let mint = Color(red: 0.66, green: 0.96, blue: 0.75)
    static let surface = Color(white: 0.065)
    static let muted = Color(white: 0.62)
    static let line = Color.white.opacity(0.09)
    // Each agent's brand color, used for its usage bars.
    static let codex = Color(red: 0x49 / 255, green: 0xA3 / 255, blue: 0xB0 / 255)   // #49A3B0
    static let claude = Color(red: 0xCC / 255, green: 0x7C / 255, blue: 0x5E / 255)  // #CC7C5E
    static let gemini = Color(red: 0x47 / 255, green: 0x96 / 255, blue: 0xE3 / 255)  // Gemini blue
    /// Low remaining quota. Red rather than orange so it never reads as Claude's color.
    static let low = Color(red: 1.0, green: 0.27, blue: 0.23)  // system red
}

/// Concave upper shoulders visually join the island to the display edge.
struct IslandShape: Shape {
    var shoulder: CGFloat = 12
    var radius: CGFloat = 24
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = min(shoulder, rect.height / 2), r = min(radius, rect.height / 2)
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: s, y: s), control: CGPoint(x: s, y: 0))
        p.addLine(to: CGPoint(x: s, y: rect.height - r))
        p.addQuadCurve(to: CGPoint(x: s + r, y: rect.height), control: CGPoint(x: s, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width - s - r, y: rect.height))
        p.addQuadCurve(to: CGPoint(x: rect.width - s, y: rect.height - r), control: CGPoint(x: rect.width - s, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width - s, y: s))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0), control: CGPoint(x: rect.width - s, y: 0))
        p.closeSubpath()
        return p
    }
}

private struct PreviewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct IslandView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var width: CGFloat {
        switch model.phase {
        case .closed: model.compactWidth
        case .preview: min(570, model.panelWidth)
        case .terminal: model.panelWidth
        }
    }
    private var height: CGFloat {
        switch model.phase {
        case .closed: model.notchHeight
        case .preview: model.previewHeight
        case .terminal: model.panelHeight
        }
    }
    var body: some View {
        ZStack(alignment: .top) {
            IslandShape(shoulder: model.phase == .closed ? 6 : 14, radius: model.phase == .closed ? 12 : 26)
                .fill(.black)
                .shadow(color: .black.opacity(model.phase == .closed ? 0 : 0.3), radius: 12, y: 8)
            if model.phase == .closed {
                compact
            } else {
                VStack(spacing: 0) {
                    // Reserve the physical camera housing; no controls render underneath it.
                    Color.clear.frame(height: model.notchHeight + 4)
                    if let error = model.lastError { errorBanner(error).padding(.bottom, 10) }
                    if model.phase == .preview { preview }
                    else { terminalPanel }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 18)
                // The preview is exactly as tall as its content (no dead space below the footer).
                .fixedSize(horizontal: false, vertical: model.phase == .preview)
                .background {
                    if model.phase == .preview {
                        GeometryReader { geo in
                            Color.clear.preference(key: PreviewHeightKey.self, value: geo.size.height)
                        }
                    }
                }
                .onPreferenceChange(PreviewHeightKey.self) { height in
                    if height > 0, abs(height - model.previewContentHeight) > 0.5 { model.previewContentHeight = height }
                }
                .transition(.opacity)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.87), value: model.phase)
        .frame(width: model.panelWidth + 32, height: model.panelHeight + 32, alignment: .top)
        .foregroundStyle(.white)
        .tint(Palette.mint)
        .preferredColorScheme(.dark)
    }
    private var compact: some View {
        Button { model.showTerminal?() } label: {
            HStack {
                Image(systemName: "terminal.fill").font(.caption).foregroundStyle(Palette.mint)
                Spacer(minLength: 0)
                if model.lastError != nil {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange)
                }
                if model.runningCount > 0 {
                    Text("\(model.runningCount)").font(.caption.monospacedDigit().bold())
                    Circle().fill(Palette.mint).frame(width: 5, height: 5)
                } else {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.horizontal, 19)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("NotchAgent 열기, 실행 중인 세션 \(model.runningCount)개")
    }
    /// Inline instead of an alert: modal UI attached to this always-on-top panel can end up hidden.
    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.lastError = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).help("닫기").accessibilityLabel("오류 메시지 닫기")
        }
        .padding(10).background(Color.orange.opacity(0.14)).clipShape(.rect(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }
    private var brand: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill").foregroundStyle(Palette.mint)
            Text("NotchAgent").font(.headline)
            Spacer()
            Text("⌃⌥SPACE").font(.caption2.monospaced()).foregroundStyle(Palette.muted)
            Button { model.showSettings?() } label: { Image(systemName: "gearshape") }
                .buttonStyle(QuietButton()).help("설정").accessibilityLabel("설정")
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            brand
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.runningCount == 0 ? "작업은 가까이. 화면은 여유롭게." : "\(model.runningCount)개의 세션이 열려 있어요.")
                        .font(.title3.weight(.semibold))
                    Text(model.selected.map { $0.kind.name + " · " + $0.initialDirectory.lastPathComponent } ?? "터미널과 에이전트를 노치에서 바로.")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Button { model.showTerminal?() } label: {
                    Label(model.sessions.isEmpty ? "시작하기" : "터미널 열기", systemImage: "arrow.up.right")
                }.buttonStyle(MintButton())
            }
            UsageStrip(service: model.usage, compact: false, showsAgent: model.claudeUsage.enabled)
            if model.claudeUsage.enabled { ClaudeUsageStrip(service: model.claudeUsage, compact: false) }
            HStack(spacing: 8) {
                ForEach(AgentKind.allCases) { kind in
                    Button { model.launch(kind) } label: {
                        HStack(spacing: 6) {
                            if kind == .shell { Image(systemName: kind.symbol) } else { AgentLogo(kind: kind, size: 13) }
                            Text(kind == .claude ? "Claude" : kind.name)
                            Circle().fill(model.executable(for: kind) == nil ? Palette.muted : Palette.mint).frame(width: 4, height: 4)
                        }
                        .font(.caption.weight(.medium)).frame(maxWidth: .infinity)
                    }.buttonStyle(QuietButton())
                }
            }
            HStack {
                Image(systemName: "folder")
                Text(model.workspaceName).lineLimit(1)
                Spacer()
                Text("클릭해서 입력 · ⌘W로 접기")
            }.font(.caption2).foregroundStyle(Palette.muted)
        }
    }
    private var terminalPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "terminal.fill").foregroundStyle(Palette.mint)
                Text("NotchAgent").font(.headline)
                Rectangle().fill(Palette.line).frame(width: 1, height: 15).padding(.horizontal, 4)
                WorkspaceBar(model: model)
                Button { model.showSettings?() } label: { Image(systemName: "gearshape") }.buttonStyle(QuietButton()).help("설정").accessibilityLabel("설정")
                Button { model.collapse?() } label: { Image(systemName: "chevron.up") }.buttonStyle(QuietButton()).help("접기 · ⌘W").accessibilityLabel("노치 접기")
            }
            if model.visibleSessions.isEmpty {
                launchPad
            } else {
                tabs
                if let session = model.selected {
                    ZStack(alignment: .bottom) {
                        EmbeddedTerminal(session: session, fontSize: model.fontSize)
                            .id(session.id)
                            .padding(10)
                            .background(Color(red: 0.035, green: 0.04, blue: 0.045))
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) }
                        if session.ended {
                            HStack {
                                Image(systemName: session.exitCode == 0 ? "checkmark.circle" : "exclamationmark.circle")
                                Text("세션 종료" + (session.exitCode.map { " · 코드 \($0)" } ?? ""))
                                Spacer()
                                Button("새 세션") { model.launch(session.kind) }.buttonStyle(QuietButton())
                            }.font(.caption).padding(12).background(Palette.surface).clipShape(.rect(cornerRadius: 10)).padding(8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transaction { $0.animation = nil }
                }
            }
            if model.claudeUsage.enabled {
                CombinedUsageStrip(codex: model.usage, claude: model.claudeUsage)
            } else {
                UsageStrip(service: model.usage, compact: true)
            }
            HStack {
                Circle().fill(model.selected?.ended == false ? Palette.mint : Palette.muted).frame(width: 5, height: 5)
                Text(model.selected?.ended == false ? "세션 연결됨" : "준비됨")
                Spacer()
                Text("Esc는 터미널로 전달됩니다").foregroundStyle(Palette.muted)
                Text("⌘W 접기").foregroundStyle(Palette.mint)
            }.font(.caption2)
        }
    }
    private var tabs: some View {
        HStack(spacing: 10) {
            FadingHScroll(target: model.selectedID) {
                HStack(spacing: 6) {
                    ForEach(model.visibleSessions) { session in
                        HStack(spacing: 7) {
                            Button { model.select(session) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(session.ended ? Palette.muted : Palette.mint).frame(width: 5, height: 5)
                                    Text(session.kind.name).fontWeight(.semibold)
                                    Text(session.initialDirectory.lastPathComponent).foregroundStyle(Palette.muted).lineLimit(1)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .accessibilityLabel("\(session.kind.name) 세션, \(session.initialDirectory.lastPathComponent)" + (session.ended ? ", 종료됨" : ""))
                            .accessibilityAddTraits(model.selectedID == session.id ? .isSelected : [])
                            Button { model.closeSession(session) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                .buttonStyle(.plain).help("세션 종료").accessibilityLabel("\(session.kind.name) 세션 종료")
                        }
                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 8)
                        .background(model.selectedID == session.id ? Color.white.opacity(0.1) : .clear)
                        .clipShape(.rect(cornerRadius: 8))
                        .id(session.id)
                    }
                }
            }
            newSessionButtons
        }.frame(height: 32)
    }
    /// New sessions in the current folder, right beside its tabs.
    private var newSessionButtons: some View {
        HStack(spacing: 6) {
            ForEach(AgentKind.allCases) { kind in
                let available = model.executable(for: kind) != nil
                Button { model.launch(kind) } label: {
                    HStack(spacing: 5) {
                        if kind == .shell { Image(systemName: kind.symbol) } else { AgentLogo(kind: kind, size: 12) }
                        Text(kind == .claude ? "Claude" : kind == .gemini ? "Gemini" : kind.name)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(available ? Color.white : Palette.muted)
                }
                .buttonStyle(QuietButton())
                .help("새 \(kind.name) 세션" + (available ? "" : " · 실행 파일을 찾을 수 없음"))
                .accessibilityLabel("새 \(kind.name) 세션")
            }
        }
    }
    private var launchPad: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                Text("A little space.\nFor your next big thing.")
                    .font(.largeTitle.weight(.semibold)).tracking(-0.9)
                Text("익숙한 CLI, 당신의 설정 그대로.\n작업 폴더를 고르고 에이전트를 시작하세요.")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
            }
            HStack(spacing: 10) {
                ForEach(AgentKind.allCases) { kind in
                    Button { model.launch(kind) } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                if kind == .shell {
                                    Image(systemName: kind.symbol).font(.title3).foregroundStyle(Palette.mint)
                                        .frame(height: 22) // same row height as the agent logos
                                } else {
                                    AgentLogo(kind: kind, size: 22)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").foregroundStyle(Palette.muted)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.name).font(.headline)
                                Text(model.executable(for: kind) != nil ? "실행 가능" : "경로 설정 필요")
                                    .font(.caption2).foregroundStyle(Palette.muted)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.surface).clipShape(.rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line) }
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 14).frame(maxHeight: .infinity)
    }
}

struct UsageStrip: View {
    let service: UsageService
    let compact: Bool
    var showsAgent = false
    var body: some View {
        Group {
            if !service.enabled {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis").foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Codex 사용량 연결").font(.caption.weight(.semibold))
                        if !compact { Text("기존 CLI 로그인으로 남은 한도를 확인합니다.").font(.caption2).foregroundStyle(Palette.muted) }
                    }
                    Spacer()
                    Button("연결") { service.setEnabled(true) }.buttonStyle(QuietButton())
                }
            } else if let snapshot = service.snapshot {
                UsageWindowsRow(agent: showsAgent ? .codex : nil, tint: Palette.codex, snapshot: snapshot, compact: compact,
                                warning: service.error != nil || snapshot.isStale ? "마지막 성공한 조회 값입니다. " + (service.error ?? "갱신이 필요합니다.") : nil) {
                    refreshButton
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: service.isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.circle").foregroundStyle(Palette.muted)
                    Text(service.isLoading ? "Codex 사용량을 확인하는 중…" : service.error ?? "사용량을 연결하세요")
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(compact ? 1 : 2)
                        .help(service.error ?? "")
                    Spacer()
                    refreshButton
                }
            }
        }
        .padding(compact ? 10 : 14)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: compact ? 9 : 12))
    }
    private var refreshButton: some View {
        Button { service.refresh() } label: {
            Image(systemName: "arrow.clockwise").font(.caption)
        }.buttonStyle(.plain).disabled(service.isLoading).help("사용량 새로고침").accessibilityLabel("사용량 새로고침")
    }
}

/// Same look as the Codex strip. Shown only after Claude usage is turned on in Settings.
struct ClaudeUsageStrip: View {
    let service: ClaudeUsageService
    let compact: Bool
    var body: some View {
        Group {
            if let snapshot = service.snapshot {
                UsageWindowsRow(agent: .claude, updatedAt: snapshot.fetchedAt, tint: Palette.claude, snapshot: snapshot, compact: compact,
                                warning: Date().timeIntervalSince(snapshot.fetchedAt) > 3600
                                    ? "Claude 세션에서 마지막으로 받은 값입니다(\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))). 새 응답이 오면 갱신됩니다." : nil) {
                    RefreshButton(help: ClaudeUsageService.refreshHelp) { service.reload() }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.muted)
                    Text("Claude 사용량은 NotchAgent에서 연 Claude 세션의 첫 응답 후 표시됩니다.")
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(compact ? 1 : 2)
                    Spacer()
                    RefreshButton(help: ClaudeUsageService.refreshHelp) { service.reload() }
                }
            }
        }
        .padding(compact ? 10 : 14)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: compact ? 9 : 12))
    }
}

/// Terminal footer when Claude usage is on: every agent on one line.
struct CombinedUsageStrip: View {
    let codex: UsageService
    let claude: ClaudeUsageService
    var body: some View {
        HStack(spacing: 18) {
            codexSegment
            Rectangle().fill(Palette.line).frame(width: 1, height: 14)
            claudeSegment
            Spacer(minLength: 0)
            RefreshButton(help: "Codex 사용량을 다시 조회합니다. " + ClaudeUsageService.refreshHelp) { codex.refresh(); claude.reload() }
                .disabled(codex.isLoading)
        }
        .padding(10)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 9))
    }
    @ViewBuilder private var codexSegment: some View {
        if let snapshot = codex.snapshot, codex.enabled {
            UsageWindowsRow(agent: .codex, tint: Palette.codex, snapshot: snapshot, compact: true,
                            warning: codex.error != nil || snapshot.isStale ? "마지막 성공한 조회 값입니다. " + (codex.error ?? "갱신이 필요합니다.") : nil,
                            fills: false) { EmptyView() }
        } else {
            HStack(spacing: 8) {
                AgentBadge(kind: .codex, stacked: false)
                if !codex.enabled {
                    Button("연결") { codex.setEnabled(true) }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.codex)
                } else {
                    Text(codex.isLoading ? "확인하는 중…" : codex.error ?? "사용량 없음")
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(1).help(codex.error ?? "")
                }
            }
        }
    }
    @ViewBuilder private var claudeSegment: some View {
        if let snapshot = claude.snapshot {
            UsageWindowsRow(agent: .claude, tint: Palette.claude, snapshot: snapshot, compact: true,
                            warning: Date().timeIntervalSince(snapshot.fetchedAt) > 3600
                                ? "Claude 세션에서 마지막으로 받은 값입니다. 새 응답이 오면 갱신됩니다." : nil,
                            fills: false) { EmptyView() }
        } else {
            HStack(spacing: 8) {
                AgentBadge(kind: .claude, stacked: false)
                Text("첫 응답 후 표시").font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    .help("NotchAgent에서 연 Claude 세션이 첫 응답을 받으면 표시됩니다 (Pro/Max).")
            }
        }
    }
}

/// The original Codex quota row, shared so Claude looks identical.
struct UsageWindowsRow<Trailing: View>: View {
    let agent: AgentKind?
    var updatedAt: Date? = nil
    let tint: Color
    let snapshot: UsageSnapshot
    let compact: Bool
    let warning: String?
    var fills = true
    @ViewBuilder let trailing: () -> Trailing
    var body: some View {
        HStack(spacing: compact ? 22 : 16) {
            if let agent { AgentBadge(kind: agent, stacked: !compact, updatedAt: updatedAt) }
            ForEach(snapshot.windows) { window in
                if compact {
                    HStack(spacing: 7) {
                        Text(window.title).foregroundStyle(Palette.muted)
                        Text("\(Int(window.remaining))% 남음").foregroundStyle(window.remaining <= 20 ? Palette.low : tint)
                    }.font(.caption.monospacedDigit())
                        .help(window.resetLabel())
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(window.title).foregroundStyle(Palette.muted)
                            Spacer()
                            Text("\(Int(window.remaining))% 남음").monospacedDigit().fontWeight(.semibold)
                        }.font(.caption)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(window.remaining <= 20 ? Palette.low : tint)
                                    .frame(width: geo.size.width * window.remaining / 100)
                            }
                        }.frame(height: 4)
                        Text(window.resetLabel()).font(.caption2).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity)
                }
            }
            if compact && fills { Spacer(minLength: 0) }
            if let warning {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange).help(warning)
            }
            trailing()
        }
    }
}

/// Work folders, Orca-sidebar style but inline: switch folders, see which ones have agents
/// running, add and manage folders. The active chip looks like the original folder button.
struct WorkspaceBar: View {
    @Bindable var model: AppModel
    var body: some View {
        let labels = Workspaces.labels(model.workspaces)
        FadingHScroll(target: model.workspacePath) {
            HStack(spacing: 4) {
                ForEach(model.workspaces) { workspace in
                    chip(workspace, label: labels[workspace.path] ?? workspace.name).id(workspace.path)
                }
                Button { model.addWorkspace() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(QuietButton()).help("작업 폴더 추가").accessibilityLabel("작업 폴더 추가")
                    .padding(.leading, 2)
            }
        }
    }
    private func chip(_ workspace: SavedWorkspace, label: String) -> some View {
        let active = workspace.path == model.workspacePath
        let running = model.runningCount(in: workspace.path)
        let exists = workspace.exists
        let branch = Workspaces.gitBranch(at: workspace.path)
        return Button { model.activateWorkspace(workspace.path) } label: {
            HStack(spacing: 6) {
                Image(systemName: exists ? "folder" : "questionmark.folder")
                Text(label).lineLimit(1)
                if running > 0 {
                    Text("\(running)").font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Palette.mint))
                }
            }
            .foregroundStyle(active ? Color.white : exists ? Palette.muted : Color.orange)
        }
        .buttonStyle(WorkspaceChipStyle(active: active))
        .help(workspace.path + (branch.map { " · " + $0 } ?? "") + (exists ? "" : " · 폴더를 찾을 수 없음"))
        .accessibilityLabel("작업 폴더 \(label)" + (running > 0 ? ", 실행 중인 세션 \(running)개" : "") + (exists ? "" : ", 폴더 없음"))
        .accessibilityAddTraits(active ? .isSelected : [])
        .contextMenu {
            ForEach(AgentKind.allCases) { kind in
                Button { model.activateWorkspace(workspace.path); model.launch(kind) } label: {
                    Label { Text("여기서 새 \(kind.name) 세션") } icon: { AgentLogo.menuIcon(kind) }
                }
            }
            Divider()
            Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)]) }
                .disabled(!exists)
            Button("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(workspace.path, forType: .string)
            }
            Divider()
            Button("목록에서 제거") { model.removeWorkspace(workspace.path) }
                .disabled(model.workspaces.count < 2)
        }
    }
}

struct WorkspaceChipStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 9).padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.14 : active ? 0.055 : 0))
            .clipShape(.rect(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}

/// Refresh icon that turns once per press, so a refresh with unchanged numbers still reads as done.
struct RefreshButton: View {
    let help: String
    let action: () -> Void
    @State private var turns = 0.0
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) { turns += 1 }
            action()
        } label: {
            Image(systemName: "arrow.clockwise").font(.caption).rotationEffect(.degrees(turns * 360))
        }
        .buttonStyle(.plain).help(help).accessibilityLabel("사용량 새로고침")
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 9).padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.055))
            .clipShape(.rect(cornerRadius: 7))
    }
}
struct MintButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(.black).background(Palette.mint.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(.rect(cornerRadius: 10))
    }
}

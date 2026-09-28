import AppKit
import SwiftUI

enum Palette {
    /// The accent the user picked (mint by default); the name is kept from the original design.
    static var mint: Color { Accent.current.color }
    static let surface = Color(white: 0.065)
    static let muted = Color(white: 0.62)
    static let line = Color.white.opacity(0.09)
    // Each agent's brand color, used for its usage bars.
    static let codex = Color(red: 0x49 / 255, green: 0xA3 / 255, blue: 0xB0 / 255)   // #49A3B0
    static let claude = Color(red: 0xCC / 255, green: 0x7C / 255, blue: 0x5E / 255)  // #CC7C5E
    static let gemini = Color(red: 0x47 / 255, green: 0x96 / 255, blue: 0xE3 / 255)  // Gemini blue
    /// Low remaining quota. Red rather than orange so it never reads as Claude's color.
    static let low = Color(red: 1.0, green: 0.27, blue: 0.23)  // system red
    /// A session asks for the user (approval, question).
    static let attention = Color(red: 1.0, green: 0.78, blue: 0.32)
    /// A session finished its work.
    static let done = Color(red: 0.30, green: 0.85, blue: 0.45)
    static func color(for reason: AttentionReason) -> Color {
        switch reason {
        case .finished: done
        case .bell: attention
        case .exited: muted
        case .failed: low
        }
    }
}

/// One motion language for the whole app, tuned to feel like the Dynamic Island: the island
/// itself moves on a slightly bouncy spring, smaller parts on a quicker, calmer one.
enum Motion {
    /// Opening, closing and resizing the island.
    static let island = Animation.spring(response: 0.42, dampingFraction: 0.76)
    /// Selections, chips, tabs, counters, bars.
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.84)
    /// Content fading in once the island has made room for it.
    static let content = Animation.easeOut(duration: 0.26).delay(0.07)
}

extension View {
    /// Animates `value` changes with `animation`, or not at all when Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation, value: V, reduce: Bool) -> some View {
        self.animation(reduce ? nil : animation, value: value)
    }
}

/// Concave upper shoulders visually join the island to the display edge.
struct IslandShape: Shape {
    var shoulder: CGFloat = 12
    var radius: CGFloat = 24
    // Corners and shoulders morph with the island instead of snapping.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, radius) }
        set { shoulder = newValue.first; radius = newValue.second }
    }
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
    @Namespace private var tabHighlight
    @State private var draggedTab: UUID?
    private var width: CGFloat {
        switch model.phase {
        case .closed: model.closedWidth
        case .preview: min(570, model.panelWidth)
        case .terminal: model.panelWidth
        }
    }
    private var height: CGFloat {
        switch model.phase {
        case .closed: model.closedHeight
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
                compact.modifier(FolderDropTarget(model: model))
                    .transition(AnyTransition(.blurReplace).animation(reduceMotion ? nil : Motion.content))
            } else {
                VStack(spacing: 0) {
                    // The top row sits in the menu bar band; only the camera housing stays empty.
                    topRow.modifier(FolderDropTarget(model: model)).padding(.bottom, 10)
                    if let error = model.lastError {
                        errorBanner(error).padding(.bottom, 10).transition(.move(edge: .top).combined(with: .opacity))
                    }
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
                .transition(.asymmetric(
                    // Content materializes just after the island opens, and dissolves quickly.
                    insertion: AnyTransition(.blurReplace).combined(with: .scale(scale: 0.96, anchor: .top))
                        .animation(reduceMotion ? nil : Motion.content),
                    removal: .opacity.animation(.easeIn(duration: 0.1))))
            }
        }
        .id("\(model.accent.rawValue)-\(model.language.rawValue)") // re-render every color and string
        .frame(width: width, height: height, alignment: .top)
        .motion(Motion.island, value: model.phase, reduce: reduceMotion)
        .motion(Motion.island, value: model.banner, reduce: reduceMotion)
        .motion(Motion.island, value: model.previewContentHeight, reduce: reduceMotion)
        .motion(Motion.snappy, value: model.lastError, reduce: reduceMotion)
        .frame(width: model.panelWidth + 32, height: model.hostHeight + 32, alignment: .top)
        .foregroundStyle(.white)
        .tint(Palette.mint)
        .preferredColorScheme(.dark)
    }
    private var compact: some View {
        VStack(spacing: 0) {
            Button { model.showTerminal?() } label: {
                HStack(spacing: 0) {
                    leftWing.frame(width: model.closedWingWidth)
                    Color.clear.frame(width: model.notchGapWidth) // camera housing
                    rightWing.frame(width: model.closedWingWidth)
                }
                .frame(maxWidth: .infinity)
                .frame(height: model.notchHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("NotchAgent 열기, 실행 중인 세션 \(model.runningCount)개", "Open NotchAgent, \(model.runningCount) running session(s)") + (model.attentionCount > 0 ? L(", 확인할 세션 \(model.attentionCount)개", ", \(model.attentionCount) need(s) attention") : ""))
            if let banner = model.banner { bannerRow(banner) }
        }
        .motion(Motion.island, value: model.closedLayout, reduce: reduceMotion)
    }
    /// Who: the agent (one session) or every session nearest the camera first (several).
    @ViewBuilder private var leftWing: some View {
        switch model.closedLayout {
        case .idle: Color.clear
        case .usage(let items):
            if let first = items.first {
                // Two agents: one per side. One agent: gauge here, number on the right.
                if items.count > 1 { UsageBadge(usage: first, showsNumber: true) } else { UsageBadge(usage: first, showsNumber: false) }
            }
        case .single(let id):
            if let session = model.sessions.first(where: { $0.id == id }) { SessionIcon(kind: session.kind, size: 15) }
        case .multi(let left, _):
            HStack(spacing: 4) { ForEach(left, id: \.self) { id in ringedIcon(id) } }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 6)
        }
    }
    /// What: one status symbol (one session), or the rest of the sessions (several).
    @ViewBuilder private var rightWing: some View {
        switch model.closedLayout {
        case .idle:
            if model.lastError != nil { Circle().fill(.orange).frame(width: 6, height: 6) }
        case .usage(let items):
            if items.count > 1 { UsageBadge(usage: items[1], showsNumber: true) }
            else if let only = items.first { UsageBadge.percent(only) }
        case .single: NotchStatusView(status: model.notchStatus)
        case .multi(_, let right):
            HStack(spacing: 4) { ForEach(right, id: \.self) { id in ringedIcon(id) } }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
        }
    }
    @ViewBuilder private func ringedIcon(_ id: UUID) -> some View {
        if let session = model.sessions.first(where: { $0.id == id }) {
            RingedSessionIcon(kind: session.kind, badge: NotchBadge(attention: session.attention, working: session.isWorking))
        }
    }
    private func bannerRow(_ banner: NotchBanner) -> some View {
        Button { model.openBanner() } label: {
            HStack(spacing: 8) {
                if banner.kind == .shell {
                    Image(systemName: "terminal.fill").font(.caption).foregroundStyle(Palette.mint)
                } else {
                    AgentLogo(kind: banner.kind, size: 14)
                }
                Text(banner.kind.name).font(.caption.weight(.semibold))
                Text(banner.reason.message).font(.caption).foregroundStyle(Palette.color(for: banner.reason))
                Spacer(minLength: 6)
                Text(banner.folder).font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
            }
            .padding(.horizontal, 24)
            .frame(height: 30, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityLabel(L("\(banner.kind.name) \(banner.reason.message), \(banner.folder). 열기", "\(banner.kind.name) \(banner.reason.message), \(banner.folder). Open"))
    }
    /// Inline instead of an alert: modal UI attached to this always-on-top panel can end up hidden.
    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.lastError = nil } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
            }
                .buttonStyle(.plain).help(L("닫기", "Dismiss")).accessibilityLabel(L("오류 메시지 닫기", "Dismiss error"))
        }
        .padding(10).background(Color.orange.opacity(0.14)).clipShape(.rect(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }
    /// Header in the menu bar band, split around the physical notch.
    private var topRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                AppMark(size: 20)
                Text("NotchAgent").font(.headline).lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Nothing is drawn under the camera. Screens without a notch keep only a small gap.
            Color.clear.frame(width: model.hasPhysicalNotch ? model.physicalNotchWidth + 16 : 16)
            HStack(spacing: 8) {
                if model.phase == .preview {
                    Text(model.hotkey.label.uppercased()).font(.caption2.monospaced()).foregroundStyle(Palette.muted)
                }
                Button { model.showSettings?() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(QuietButton()).help(L("설정", "Settings")).accessibilityLabel(L("설정", "Settings"))
                if model.phase == .terminal {
                    Button { model.collapse?() } label: { Image(systemName: "chevron.up") }.buttonStyle(QuietButton())
                        .help(L("접기 · \(model.hotkey.label)", "Close · \(model.hotkey.label)")).accessibilityLabel(L("노치 접기", "Close notch"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: model.notchHeight)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.previewHeadline)
                        .font(.title3.weight(.semibold))
                    Text(model.previewSubtitle)
                        .font(.subheadline).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                Button { model.showTerminal?() } label: {
                    Label(model.visibleSessions.isEmpty ? L("시작하기", "Get Started") : L("터미널 열기", "Open Terminal"), systemImage: "arrow.up.right")
                }.buttonStyle(MintButton())
            }
            QuickPromptField(model: model)
            PreviewUsageSummary(codex: model.usage, claude: model.claudeUsage)
            RecentActivitiesView(model: model)
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
            PreviewFolderFooter(model: model)
        }
        .modifier(FolderDropTarget(model: model))
    }
    private var terminalPanel: some View {
        VStack(spacing: 12) {
            // Folders get the full width below the menu bar band.
            WorkspaceBar(model: model)
            if model.visibleSessions.isEmpty {
                launchPad
            } else {
                tabs
                if let session = model.selected {
                    ZStack(alignment: .bottom) {
                        EmbeddedTerminal(session: session, appearance: model.appearance)
                            .id(session.id)
                            .padding(10)
                            .background(model.terminalTheme.backgroundColor)
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line) }
                        if session.ended {
                            HStack {
                                Image(systemName: session.exitCode == 0 ? "checkmark.circle" : "exclamationmark.circle")
                                Text(L("세션 종료", "End Session") + (session.exitCode.map { L(" · 코드 \($0)", " · code \($0)") } ?? ""))
                                Spacer()
                                Button(L("새 세션", "New Session")) { model.launch(session.kind) }.buttonStyle(QuietButton())
                            }.font(.caption).padding(12).background(Palette.surface).clipShape(.rect(cornerRadius: 10)).padding(8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                Circle().fill(model.selected?.isRunning == true ? Palette.mint : Palette.muted).frame(width: 5, height: 5)
                Text(model.selected?.isRunning == true ? L("세션 연결됨", "Session connected") : L("준비됨", "Ready"))
                Spacer()
                Text(L("Esc는 터미널로 전달됩니다", "Esc goes to the terminal")).foregroundStyle(Palette.muted)
                Text(L("\(model.hotkey.label) 접기", "\(model.hotkey.label) to close")).foregroundStyle(Palette.mint)
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
                                    Circle().fill(session.attention.map(Palette.color(for:)) ?? (session.isRunning ? Palette.mint : Palette.muted)).frame(width: 5, height: 5)
                                    if session.kind == .shell {
                                        Image(systemName: "terminal").foregroundStyle(Palette.muted)
                                    } else { AgentLogo(kind: session.kind, size: 12) }
                                    Text(session.displayTitle).fontWeight(.semibold).lineLimit(1)
                                        .truncationMode(.middle).frame(maxWidth: 220)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.renameSession(session) })
                            .help("\(session.kind.name) · \(session.displayTitle)\n\(session.initialDirectory.path)\n" + L("더블클릭하여 이름 변경", "Double-click to rename"))
                            .accessibilityLabel("\(session.kind.name), \(session.displayTitle), \(session.initialDirectory.lastPathComponent)" + (session.ended ? L(", 종료됨", ", ended") : ""))
                            .accessibilityAddTraits(model.selectedID == session.id ? .isSelected : [])
                            Button { model.closeSession(session) } label: {
                                Image(systemName: "xmark").font(.system(size: 9)).frame(width: 16, height: 16).contentShape(Rectangle())
                            }
                                .buttonStyle(.plain).help(L("세션 종료", "End Session")).accessibilityLabel(L("\(session.kind.name) 세션 종료", "End \(session.kind.name) session"))
                        }
                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 8)
                        .background {
                            // One highlight that slides from tab to tab.
                            if model.selectedID == session.id {
                                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1))
                                    .matchedGeometryEffect(id: "selectedTab", in: tabHighlight)
                            }
                        }
                        .id(session.id)
                        .contextMenu {
                            Button(L("이름 변경…", "Rename…")) { model.renameSession(session) }
                            if session.customTitle != nil {
                                Button(L("터미널 제목 사용", "Use Terminal Title")) { model.setSessionName(session, name: nil) }
                            }
                        }
                        .opacity(draggedTab == session.id ? 0.55 : 1)
                        .reorderable(session.id, dragging: $draggedTab) { model.moveSession($0, onto: $1) }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .motion(Motion.snappy, value: model.selectedID, reduce: reduceMotion)
                .motion(Motion.snappy, value: model.visibleSessions.map(\.id), reduce: reduceMotion)
            }
            newSessionButtons
        }.frame(height: 32)
    }
    /// New sessions in the current folder, right beside its tabs; one button folds them away.
    private var newSessionButtons: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.snappy) { model.showsNewSessionButtons.toggle() }
            } label: {
                Image(systemName: model.showsNewSessionButtons ? "chevron.right" : "plus")
                    .font(.caption.weight(.semibold)).frame(width: 12)
            }
            .buttonStyle(QuietButton())
            .help(model.showsNewSessionButtons ? L("새 세션 버튼 숨기기", "Hide new session buttons") : L("새 세션 버튼 보기", "Show new session buttons"))
            .accessibilityLabel(model.showsNewSessionButtons ? L("새 세션 버튼 숨기기", "Hide new session buttons") : L("새 세션 버튼 보기", "Show new session buttons"))
            if model.showsNewSessionButtons {
                agentButtons.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
    private var agentButtons: some View {
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
                .help(L("새 \(kind.name) 세션", "New \(kind.name) session") + (available ? "" : L(" · 실행 파일을 찾을 수 없음", " · executable not found")))
                .accessibilityLabel(L("새 \(kind.name) 세션", "New \(kind.name) session"))
            }
        }
    }
    private var launchPad: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                Text("A little space.\nFor your next big thing.")
                    .font(.largeTitle.weight(.semibold)).tracking(-0.9)
                Text(L("익숙한 CLI, 당신의 설정 그대로.\n작업 폴더를 고르고 에이전트를 시작하세요.", "The CLIs you know, with your own settings.\nPick a folder and start an agent."))
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
                                Text(model.executable(for: kind) != nil ? L("실행 가능", "Ready to run") : L("경로 설정 필요", "Set path in Settings"))
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
                        Text(L("Codex 사용량 연결", "Connect Codex usage")).font(.caption.weight(.semibold))
                        if !compact { Text(L("기존 CLI 로그인으로 남은 한도를 확인합니다.", "Shows remaining limits using your existing CLI sign-in.")).font(.caption2).foregroundStyle(Palette.muted) }
                    }
                    Spacer()
                    Button(L("연결", "Connect")) { service.setEnabled(true) }.buttonStyle(QuietButton())
                }
            } else if let snapshot = service.snapshot {
                UsageWindowsRow(agent: showsAgent ? .codex : nil, tint: Palette.codex, snapshot: snapshot, compact: compact,
                                warning: service.error != nil || snapshot.isStale ? L("마지막 성공한 조회 값입니다. ", "Last successful reading. ") + (service.error ?? L("갱신이 필요합니다.", "Needs a refresh.")) : nil) {
                    refreshButton
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: service.isLoading ? "arrow.triangle.2.circlepath" : "exclamationmark.circle").foregroundStyle(Palette.muted)
                    Text(service.isLoading ? L("Codex 사용량을 확인하는 중…", "Checking Codex usage…") : service.error ?? L("사용량을 연결하세요", "Connect usage"))
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
        RefreshButton(help: L("Codex 사용량 새로고침", "Refresh Codex usage")) { service.refresh() }.disabled(service.isLoading)
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
                                    ? L("Claude 세션에서 마지막으로 받은 값입니다(\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))). 새 응답이 오면 갱신됩니다.", "Last value from a Claude session (\(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))). Updates with the next response.") : nil) {
                    RefreshButton(help: ClaudeUsageService.refreshHelp) { service.reload() }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.muted)
                    Text(L("Claude 사용량은 NotchAgent에서 연 Claude 세션의 첫 응답 후 표시됩니다.", "Claude usage appears after the first response in a Claude session opened in NotchAgent."))
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
            RefreshButton(help: L("Codex 사용량을 다시 조회합니다. ", "Re-queries Codex usage. ") + ClaudeUsageService.refreshHelp) { codex.refresh(); claude.reload() }
                .disabled(codex.isLoading)
        }
        .padding(10)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 9))
    }
    @ViewBuilder private var codexSegment: some View {
        if let snapshot = codex.snapshot, codex.enabled {
            UsageWindowsRow(agent: .codex, tint: Palette.codex, snapshot: snapshot, compact: true,
                            warning: codex.error != nil || snapshot.isStale ? L("마지막 성공한 조회 값입니다. ", "Last successful reading. ") + (codex.error ?? L("갱신이 필요합니다.", "Needs a refresh.")) : nil,
                            fills: false) { EmptyView() }
        } else {
            HStack(spacing: 8) {
                AgentBadge(kind: .codex, stacked: false)
                if !codex.enabled {
                    Button(L("연결", "Connect")) { codex.setEnabled(true) }.buttonStyle(.plain).font(.caption).foregroundStyle(Palette.codex)
                } else {
                    Text(codex.isLoading ? L("확인하는 중…", "Checking…") : codex.error ?? L("사용량 없음", "No usage"))
                        .font(.caption).foregroundStyle(Palette.muted).lineLimit(1).help(codex.error ?? "")
                }
            }
        }
    }
    @ViewBuilder private var claudeSegment: some View {
        if let snapshot = claude.snapshot {
            UsageWindowsRow(agent: .claude, tint: Palette.claude, snapshot: snapshot, compact: true,
                            warning: Date().timeIntervalSince(snapshot.fetchedAt) > 3600
                                ? L("Claude 세션에서 마지막으로 받은 값입니다. 새 응답이 오면 갱신됩니다.", "Last value from a Claude session. Updates with the next response.") : nil,
                            fills: false) { EmptyView() }
        } else {
            HStack(spacing: 8) {
                AgentBadge(kind: .claude, stacked: false)
                Text(L("첫 응답 후 표시", "After first reply")).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    .help(L("NotchAgent에서 연 Claude 세션이 첫 응답을 받으면 표시됩니다 (Pro/Max).", "Shown once a Claude session opened in NotchAgent gets its first response (Pro/Max)."))
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
                        Text(L("\(Int(window.remaining))% 남음", "\(Int(window.remaining))% left")).foregroundStyle(window.remaining <= 20 ? Palette.low : tint)
                            .contentTransition(.numericText(value: window.remaining)).animation(Motion.snappy, value: window.remaining)
                    }.font(.caption.monospacedDigit())
                        .help(window.resetLabel())
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(window.title).foregroundStyle(Palette.muted)
                            Spacer()
                            Text(L("\(Int(window.remaining))% 남음", "\(Int(window.remaining))% left")).monospacedDigit().fontWeight(.semibold)
                                .contentTransition(.numericText(value: window.remaining)).animation(Motion.snappy, value: window.remaining)
                        }.font(.caption)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(window.remaining <= 20 ? Palette.low : tint)
                                    .frame(width: geo.size.width * window.remaining / 100)
                                    .animation(Motion.snappy, value: window.remaining)
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

/// Preview footer. The folder name opens the same folder chips as the terminal header, so
/// switching folders looks and behaves identically in both places.
struct PreviewFolderFooter: View {
    @Bindable var model: AppModel
    @State private var choosing: Bool
    init(model: AppModel, choosing: Bool = false) {
        self.model = model
        _choosing = State(initialValue: choosing)
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if choosing {
                HStack(spacing: 6) {
                    WorkspaceBar(model: model)
                    Button { set(false) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                        .buttonStyle(QuietButton())
                        .help(L("닫기", "Close")).accessibilityLabel(L("폴더 선택 닫기", "Close folder picker"))
                }
                .font(.subheadline)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                HStack {
                    Button { set(true) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                            Text(model.workspaceName).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("작업 폴더 전환", "Switch folder"))
                    .accessibilityLabel(L("작업 폴더 \(model.workspaceName), 전환", "Folder \(model.workspaceName), switch"))
                    Spacer()
                    Text(L("클릭해서 열기 · \(model.hotkey.label)", "Click to open · \(model.hotkey.label)"))
                }
                .font(.caption2).foregroundStyle(Palette.muted)
                .transition(.opacity)
            }
        }
        // Picking a folder switches it and folds the chips back into the folder name.
        .onChange(of: model.workspacePath) { _, _ in set(false) }
    }
    private func set(_ value: Bool) {
        withAnimation(reduceMotion ? nil : Motion.snappy) { choosing = value }
    }
}

/// Work folders, Orca-sidebar style but inline: switch folders, see which ones have agents
/// running, add and manage folders. The active chip looks like the original folder button.
struct WorkspaceBar: View {
    @Bindable var model: AppModel
    @Namespace private var chipHighlight
    @State private var draggedFolder: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let labels = Workspaces.labels(model.workspaces)
        FadingHScroll(target: model.workspacePath) {
            HStack(spacing: 4) {
                ForEach(model.workspaces) { workspace in
                    chip(workspace, label: labels[workspace.path] ?? workspace.name).id(workspace.path)
                        .opacity(draggedFolder == workspace.path ? 0.55 : 1)
                        .reorderable(workspace.path, dragging: $draggedFolder) { model.moveWorkspace($0, onto: $1) }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                Button { model.addWorkspace() } label: { Image(systemName: "folder.badge.plus") }
                    .buttonStyle(QuietButton()).help(L("작업 폴더 추가", "Add folder")).accessibilityLabel(L("작업 폴더 추가", "Add folder"))
                    .padding(.leading, 2)
            }
            .motion(Motion.snappy, value: model.workspacePath, reduce: reduceMotion)
            .motion(Motion.snappy, value: model.workspaces, reduce: reduceMotion)
        }
    }
    private func chip(_ workspace: SavedWorkspace, label: String) -> some View {
        let active = workspace.path == model.workspacePath
        let running = model.runningCount(in: workspace.path)
        let exists = workspace.exists
        let branch = Workspaces.gitBranch(at: workspace.path)
        return Button { model.activateWorkspace(workspace.path) } label: {
            HStack(spacing: 6) {
                Image(systemName: !exists ? "questionmark.folder" : Worktree.isLinked(workspace.path) ? "arrow.triangle.branch" : "folder")
                Text(label).lineLimit(1)
                if let reason = model.attention(in: workspace.path) {
                    Circle().fill(Palette.color(for: reason)).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                if running > 0 {
                    Text("\(running)").font(.caption2.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText(value: Double(running)))
                        .foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Palette.mint))
                }
            }
            .foregroundStyle(active ? Color.white : exists ? Palette.muted : Color.orange)
        }
        .buttonStyle(WorkspaceChipStyle(active: active, highlight: chipHighlight))
        .help(workspace.path + (branch.map { " · " + $0 } ?? "") + (exists ? "" : L(" · 폴더를 찾을 수 없음", " · folder not found")))
        .accessibilityLabel(L("작업 폴더 \(label)", "Folder \(label)") + (running > 0 ? L(", 실행 중인 세션 \(running)개", ", \(running) running session(s)") : "") + (exists ? "" : L(", 폴더 없음", ", missing")))
        .accessibilityAddTraits(active ? .isSelected : [])
        .contextMenu {
            ForEach(AgentKind.allCases) { kind in
                Button { model.activateWorkspace(workspace.path); model.launch(kind) } label: {
                    Label { Text(L("여기서 새 \(kind.name) 세션", "New \(kind.name) Session Here")) } icon: { AgentLogo.menuIcon(kind) }
                }
            }
            Divider()
            Button(L("Finder에서 보기", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: workspace.path)]) }
                .disabled(!exists)
            Button(L("경로 복사", "Copy Path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(workspace.path, forType: .string)
            }
            if exists, Worktree.isLinked(workspace.path) {
                Divider()
                Button(L("worktree 제거…", "Remove Worktree…")) { model.removeWorktree(workspace.path) }
            } else if exists, Worktree.isRepository(workspace.path) {
                Divider()
                Button(L("새 worktree 만들기…", "New Worktree…")) { model.createWorktree(from: workspace.path) }
            }
            Divider()
            Button(L("목록에서 제거", "Remove from List")) { model.removeWorkspace(workspace.path) }
                .disabled(model.workspaces.count < 2)
        }
    }
}

/// Ask an agent straight from the preview. The preview never takes keyboard focus on hover;
/// clicking this field does, and Enter starts the agent with the text in the current folder.
struct QuickPromptField: View {
    @Bindable var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool
    private let agents: [AgentKind] = [.codex, .claude, .gemini]
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(agents, id: \.self) { kind in
                    Button { model.quickAgent = kind } label: {
                        AgentLogo(kind: kind, size: 13)
                            .padding(6)
                            .background(model.quickAgent == kind ? Color.white.opacity(0.1) : .clear)
                            .clipShape(.rect(cornerRadius: 6))
                            .opacity(model.executable(for: kind) == nil ? 0.35 : 1)
                            // The whole square is clickable, not just the logo's thin strokes.
                            .contentShape(.rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(kind.name + (model.executable(for: kind) == nil ? L(" · 실행 파일을 찾을 수 없음", " · executable not found") : ""))
                    .accessibilityLabel(kind.name).accessibilityAddTraits(model.quickAgent == kind ? .isSelected : [])
                }
            }
            Rectangle().fill(Palette.line).frame(width: 1, height: 16)
            ZStack(alignment: .leading) {
                TextField("", text: $text, prompt: Text(L("\(model.quickAgent.name)에게 바로 요청…", "Ask \(model.quickAgent.name)…")).foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { text = ""; model.cancelQuickPrompt() }
                    .allowsHitTesting(model.quickPromptActive)
                if !model.quickPromptActive {
                    // The preview panel cannot take focus by itself; the first click asks for it.
                    Color.clear.contentShape(Rectangle()).onTapGesture { model.beginQuickPrompt?() }
                }
            }
            Image(systemName: "return").font(.caption).foregroundStyle(text.isEmpty ? Palette.muted : Palette.mint)
        }
        .font(.subheadline)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Palette.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? Palette.mint.opacity(0.5) : Palette.line) }
        .onChange(of: model.quickPromptActive) { _, active in focused = active; if !active { text = "" } }
        .accessibilityElement(children: .contain)
    }
    private func submit() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        text = ""
        model.submitQuickPrompt(prompt)
    }
}

/// Right wing of the closed notch. One item, chosen by `NotchStatus.resolve`.
struct NotchStatusView: View {
    let status: NotchStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            switch status {
            case .attention(let reason):
                Image(systemName: Self.symbol(for: reason))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.color(for: reason))
                    .symbolEffect(.bounce, value: reason)
                    .phaseAnimator(reason == .bell && !reduceMotion ? [1.0, 0.55] : [1.0]) { content, opacity in
                        content.opacity(opacity) // a request "breathes" until it is seen
                    } animation: { _ in .easeInOut(duration: 1.1) }
                    .accessibilityLabel(reason.message)
            case .working(let since):
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if context.date.timeIntervalSince(since) < NotchStatus.clockAfter {
                        WorkingDots()
                    } else {
                        Text(NotchStatus.elapsed(since: since, now: context.date))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityLabel(L("작업 중", "Working"))
            case .lowQuota(let agent, let remaining):
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.2)
                    Circle().trim(from: 0, to: remaining / 100).stroke(Palette.low, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 13, height: 13)
                .help(L("\(agent.name) 한도 \(Int(remaining))% 남음", "\(agent.name) limit: \(Int(remaining))% left"))
                .accessibilityLabel(L("\(agent.name) 한도 \(Int(remaining))% 남음", "\(agent.name) limit: \(Int(remaining))% left"))
            case .sessions:
                Circle().fill(Palette.muted).frame(width: 6, height: 6).accessibilityLabel(L("대기 중", "Idle"))
            case .empty:
                Color.clear
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .animation(Motion.snappy, value: status)
    }
    static func symbol(for reason: AttentionReason) -> String {
        switch reason {
        case .bell: "bell.fill"
        case .finished: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .exited: "stop.circle.fill"
        }
    }
}

/// Idle notch: an agent's icon inside a gauge ring filled to its remaining quota, optionally
/// with the percentage. The icon already names the agent, so the ring is neutral white and
/// only turns red at 20% or less.
struct UsageBadge: View {
    let usage: IdleUsage
    let showsNumber: Bool
    static func color(_ usage: IdleUsage) -> Color {
        usage.remaining <= NotchStatus.lowQuotaThreshold ? Palette.low : Color.white.opacity(0.9)
    }
    static func percent(_ usage: IdleUsage) -> some View {
        Text("\(Int(usage.remaining))%").font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(usage.remaining <= NotchStatus.lowQuotaThreshold ? Palette.low : Color.white)
            .contentTransition(.numericText(value: usage.remaining))
            .help(usage.agent.name + " · " + usage.window.title + L(" 남음", " left") + " · " + usage.window.resetLabel())
    }
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 2)
                Circle().trim(from: 0, to: usage.remaining / 100)
                    .stroke(Self.color(usage), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(Motion.snappy, value: usage.remaining)
                SessionIcon(kind: usage.agent, size: 11)
            }
            .frame(width: 21, height: 21)
            if showsNumber { Self.percent(usage) }
        }
        .help(usage.agent.name + " · " + usage.window.title + L(" \(Int(usage.remaining))% 남음 · ", " \(Int(usage.remaining))% left · ") + usage.window.resetLabel())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usage.agent.name + " " + usage.window.title + L(" \(Int(usage.remaining))퍼센트 남음", " \(Int(usage.remaining)) percent left"))
    }
}

/// "•••" flowing left to right while an agent works.
struct WorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let step = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle().fill(Color.white.opacity(index == step ? 1 : 0.35)).frame(width: 4, height: 4)
                }
            }
        }
    }
}

/// The agent's mark; Terminal sessions use the terminal symbol.
struct SessionIcon: View {
    let kind: AgentKind
    var size: CGFloat = 14
    var body: some View {
        Group {
            if kind == .shell {
                Image(systemName: "terminal").font(.system(size: size * 0.8, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
            } else { AgentLogo(kind: kind, size: size) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A session among several: its icon inside a ring whose color says its state. Working spins
/// a white arc (so it never reads as "done" green); a request breathes; quiet has no ring.
struct RingedSessionIcon: View {
    let kind: AgentKind
    let badge: NotchBadge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    var body: some View {
        ZStack {
            switch badge {
            case .quiet: EmptyView()
            case .working:
                Circle().trim(from: 0, to: 0.3)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            case .done: Circle().stroke(Palette.done, lineWidth: 2)
            case .waiting:
                Circle().stroke(Palette.attention, lineWidth: 2)
                    .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { content, opacity in content.opacity(opacity) }
                        animation: { _ in .easeInOut(duration: 1.1) }
            case .error: Circle().stroke(Palette.low, lineWidth: 2)
            }
            SessionIcon(kind: kind, size: 12).opacity(badge == .quiet ? 0.5 : 1)
        }
        .frame(width: 22, height: 22)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct WorkspaceChipStyle: ButtonStyle {
    let active: Bool
    let highlight: Namespace.ID
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 9).padding(.vertical, 7)
            .background {
                // The active chip's background slides to the newly chosen folder.
                if active {
                    RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.055))
                        .matchedGeometryEffect(id: "activeFolder", in: highlight)
                }
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(configuration.isPressed ? 0.09 : 0)))
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
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(L("사용량 새로고침", "Refresh usage"))
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

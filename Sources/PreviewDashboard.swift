import SwiftUI

struct FolderDropTarget: ViewModifier {
    let model: AppModel
    @State private var targeted = false
    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { urls, _ in model.addDroppedFolders(urls) } isTargeted: { targeted = $0 }
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.mint, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Compact usage for the preview: one line per agent with small bars; reset times and
/// stale-reading details stay in tooltips.
struct PreviewUsageSummary: View {
    let codex: UsageService
    let claude: ClaudeUsageService
    var body: some View {
        VStack(spacing: 8) {
            if codex.enabled {
                row(.codex, snapshot: codex.snapshot, tint: Palette.codex,
                    placeholder: codex.isLoading ? L("확인 중", "Loading") : (codex.error ?? "—"),
                    warning: codex.error ?? (codex.snapshot?.isStale == true ? L("마지막 조회 값 · 갱신 필요", "Last reading · refresh needed") : nil),
                    carriesRefresh: true)
            } else {
                HStack(spacing: 8) {
                    Button { codex.setEnabled(true) } label: {
                        HStack(spacing: 6) {
                            AgentLogo(kind: .codex, size: 13)
                            Text(L("Codex 사용량 연결", "Connect Codex usage")).font(.caption)
                        }
                    }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    if !claude.enabled { refresh }
                }
            }
            if claude.enabled {
                row(.claude, snapshot: claude.snapshot, tint: Palette.claude,
                    placeholder: L("NotchAgent의 Claude 세션이 응답하면 표시됩니다", "Shows after a Claude session in NotchAgent replies"),
                    warning: claude.snapshot.map { Date().timeIntervalSince($0.fetchedAt) > 3600 } == true
                        ? L("마지막 수신 값 · 다음 응답 시 갱신", "Last reading · updates on next reply") : nil,
                    carriesRefresh: !codex.enabled)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Palette.surface).clipShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("남은 사용량", "Remaining usage"))
    }
    private var refresh: some View {
        RefreshButton(help: L("사용량 새로고침 · 숫자는 남은 한도입니다", "Refresh usage · percentages show remaining quota")) {
            if codex.enabled { codex.refresh() }
            if claude.enabled { claude.reload() }
        }.disabled(codex.isLoading)
    }
    private func row(_ kind: AgentKind, snapshot: UsageSnapshot?, tint: Color,
                     placeholder: String, warning: String?, carriesRefresh: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                AgentLogo(kind: kind, size: 13)
                Text(kind == .claude ? "Claude" : "Codex").fontWeight(.medium)
            }.frame(width: 70, alignment: .leading)
            if let snapshot {
                ForEach(snapshot.windows.prefix(2)) { window in
                    HStack(spacing: 6) {
                        Text(shortTitle(window)).foregroundStyle(Palette.muted).frame(width: 20, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(window.remaining <= 20 ? Palette.low : tint)
                                    .frame(width: geo.size.width * window.remaining / 100)
                                    .animation(Motion.snappy, value: window.remaining)
                            }
                        }.frame(height: 4)
                        Text("\(Int(window.remaining))%").monospacedDigit()
                            .foregroundStyle(window.remaining <= 20 ? Palette.low : Color.white)
                            .frame(width: 34, alignment: .trailing)
                            .contentTransition(.numericText(value: window.remaining))
                            .animation(Motion.snappy, value: window.remaining)
                    }
                    .help(window.title + L(" 남음", " left") + " · " + window.resetLabel())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(window.title + L(" \(Int(window.remaining))% 남음, ", " \(Int(window.remaining))% left, ") + window.resetLabel())
                }
            } else {
                Text(placeholder).foregroundStyle(Palette.muted).lineLimit(1).help(warning ?? placeholder)
                Spacer(minLength: 0)
            }
            Group {
                if let warning, snapshot != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).help(warning)
                } else { Color.clear }
            }.frame(width: 12)
            // Keeps both rows' bars aligned whether or not this row carries the refresh button.
            if carriesRefresh { refresh } else { Color.clear.frame(width: 18) }
        }
        .font(.system(size: 11))
    }
    private func shortTitle(_ window: UsageWindow) -> String {
        guard let minutes = window.durationMinutes else { return window.id == "primary" ? "1" : "2" }
        if minutes % 1440 == 0 { return "\(minutes / 1440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

struct RecentActivitiesView: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(L("최근 활동", "Recent Activity")).font(.caption.weight(.semibold))
                if model.unreadActivityCount > 0 {
                    Text("\(model.unreadActivityCount)").font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.mint).padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Palette.mint.opacity(0.12)).clipShape(Capsule())
                }
                Spacer()
                if model.attentionCount > 0 {
                    Button(L("확인 필요 \(model.attentionCount)", "Needs attention \(model.attentionCount)")) {
                        model.openPrioritySession()
                    }
                    .font(.caption2).buttonStyle(.plain).foregroundStyle(Palette.attention)
                    .help(L("확인이 필요한 세션으로 이동 · ⇧⌘A", "Open a session needing attention · ⇧⌘A"))
                }
                if !model.recentActivities.isEmpty {
                    Button(L("비우기", "Clear")) { model.clearRecentActivities() }
                        .font(.caption2).buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .accessibilityLabel(L("최근 활동 기록 비우기", "Clear recent activity"))
                }
            }
            if model.recentActivities.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge").foregroundStyle(Palette.muted)
                    Text(L("놓친 작업 완료와 확인 요청이 여기에 모입니다.", "Missed completions and requests will appear here."))
                        .font(.caption).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.recentActivities) { activity in
                                activityRow(activity, now: timeline.date)
                            }
                        }
                    }.frame(height: min(CGFloat(model.recentActivities.count) * 46, 138))
                }
            }
        }
    }
    private func activityRow(_ activity: RecentActivity, now: Date) -> some View {
        let available = model.sessions.contains { $0.id == activity.sessionID }
        return Button {
            if available { model.openSession(id: activity.sessionID) }
            else { model.markActivityRead(id: activity.id) }
        } label: {
            HStack(spacing: 9) {
                if activity.kind == .shell {
                    Image(systemName: "terminal").font(.caption).frame(width: 15)
                } else { AgentLogo(kind: activity.kind, size: 15) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(activity.kind == .claude ? "Claude" : activity.kind.name).fontWeight(.medium)
                        Text(activity.reason.message).foregroundStyle(Palette.color(for: activity.reason))
                    }.font(.caption)
                    Text(activity.title == activity.folder ? activity.folder : "\(activity.title) · \(activity.folder)")
                        .font(.caption2).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(available ? UsageAge.label(since: activity.date, now: now) : L("닫힌 세션", "Closed"))
                    .font(.caption2).foregroundStyle(Palette.muted).fixedSize()
                Circle().fill(activity.isRead ? Color.clear : Palette.mint).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 9).frame(height: 42)
            .background(activity.isRead ? Color.white.opacity(0.025) : Color.white.opacity(0.055))
            .clipShape(.rect(cornerRadius: 8)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(available ? 1 : 0.7)
        .help(available ? L("세션 열기", "Open session") : L("닫힌 세션의 기록 읽음 처리", "Mark this closed session's activity as read"))
    }
}

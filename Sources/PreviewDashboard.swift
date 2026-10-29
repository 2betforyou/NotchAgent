import SwiftUI

/// Refreshes only the age label; terminal views do not redraw on its clock.
struct UsageReadingStatus: View {
    let agent: AgentKind
    let snapshot: UsageSnapshot?
    var loading = false
    var error: String? = nil
    var refresh: (() -> Void)? = nil
    var concise = false
    var iconOnly = false
    @State private var showingDetails = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let stale = snapshot.map { UsageFreshness.isStale($0, agent: agent, now: context.date) } ?? false
            let label = UsageFreshness.label(snapshot: snapshot, agent: agent, loading: loading, error: error, now: context.date)
            let shortLabel = snapshot.map { (stale ? "! " : "") + UsageAge.label(since: $0.fetchedAt, now: context.date) }
            Button { showingDetails.toggle() } label: {
                if iconOnly {
                    AgentLogo(kind: agent, size: 14)
                        .overlay(alignment: .topTrailing) {
                            if stale || error != nil { Circle().fill(.orange).frame(width: 4, height: 4) }
                        }
                } else {
                    Text(concise && !loading && error == nil ? shortLabel ?? label : label).font(.system(size: 10)).lineLimit(1)
                        .foregroundStyle(stale || error != nil ? Color.orange : Palette.muted)
                }
            }
            .buttonStyle(.plain).help(label + L(" · 눌러서 자세히 보기", " · Click for details"))
            .accessibilityLabel(agent.name + " · " + label)
            .popover(isPresented: $showingDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(agent.name + L(" 사용량", " usage")).font(.headline)
                    if let snapshot {
                        Text(L("마지막 갱신: ", "Last updated: ") + snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))
                    }
                    if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                    if stale { Text(L("오래된 값입니다. 현재 남은 한도와 다를 수 있습니다.", "This reading is outdated and may differ from your current limit.")).foregroundStyle(.orange) }
                    Text(agent == .claude ? ClaudeUsageService.refreshHelp : L("5분마다 조회합니다. 조회 실패 시 마지막 성공 값을 유지합니다.", "Checked every five minutes. The last successful reading is kept if a refresh fails."))
                    if let refresh {
                        Button(agent == .claude ? L("마지막 값 다시 읽기", "Re-read last value") : L("다시 조회", "Retry refresh"), action: refresh)
                            .disabled(loading)
                    }
                }.font(.caption).padding(16).frame(width: 290, alignment: .leading)
            }
        }
    }
}

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

/// Kept as the preview entry point; rendering is shared with the workspace footer.
struct PreviewUsageSummary: View {
    let codex: UsageService
    let claude: ClaudeUsageService
    var body: some View {
        CompactUsageFooter(codex: codex, claude: claude, stacked: true)
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
        let available = model.sessions.contains { !$0.ended && $0.id == activity.sessionID }
        let resumable = model.canResumeActivity(activity)
        return Button {
            model.openActivity(id: activity.id)
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
                Text(available ? UsageAge.label(since: activity.date, now: now) : resumable ? L("이어가기 ↗", "Resume ↗") : L("이전 기록", "Past event"))
                    .font(.caption2).foregroundStyle(Palette.muted).fixedSize()
                Circle().fill(activity.isRead ? Color.clear : Palette.mint).frame(width: 5, height: 5)
            }
            .padding(.horizontal, 9).frame(height: 42)
            .background(activity.isRead ? Color.white.opacity(0.025) : Color.white.opacity(0.055))
            .clipShape(.rect(cornerRadius: 8)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).opacity(available || resumable ? 1 : 0.7)
        .help(available ? L("세션 열기", "Open session") : resumable ? L("같은 대화를 새 탭에서 이어가기", "Resume this conversation in a new tab") : L("대화 복원 정보가 없는 이전 기록", "This older event has no conversation restore details"))
    }
}

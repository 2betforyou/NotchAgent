import SwiftUI

/// Preview and workspace share consumed quota, ordering, and reset countdowns.
struct CompactUsageFooter: View {
    let codex: UsageService
    let claude: ClaudeUsageService
    var stacked = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if stacked {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("사용", "Used")).foregroundStyle(Palette.muted)
                        Spacer(minLength: 0)
                        refresh
                    }
                    agents(now: context.date)
                    connect
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Palette.surface).clipShape(.rect(cornerRadius: 9))
            } else {
            HStack(spacing: 14) {
                Text(L("사용", "Used")).foregroundStyle(Palette.muted)
                agents(now: context.date)
                connect
                Spacer(minLength: 0)
                refresh
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Palette.surface).clipShape(.rect(cornerRadius: 9))
            }
        }
    }
    @ViewBuilder private func agents(now: Date) -> some View {
        if claude.enabled {
            CompactAgentUsage(agent: .claude, snapshot: claude.snapshot, now: now,
                              refresh: { claude.reload() })
        }
        if codex.enabled {
            CompactAgentUsage(agent: .codex, snapshot: codex.snapshot, now: now,
                              loading: codex.isLoading, error: codex.error, refresh: { codex.refresh() })
        }
    }
    @ViewBuilder private var connect: some View {
        if !codex.enabled && !claude.enabled {
            Button(L("Codex 사용량 연결", "Connect Codex usage")) { codex.setEnabled(true) }
                .buttonStyle(.plain).foregroundStyle(Palette.codex)
        }
    }
    private var refresh: some View {
        RefreshButton(help: L("Codex는 다시 조회하고 Claude는 마지막 값을 다시 읽습니다. 숫자는 사용한 비율입니다.", "Refreshes Codex and re-reads Claude's last value. Percentages show used quota.")) {
                    if codex.enabled { codex.refresh() }
                    if claude.enabled { claude.reload() }
                }.disabled(codex.isLoading || (!codex.enabled && !claude.enabled))
    }
}

private struct CompactAgentUsage: View {
    let agent: AgentKind
    let snapshot: UsageSnapshot?
    let now: Date
    var loading = false
    var error: String? = nil
    let refresh: () -> Void
    private var windows: [UsageWindow] {
        Array((snapshot?.windows ?? []).sorted { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }.prefix(2))
    }
    var body: some View {
        HStack(spacing: 7) {
            UsageReadingStatus(agent: agent, snapshot: snapshot, loading: loading, error: error,
                               refresh: refresh, iconOnly: true)
            if windows.isEmpty {
                Text(loading ? "…" : "—").foregroundStyle(Palette.muted)
            } else {
                ForEach(windows) { window in
                    if window.id != windows.first?.id { Text("·").foregroundStyle(Palette.muted) }
                    if window.id == windows.first?.id {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(window.remaining <= 20 ? Palette.low : Palette.muted)
                                .frame(width: 44 * window.consumed / 100)
                        }.frame(width: 44, height: 4).accessibilityHidden(true)
                    }
                    HStack(spacing: 6) {
                        Text("\(Int(window.consumed))%")
                            .foregroundStyle(window.remaining <= 20 ? Palette.low : .white)
                            .frame(width: 28, alignment: .trailing)
                        Text(shortReset(window)).foregroundStyle(Palette.muted)
                            .frame(width: 60, alignment: .leading)
                    }
                    .fixedSize()
                    .help(agent.name + " · " + window.title + L(" 사용 · ", " used · ") + window.resetLabel(now: now))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(agent.name + " · " + window.title + L(" \(Int(window.consumed))% 사용 · ", " \(Int(window.consumed))% used · ") + window.resetLabel(now: now))
                }
            }
        }
    }
    private func shortReset(_ window: UsageWindow) -> String {
        guard let reset = window.resetsAt else { return "—" }
        let minutes = max(0, Int(ceil(reset.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "0m" }
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

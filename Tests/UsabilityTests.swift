import Foundation
import Testing
@testable import NotchAgent

@MainActor
@Suite("Daily usability")
struct UsabilityTests {
    private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let name = "NotchAgent.UsabilityTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(AppModel(defaults: defaults), defaults)
    }

    @Test("A failed quick request leaves the composer active so its draft remains")
    func failedQuickPrompt() throws {
        try withModel { model, defaults in
            defaults.set("/missing/notchagent-codex", forKey: "codexPath")
            model.quickAgent = .codex
            model.quickPromptActive = true
            #expect(!model.submitQuickPrompt("Keep this draft"))
            #expect(model.quickPromptActive)
            #expect(model.sessions.isEmpty)
            #expect(model.lastError != nil)
        }
    }

    @Test("Attention navigation prioritizes input requests across folders")
    func priorityNavigation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentAttention-" + UUID().uuidString)
        let first = root.appendingPathComponent("one")
        let second = root.appendingPathComponent("two")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try withModel { model, _ in
            let finished = TerminalSession(kind: .codex, directory: first, executable: "/bin/zsh", fontSize: 13)
            let waiting = TerminalSession(kind: .claude, directory: second, executable: "/bin/zsh", fontSize: 13)
            model.sessions = [finished, waiting]
            let now = Date()
            finished.receive(.finished, conversation: nil, now: now)
            waiting.receive(.needsInput, conversation: nil, now: now)
            model.tickActivity(now: now)
            #expect(model.attentionCount == 2)
            #expect(model.handleTabShortcut(key: "a", shift: true))
            #expect(model.selectedID == waiting.id)
            #expect(model.workspacePath == second.path)
            #expect(waiting.attention == nil)
            #expect(model.openPrioritySession())
            #expect(model.selectedID == finished.id)
            #expect(!model.openPrioritySession())
        }
    }

    @Test("Recent activity survives relaunch for 24 hours and can be deleted")
    func recentActivityRetention() throws {
        try withModel { model, defaults in
            let session = TerminalSession(kind: .shell, directory: URL(fileURLWithPath: "/tmp/project"), executable: "/bin/zsh", fontSize: 13)
            let now = Date()
            model.recordActivity(.finished, for: session, now: now)
            model.markActivitiesRead(for: session.id)
            let restored = AppModel(defaults: defaults)
            #expect(restored.recentActivities.count == 1)
            #expect(restored.recentActivities.first?.isRead == true)
            #expect(restored.recentActivities.first?.sessionID == session.id)

            restored.recordActivity(.bell, for: session, now: now)
            let unread = try #require(restored.recentActivities.first)
            restored.markActivityRead(id: unread.id)
            #expect(restored.unreadActivityCount == 0)

            let old = RecentActivity(sessionID: UUID(), kind: .claude, title: "Old", folder: "old", reason: .bell,
                                     date: now.addingTimeInterval(-AppModel.activityRetention - 1))
            let recent = try #require(restored.recentActivities.first)
            defaults.set(try JSONEncoder().encode([recent, old]), forKey: "recentActivities")
            #expect(AppModel(defaults: defaults).recentActivities.count == 1)

            restored.keepRecentActivities = false
            #expect(defaults.data(forKey: "recentActivities") == nil)
            #expect(AppModel(defaults: defaults).recentActivities.isEmpty)
        }
    }

    @Test("System alerts hide task details unless explicitly enabled and honor event choices")
    func notificationPrivacy() throws {
        try withModel { model, defaults in
            let activity = RecentActivity(sessionID: UUID(), kind: .claude, title: "Private task", folder: "Secret project",
                                          reason: .bell, date: Date())
            let privateBody = ActivityNotificationText.body(for: activity, showsDetails: model.showNotificationDetails)
            #expect(!privateBody.contains("Private task"))
            #expect(!privateBody.contains("Secret project"))
            #expect(ActivityNotificationText.body(for: activity, showsDetails: true).contains("Private task"))
            model.notifyForNeedsInput = false
            #expect(!model.shouldDeliverActivity(.bell))
            #expect(model.shouldDeliverActivity(.finished))
            #expect(!AppModel(defaults: defaults).notifyForNeedsInput)
        }
    }
}

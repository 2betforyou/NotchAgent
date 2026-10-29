import XCTest
import AppKit
import SwiftUI
@testable import NotchAgent

@MainActor
final class UserExperienceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "NotchAgent.UX." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("/bin/zsh", forKey: "codexPath")
        defaults.set("/bin/zsh", forKey: "claudePath")
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testDeliveryMigratesEffectiveLegacyChoicesWithoutEnablingOtherEvents() {
        defaults.set(false, forKey: "notifyEnabled")
        defaults.set(true, forKey: "activitySoundEnabled")
        defaults.set(false, forKey: "notifyForCompletion")
        let model = AppModel(defaults: defaults)
        XCTAssertFalse(model[delivery: .finished, channel: .notch])
        XCTAssertFalse(model[delivery: .finished, channel: .sound])
        XCTAssertTrue(model[delivery: .bell, channel: .sound])
        model[delivery: .bell, channel: .system] = true
        XCTAssertTrue(model[delivery: .bell, channel: .system])
        XCTAssertFalse(model[delivery: .finished, channel: .system])
        XCTAssertFalse(model[delivery: .bell, channel: .notch])
        model[delivery: .finished, channel: .notch] = true
        let restored = AppModel(defaults: defaults)
        XCTAssertTrue(restored[delivery: .finished, channel: .notch])
        XCTAssertFalse(restored[delivery: .finished, channel: .sound])
        restored[delivery: .exited, channel: .notch] = false
        XCTAssertFalse(restored[delivery: .failed, channel: .notch])
    }

    func testActivityResumesExactConversationAfterRelaunchAndReusesTab() throws {
        for kind in [AgentKind.codex, .claude] {
            let model = AppModel(defaults: defaults)
            let session = TerminalSession(kind: kind, directory: FileManager.default.temporaryDirectory,
                                          executable: "/bin/zsh", fontSize: 13)
            session.conversationID = "conversation-" + kind.rawValue
            model.recordActivity(.finished, for: session, now: Date())
            let activity = try XCTUnwrap(model.recentActivities.first)
            let restored = AppModel(defaults: defaults)
            restored.openActivity(id: activity.id)
            let resumed = try XCTUnwrap(restored.sessions.first)
            XCTAssertEqual(resumed.conversationID, session.conversationID)
            XCTAssertEqual(resumed.initialDirectory.path, session.initialDirectory.path)
            XCTAssertTrue(resumed.commandLine.contains(session.conversationID!))
            XCTAssertFalse(resumed.commandLine.contains("--last"))
            XCTAssertEqual(restored.selectedID, resumed.id)
            XCTAssertTrue(restored.recentActivities.first!.isRead)
            restored.openActivity(id: activity.id)
            XCTAssertEqual(restored.sessions.count, 1)
        }
    }

    func testLegacyActivityDecodesWithoutInventingConversation() throws {
        let legacy = RecentActivity(sessionID: UUID(), kind: .codex, title: "Old task", folder: "project", reason: .finished, date: Date())
        let data = try JSONEncoder().encode([legacy])
        defaults.set(data, forKey: "recentActivities")
        let restored = AppModel(defaults: defaults)
        let decoded = try XCTUnwrap(restored.recentActivities.first)
        XCTAssertNil(decoded.projectPath)
        XCTAssertFalse(restored.canResumeActivity(decoded))
        restored.openActivity(id: decoded.id)
        XCTAssertTrue(restored.sessions.isEmpty)
        XCTAssertNotNil(restored.lastError)
        XCTAssertFalse(restored.recentActivities.first!.isRead)
    }

    func testMissingProjectDoesNotLaunchOrMarkRead() throws {
        let model = AppModel(defaults: defaults)
        let session = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: "/missing/notchagent-" + UUID().uuidString),
                                      executable: "/bin/zsh", fontSize: 13)
        session.conversationID = "known-chat"
        model.recordActivity(.bell, for: session, now: Date())
        model.openActivity(id: try XCTUnwrap(model.recentActivities.first?.id))
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNotNil(model.lastError)
        XCTAssertFalse(model.recentActivities.first!.isRead)
    }

    func testResumeHonorsSessionLimitAndMissingCLI() throws {
        let model = AppModel(defaults: defaults)
        let session = TerminalSession(kind: .codex, directory: FileManager.default.temporaryDirectory, executable: "/bin/zsh", fontSize: 13)
        session.conversationID = "exact-chat"
        model.recordActivity(.finished, for: session, now: Date())
        let activity = try XCTUnwrap(model.recentActivities.first)
        defaults.set("/missing/cli", forKey: "codexPath")
        model.openActivity(id: activity.id)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertNotNil(model.lastError)
        defaults.set("/bin/zsh", forKey: "codexPath")
        model.sessions = (0..<8).map { _ in TerminalSession(kind: .shell, directory: FileManager.default.temporaryDirectory, executable: "/bin/zsh", fontSize: 13) }
        model.openActivity(id: activity.id)
        XCTAssertEqual(model.sessions.count, 8)
        XCTAssertFalse(model.recentActivities.first!.isRead)
    }

    func testInlineSettingsDoesNotReadHiddenSessionEvents() {
        let model = AppModel(defaults: defaults)
        let session = TerminalSession(kind: .claude, directory: FileManager.default.temporaryDirectory, executable: "/bin/zsh", fontSize: 13)
        model.sessions = [session]
        model.selectedID = session.id
        model.phase = .terminal
        model.showsInlineSettings = true
        session.receive(.needsInput, conversation: "same-chat", now: Date())
        model.tickActivity(terminalIsVisible: true)
        XCTAssertEqual(model.unreadActivityCount, 1)
        XCTAssertEqual(session.attention, .bell)
        XCTAssertEqual(model.selectedID, session.id)
        var settingsReopened = false
        model.showSettings = { settingsReopened = true }
        model.phase = .closed
        model.openPriorityOrTerminal()
        XCTAssertTrue(settingsReopened)
        XCTAssertEqual(model.selectedID, session.id)
        model.phase = .terminal
        model.showsInlineSettings = false
        model.tickActivity(terminalIsVisible: true)
        XCTAssertEqual(model.unreadActivityCount, 0)
        XCTAssertNil(session.attention)
    }

    func testRenderExperience() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["NOTCHAGENT_SNAPSHOT_DIR"] != nil)
        let output = URL(fileURLWithPath: env["NOTCHAGENT_SNAPSHOT_DIR"]!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let oldLanguage = AppLanguage.current
        defer { AppLanguage.current = oldLanguage }
        for language in [AppLanguage.english, .korean] {
            AppLanguage.current = language
            let snapshot = UsageSnapshot(windows: [
                UsageWindow(id: "primary", usedPercent: 22, durationMinutes: 300, resetsAt: Date().addingTimeInterval(3600)),
                UsageWindow(id: "secondary", usedPercent: 38, durationMinutes: 10080, resetsAt: Date().addingTimeInterval(80000))
            ], fetchedAt: Date().addingTimeInterval(-1200))
            let usage = UsageService(snapshot: snapshot)
            usage.enabled = true
            defaults.removeObject(forKey: "recentActivities")
            let model = AppModel(defaults: defaults, usage: usage)
            model.language = language
            model.claudeUsage.enabled = false
            let sample = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: "/tmp/World_Models"), executable: "/bin/zsh", fontSize: 13)
            sample.conversationID = "sample-conversation"
            model.recordActivity(.finished, for: sample, now: Date())
            let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 24) {
                Text(L("이벤트별 알림", "Event delivery")).font(.headline)
                NotificationRoutingView(model: model)
                PreviewUsageSummary(codex: usage, claude: model.claudeUsage).frame(width: 518)
                RecentActivitiesView(model: model).frame(width: 518)
                UsageStrip(service: usage, compact: true, showsAgent: true)
                Spacer(minLength: 0)
            }.padding(24).frame(width: 760, height: 520).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark))
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("experience-\(language.rawValue).png"))
            window.close()
            model.phase = .terminal
            model.showsInlineSettings = true
            model.panelWidth = 940; model.panelHeight = 620
            model.hasPhysicalNotch = false
            let settingsHost = NSHostingView(rootView: IslandView(model: model))
            settingsHost.frame = NSRect(x: 0, y: 0, width: model.panelWidth + 32, height: model.hostHeight + 32)
            let settingsWindow = NSWindow(contentRect: settingsHost.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            settingsWindow.isReleasedWhenClosed = false
            settingsWindow.contentView = settingsHost
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            settingsHost.layoutSubtreeIfNeeded()
            let settingsBitmap = try XCTUnwrap(settingsHost.bitmapImageRepForCachingDisplay(in: settingsHost.bounds))
            settingsHost.cacheDisplay(in: settingsHost.bounds, to: settingsBitmap)
            try XCTUnwrap(settingsBitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("inline-settings-\(language.rawValue).png"))
            settingsWindow.close()
        }
    }

    func testFreshnessUsesAgentCadenceAndInvalidatesExpiredWindow() {
        let now = Date()
        func snapshot(age: TimeInterval, reset: Date? = nil) -> UsageSnapshot {
            UsageSnapshot(windows: [UsageWindow(id: "primary", usedPercent: 12, durationMinutes: 300, resetsAt: reset)], fetchedAt: now.addingTimeInterval(-age))
        }
        XCTAssertFalse(UsageFreshness.isStale(snapshot(age: 300), agent: .codex, now: now))
        XCTAssertTrue(UsageFreshness.isStale(snapshot(age: 601), agent: .codex, now: now))
        XCTAssertFalse(UsageFreshness.isStale(snapshot(age: 601), agent: .claude, now: now))
        XCTAssertTrue(UsageFreshness.isStale(snapshot(age: 3601), agent: .claude, now: now))
        XCTAssertTrue(UsageFreshness.isStale(snapshot(age: 10, reset: now.addingTimeInterval(-1)), agent: .codex, now: now))
        XCTAssertNotEqual(UsageFreshness.label(snapshot: snapshot(age: 0), agent: .codex, loading: false, error: "offline", now: now),
                          UsageFreshness.label(snapshot: snapshot(age: 0), agent: .codex, loading: false, error: nil, now: now))
    }
}

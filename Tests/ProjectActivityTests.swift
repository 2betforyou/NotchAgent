import Foundation
import Testing
@testable import NotchAgent

@MainActor
@Suite("Project activity")
struct ProjectActivityTests {
    private func withModel(_ body: (AppModel, UserDefaults) throws -> Void) throws {
        let name = "NotchAgent.ProjectActivityTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(AppModel(defaults: defaults), defaults)
    }

    @Test("Visible agent replies count without creating missed-activity notices")
    func visibleReplies() throws {
        try withModel { model, defaults in
            let path = Workspaces.normalize("/tmp/project-activity")
            let session = TerminalSession(kind: .codex, directory: URL(fileURLWithPath: path), executable: "/bin/zsh", fontSize: 13)
            model.workspacePath = path
            model.sessions = [session]
            model.selectedID = session.id
            model.phase = .terminal
            let now = Date()
            session.receive(.finished, conversation: nil, now: now)
            model.tickActivity(now: now, terminalIsVisible: true)
            #expect(model.projectActivity.count(in: path, on: now) == 1)
            #expect(model.recentActivities.isEmpty)
            session.receive(.finished, conversation: nil, now: now.addingTimeInterval(2))
            model.tickActivity(now: now.addingTimeInterval(2), terminalIsVisible: true)
            #expect(model.projectActivity.count(in: path, on: now) == 2)
            #expect(AppModel(defaults: defaults).projectActivity.count(in: path, on: now) == 2)
        }
    }

    @Test("Replies are per project and turning recording off deletes saved counts")
    func projectIsolationAndDelete() throws {
        try withModel { model, defaults in
            let first = "/tmp/first-project"
            let second = "/tmp/second-project"
            let now = Date()
            for path in [first, second] {
                let session = TerminalSession(kind: .claude, directory: URL(fileURLWithPath: path), executable: "/bin/zsh", fontSize: 13)
                model.sessions = [session]
                session.receive(.finished, conversation: nil, now: now)
                model.tickActivity(now: now, terminalIsVisible: false)
            }
            #expect(model.projectActivity.count(in: first, on: now) == 1)
            #expect(model.projectActivity.count(in: second, on: now) == 1)
            model.projectActivityEnabled = false
            #expect(defaults.data(forKey: "projectActivityV1") == nil)
            #expect(AppModel(defaults: defaults).projectActivity.count(in: first, on: now) == 0)
        }
    }

    @Test("Old daily counts expire without storing reply content")
    func retention() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let old = calendar.date(byAdding: .day, value: -370, to: now)!
        var activity = ProjectActivity()
        activity.record(in: "/tmp/repo", at: old, calendar: calendar)
        activity.record(in: "/tmp/repo", at: now, calendar: calendar)
        let restored = ProjectActivity(data: activity.data(), now: now, calendar: calendar)
        #expect(restored.count(in: "/tmp/repo", on: old, calendar: calendar) == 0)
        #expect(restored.count(in: "/tmp/repo", on: now, calendar: calendar) == 1)
        #expect(!String(decoding: restored.data()!, as: UTF8.self).contains("prompt"))
    }

    @Test("Turning recording off also deletes imported history")
    func importedHistoryDeletion() throws {
        let name = "NotchAgent.ImportDeletion." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = Date()
        let path = "/tmp/history-project"
        var activity = ProjectActivity()
        activity.mergeHistoricalCounts([ProjectActivity.dayKey(now, calendar: .current): 3], in: path, now: now)
        defaults.set(activity.importedData(), forKey: "projectActivityImportedV1")
        let model = AppModel(defaults: defaults)
        #expect(model.projectActivity.count(in: path, on: now) == 3)
        model.projectActivityEnabled = false
        #expect(defaults.data(forKey: "projectActivityImportedV1") == nil)
        #expect(model.projectActivity.count(in: path, on: now) == 0)
    }
}

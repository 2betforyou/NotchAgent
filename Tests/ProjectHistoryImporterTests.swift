import Foundation
import Testing
@testable import NotchAgent

@Suite("Past project activity")
struct ProjectHistoryImporterTests {
    @Test("Imports completed root replies for the selected folder only")
    func importsLocalHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgent-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let claude = root.appendingPathComponent("claude")
        let codex = root.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let project = "/tmp/example-project"
        let time = "2026-10-20T09:30:00.000Z"
        let claudeLines = [
            """
            {"type":"assistant","cwd":"\(project)","sessionId":"s1","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"private"}]},"timestamp":"\(time)","isSidechain":false}
            """,
            """
            {"type":"assistant","cwd":"\(project)","sessionId":"s1","message":{"id":"m1","stop_reason":"end_turn","content":[{"type":"text","text":"duplicate"}]},"timestamp":"\(time)","isSidechain":false}
            """,
            """
            {"type":"assistant","cwd":"\(project)","sessionId":"s1","message":{"id":"m2","stop_reason":"tool_use","content":[{"type":"text","text":"not finished"}]},"timestamp":"\(time)","isSidechain":false}
            """,
            """
            {"type":"assistant","cwd":"\(project)","sessionId":"s1","message":{"id":"m3","stop_reason":"end_turn","content":[{"type":"text","text":"sidechain"}]},"timestamp":"\(time)","isSidechain":true}
            """
        ]
        try claudeLines.joined(separator: "\n").write(to: claude.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
        let codexLines = [
            #"{"type":"session_meta","payload":{"id":"c1","cwd":"\#(project)","source":"cli"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","root_turn_id":"t1"},"timestamp":"\#(time)"}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","root_turn_id":"t1"},"timestamp":"\#(time)"}"#
        ]
        try codexLines.joined(separator: "\n").write(to: codex.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)
        let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!
        let result = ProjectHistoryImporter.scan(projectPath: project, now: now, claudeRoot: claude, codexRoot: codex)
        #expect(result.replies == 2)
        #expect(result.filesRead == 2)
        #expect(ProjectHistoryImporter.scan(projectPath: "/tmp/other", now: now, claudeRoot: claude, codexRoot: codex).replies == 0)
    }

    @Test("Re-importing never duplicates existing or later live replies")
    func mergeIsIdempotent() {
        let now = Date()
        let path = "/tmp/example-project"
        let day = ProjectActivity.dayKey(now, calendar: .current)
        var activity = ProjectActivity()
        activity.record(in: path, at: now)
        activity.mergeHistoricalCounts([day: 4], in: path, now: now)
        #expect(activity.count(in: path, on: now) == 4)
        activity.record(in: path, at: now)
        #expect(activity.count(in: path, on: now) == 5)
        activity.mergeHistoricalCounts([day: 5], in: path, now: now)
        #expect(activity.count(in: path, on: now) == 5)
        let restored = ProjectActivity(data: activity.data(), importedData: activity.importedData(), now: now)
        #expect(restored.count(in: path, on: now) == 5)
    }
}

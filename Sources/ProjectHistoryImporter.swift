import Foundation

/// Reads local CLI transcripts only on request. No conversation text leaves this scan.
enum ProjectHistoryImporter {
    struct Result: Sendable {
        let dailyCounts: [String: Int]
        let filesRead: Int
        var replies: Int { dailyCounts.values.reduce(0, +) }
    }

    static func scan(projectPath: String, now: Date = Date(),
                     claudeRoot: URL? = nil, codexRoot: URL? = nil) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claude = claudeRoot ?? home.appendingPathComponent(".claude/projects", isDirectory: true)
        let codex = codexRoot ?? home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let path = normalized(projectPath)
        let encodedPath = path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        let claudeProject = claude.appendingPathComponent(encodedPath, isDirectory: true)
        let claudeSearchRoot = claudeRoot == nil && FileManager.default.fileExists(atPath: claudeProject.path) ? claudeProject : claude
        let oldest = Calendar.current.date(byAdding: .day, value: -(ProjectActivity.retentionDays - 1), to: Calendar.current.startOfDay(for: now)) ?? now
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        var dailyCounts: [String: Int] = [:]
        var seenClaude: Set<String> = []
        var seenCodex: Set<String> = []
        var filesRead = 0

        func add(_ timestamp: String?) {
            guard let timestamp, let date = formatter.date(from: timestamp) ?? fallback.date(from: timestamp),
                  date >= oldest, date <= now else { return }
            dailyCounts[ProjectActivity.dayKey(date, calendar: .current), default: 0] += 1
        }

        for file in jsonlFiles(at: claudeSearchRoot) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            filesRead += 1
            for line in text.split(separator: "\n") {
                guard let record = json(line), record["type"] as? String == "assistant",
                      record["isSidechain"] as? Bool != true,
                      normalized(record["cwd"] as? String ?? "") == path,
                      let message = record["message"] as? [String: Any],
                      message["stop_reason"] as? String == "end_turn",
                      let content = message["content"] as? [[String: Any]],
                      content.contains(where: { $0["type"] as? String == "text" }),
                      let messageID = message["id"] as? String else { continue }
                let id = "\(record["sessionId"] as? String ?? file.lastPathComponent):\(messageID)"
                if seenClaude.insert(id).inserted { add(record["timestamp"] as? String) }
            }
        }

        for file in jsonlFiles(at: codex) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n")
            guard let metadata = lines.lazy.compactMap(json).first(where: { $0["type"] as? String == "session_meta" })?["payload"] as? [String: Any],
                  normalized(metadata["cwd"] as? String ?? "") == path,
                  metadata["parent_thread_id"] == nil || metadata["parent_thread_id"] is NSNull,
                  !(metadata["source"] as? [String: Any] ?? [:]).keys.contains("subagent") else { continue }
            filesRead += 1
            for line in lines {
                guard let record = json(line), record["type"] as? String == "event_msg",
                      let payload = record["payload"] as? [String: Any],
                      payload["type"] as? String == "task_complete",
                      let turnID = (payload["root_turn_id"] as? String) ?? (payload["turn_id"] as? String) else { continue }
                let id = "\(metadata["id"] as? String ?? file.lastPathComponent):\(turnID)"
                if seenCodex.insert(id).inserted {
                    add((payload["completed_at"] as? String) ?? (record["timestamp"] as? String))
                }
            }
        }
        return Result(dailyCounts: dailyCounts, filesRead: filesRead)
    }

    private static func jsonlFiles(at root: URL) -> [URL] {
        guard let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return urls.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private static func json(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }
}

import Foundation

/// Precise agent state from the CLIs' own extension points, instead of guessing from output:
/// Claude Code hooks (prompt submitted, turn finished, permission needed, session id) and the
/// Codex `notify` program (turn finished, thread id). Both are set only for sessions opened in
/// NotchAgent, run NotchAgent's binary in a helper mode, and reach the app through a local
/// distributed notification tagged with the NotchAgent session id.
enum AgentEvent: String {
    case started, finished, needsInput
}

enum AgentEvents {
    static let argument = "--agent-event"
    static let sessionVariable = "NOTCHAGENT_SESSION_ID"
    static let codexChainVariable = "NOTCHAGENT_CODEX_NOTIFY_CHAIN"
    static let notification = Notification.Name("app.notchagent.agentEvent")

    // MARK: Parsing

    /// Claude Code hook input (stdin JSON).
    static func parseClaude(_ json: [String: Any]) -> (event: AgentEvent?, conversation: String?) {
        let conversation = json["session_id"] as? String
        switch json["hook_event_name"] as? String {
        case "UserPromptSubmit": return (.started, conversation)
        case "Stop": return (.finished, conversation)
        case "Notification":
            let type = json["notification_type"] as? String ?? ""
            let asks = ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"]
            return (asks.contains(type) ? .needsInput : nil, conversation)
        default: return (nil, conversation) // SessionStart and others: only the conversation id
        }
    }
    /// Codex notify payload (the last command-line argument).
    static func parseCodex(_ json: [String: Any]) -> (event: AgentEvent?, conversation: String?) {
        let conversation = json["thread-id"] as? String
        switch json["type"] as? String {
        case "agent-turn-complete": return (.finished, conversation)
        case "approval-requested": return (.needsInput, conversation)
        default: return (nil, conversation)
        }
    }

    // MARK: Configuration passed to the CLIs

    /// Claude hooks for `--settings`. They are merged with the user's own hooks and run
    /// asynchronously, so they never slow Claude down.
    static func claudeHooks(executable: String) -> [String: Any] {
        let hook: [String: Any] = ["type": "command", "command": ShellSafety.quote(executable) + " " + argument + " claude", "async": true]
        let entry: [[String: Any]] = [["hooks": [hook]]]
        return ["SessionStart": entry, "UserPromptSubmit": entry, "Stop": entry, "Notification": entry]
    }
    /// `-c notify=[…]` for Codex. The user's own notify program still runs (chained).
    static func codexNotifyOverride(executable: String) -> String {
        "notify=[" + [executable, argument, "codex"].map(tomlString).joined(separator: ", ") + "]"
    }
    static func tomlString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    /// The top-level `notify = [...]` from `~/.codex/config.toml`, if any.
    static func userCodexNotify(configText: String) -> [String]? {
        for rawLine in configText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return nil } // tables start; notify must be top-level
            guard line.hasPrefix("notify"), let eq = line.firstIndex(of: "=") else { continue }
            guard line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces) == "notify" else { continue }
            return parseStringArray(String(line[line.index(after: eq)...]))
        }
        return nil
    }
    /// Parses a one-line TOML array of basic ("…") or literal ('…') strings.
    static func parseStringArray(_ text: String) -> [String]? {
        var items: [String] = [], chars = Array(text.trimmingCharacters(in: .whitespaces)), i = 0
        guard chars.first == "[" else { return nil }
        i = 1
        while i < chars.count {
            let c = chars[i]
            if c == "]" { return items }
            if c == "\"" || c == "'" {
                let quote = c; var value = ""; i += 1
                while i < chars.count, chars[i] != quote {
                    if quote == "\"", chars[i] == "\\", i + 1 < chars.count {
                        i += 1
                        switch chars[i] { case "n": value.append("\n"); case "t": value.append("\t"); default: value.append(chars[i]) }
                    } else { value.append(chars[i]) }
                    i += 1
                }
                items.append(value)
            }
            i += 1
        }
        return nil
    }

    // MARK: Helper mode

    /// Entry point when a CLI runs NotchAgent as its hook or notify program.
    static func run(_ arguments: [String]) -> Int32 {
        signal(SIGPIPE, SIG_IGN)
        let env = ProcessInfo.processInfo.environment
        let parsed: (event: AgentEvent?, conversation: String?)
        switch arguments.first {
        case "claude":
            let input = FileHandle.standardInput.readDataToEndOfFile()
            parsed = ((try? JSONSerialization.jsonObject(with: input)) as? [String: Any]).map(parseClaude) ?? (nil, nil)
        case "codex":
            let payload = arguments.count > 1 ? arguments[arguments.count - 1] : ""
            parsed = ((try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]).map(parseCodex) ?? (nil, nil)
            chainCodexNotify(payload: payload, env: env)
        default:
            return 0
        }
        if let session = env[sessionVariable], !session.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                notification, object: nil,
                userInfo: ["session": session, "event": parsed.event?.rawValue ?? "", "conversation": parsed.conversation ?? ""],
                deliverImmediately: true)
        }
        return 0
    }
    /// Keeps the user's own Codex notify program working (for example Codex Computer Use).
    private static func chainCodexNotify(payload: String, env: [String: String]) {
        guard let data = env[codexChainVariable]?.data(using: .utf8),
              let argv = try? JSONSerialization.jsonObject(with: data) as? [String], let program = argv.first else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: (program as NSString).expandingTildeInPath)
        process.arguments = Array(argv.dropFirst()) + [payload]
        try? process.run() // not awaited: notify programs must not hold up Codex
    }
}

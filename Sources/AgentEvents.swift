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
    enum CodexNotify: Equatable {
        case absent, command([String]), unsupported
    }
    /// Parse only the top-level notify command. Unknown syntax must not be overridden.
    static func userCodexNotify(configText: String) -> CodexNotify {
        let lines = configText.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { return .absent } // tables start; notify must be top-level
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            guard ["notify", "\"notify\"", "'notify'"].contains(key) else { continue }
            let value = String(line[line.index(after: eq)...]) + "\n" + lines.dropFirst(index + 1).joined(separator: "\n")
            return parseStringArray(value).map(CodexNotify.command) ?? .unsupported
        }
        return .absent
    }
    /// Parses a TOML array of basic ("…") or literal ('…') strings, including multiline arrays.
    static func parseStringArray(_ text: String) -> [String]? {
        let chars = Array(text)
        var items: [String] = [], i = 0
        func skipTrivia() {
            while i < chars.count {
                if chars[i].isWhitespace { i += 1; continue }
                if chars[i] == "#" {
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                    continue
                }
                break
            }
        }
        skipTrivia()
        guard i < chars.count, chars[i] == "[" else { return nil }
        i += 1
        while true {
            skipTrivia()
            guard i < chars.count else { return nil }
            if chars[i] == "]" { return items }
            let quote = chars[i]
            guard quote == "\"" || quote == "'" else { return nil }
            i += 1
            var value = "", closed = false
            while i < chars.count {
                let c = chars[i]; i += 1
                if c == quote { closed = true; break }
                if c == "\n" || c == "\r" { return nil }
                if quote == "\"", c == "\\" {
                    guard i < chars.count else { return nil }
                    let escape = chars[i]; i += 1
                    switch escape {
                    case "\"", "\\": value.append(escape)
                    case "n": value.append("\n")
                    case "t": value.append("\t")
                    case "r": value.append("\r")
                    case "b": value.append("\u{8}")
                    case "f": value.append("\u{c}")
                    case "u", "U":
                        let count = escape == "u" ? 4 : 8
                        guard i + count <= chars.count,
                              let scalar = UInt32(String(chars[i..<(i + count)]), radix: 16).flatMap(Unicode.Scalar.init) else { return nil }
                        value.unicodeScalars.append(scalar); i += count
                    default: return nil
                    }
                } else { value.append(c) }
            }
            guard closed else { return nil }
            items.append(value)
            skipTrivia()
            guard i < chars.count else { return nil }
            if chars[i] == "]" { return items }
            guard chars[i] == "," else { return nil }
            i += 1
        }
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

import os

/// Diagnostics for bug reports (`log show --predicate 'subsystem == "app.notchagent.desktop"'`).
/// Only events and error kinds are logged, never terminal content, paths, or account data.
enum Log {
    static let app = Logger(subsystem: "app.notchagent.desktop", category: "app")
    static let session = Logger(subsystem: "app.notchagent.desktop", category: "session")
    static let usage = Logger(subsystem: "app.notchagent.desktop", category: "usage")
}

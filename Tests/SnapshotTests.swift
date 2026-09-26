import AppKit
import SwiftUI
import XCTest
@testable import NotchAgent

/// Opt-in visual check without screen-recording or accessibility permissions:
/// TEST_RUNNER_NOTCHAGENT_SNAPSHOT_DIR=/dir TEST_RUNNER_NOTCHAGENT_SUPPORT_DIR=/dir/support bash Scripts/test.sh
@MainActor
final class SnapshotTests: XCTestCase {
    func testRenderIslandPhases() throws {
        let env = ProcessInfo.processInfo.environment
        // Also requires a scratch support dir so sample Claude data never touches the real one.
        try XCTSkipUnless(env["NOTCHAGENT_SNAPSHOT_DIR"] != nil && env["NOTCHAGENT_SUPPORT_DIR"] != nil)
        let output = URL(fileURLWithPath: env["NOTCHAGENT_SNAPSHOT_DIR"]!)
        let model = AppModel()
        model.notchHeight = 38
        model.panelWidth = 900; model.panelHeight = 570
        if model.usage.enabled {
            model.usage.refresh()
            let deadline = Date().addingTimeInterval(20)
            while model.usage.isLoading && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        let now = Date().timeIntervalSince1970
        ClaudeStatusLine.record(["five_hour": ["used_percentage": 23, "resets_at": now + 9000],
                                 "seven_day": ["used_percentage": 85, "resets_at": now + 400_000]])
        model.claudeUsage.enabled = true
        model.claudeUsage.reload()
        // Several work folders, one with agents running in the background.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        model.workspaces = ["Desktop", "Desktop/NotchAgents", "Documents"].map { SavedWorkspace(path: home + "/" + $0) }
        model.workspacePath = home + "/Desktop"
        let desktopSessions = (0..<6).map { i in
            TerminalSession(kind: [.codex, .claude, .shell][i % 3], directory: URL(fileURLWithPath: home + "/Desktop"), executable: "/bin/zsh", fontSize: 13)
        }
        model.sessions = desktopSessions + [
                          TerminalSession(kind: .codex, directory: URL(fileURLWithPath: home + "/Desktop/NotchAgents"), executable: "/bin/zsh", fontSize: 13),
                          TerminalSession(kind: .claude, directory: URL(fileURLWithPath: home + "/Desktop/NotchAgents"), executable: "/bin/zsh", fontSize: 13)]
        model.selectedID = desktopSessions.last?.id
        for phase in [IslandPhase.preview, .terminal] {
            model.phase = phase
            let host = NSHostingView(rootView: IslandView(model: model))
            host.frame = NSRect(x: 0, y: 0, width: model.panelWidth + 32, height: model.panelHeight + 32)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.backgroundColor = NSColor(white: 0.85, alpha: 1)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("\(phase).png"))
        }
    }
}

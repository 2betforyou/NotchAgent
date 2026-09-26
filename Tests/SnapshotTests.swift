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
        model.hasPhysicalNotch = true
        model.physicalNotchWidth = 185 // 14-inch MacBook Pro camera housing
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
        // Closed notch: one agent working, one waiting for the user, and a notice.
        let working = model.sessions[7], waiting = model.sessions[6]
        working.recordOutput(at: Date())
        waiting.terminal.onBell?()
        model.phase = .closed
        model.tickActivity()
        model.banner = NotchBanner(sessionID: waiting.id, kind: .claude, reason: .finished, folder: "NotchAgents", shownAt: Date())
        let savedFold = UserDefaults.standard.object(forKey: "showsNewSessionButtons")
        defer { UserDefaults.standard.set(savedFold, forKey: "showsNewSessionButtons") }
        if ProcessInfo.processInfo.environment["NOTCHAGENT_SNAPSHOT_FOLDED"] == "1" { model.showsNewSessionButtons = false }
        if let language = ProcessInfo.processInfo.environment["NOTCHAGENT_SNAPSHOT_LANGUAGE"].flatMap(AppLanguage.init(rawValue:)) {
            AppLanguage.current = language // not persisted: the model's setter is bypassed on purpose
        }
        if let accent = ProcessInfo.processInfo.environment["NOTCHAGENT_SNAPSHOT_ACCENT"].flatMap(Accent.init(rawValue:)) {
            Accent.current = accent
        }
        let savedTheme = UserDefaults.standard.object(forKey: "terminalTheme")
        defer { UserDefaults.standard.set(savedTheme, forKey: "terminalTheme") } // the model persists it
        if let theme = ProcessInfo.processInfo.environment["NOTCHAGENT_SNAPSHOT_THEME"].flatMap(TerminalTheme.init(rawValue:)) {
            model.terminalTheme = theme
        }
        for phase in [IslandPhase.closed, .preview, .terminal] {
            model.phase = phase
            if phase != .closed { model.banner = nil }
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
        let settings = NSHostingView(rootView: SettingsView(model: model, displayChanged: {}))
        settings.frame = NSRect(x: 0, y: 0, width: 590, height: 640)
        let settingsWindow = NSWindow(contentRect: settings.frame, styleMask: [.titled], backing: .buffered, defer: false)
        settingsWindow.contentView = settings
        settings.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = try XCTUnwrap(settings.bitmapImageRepForCachingDisplay(in: settings.bounds))
        settings.cacheDisplay(in: settings.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("settings.png"))
        // Every right-wing state of the closed notch, side by side.
        let states: [NotchStatus] = [.attention(.finished), .attention(.bell), .attention(.exited),
                                     .working(since: Date().addingTimeInterval(-151)), .lowQuota(.claude, remaining: 12), .sessions(3), .empty]
        let strip = NSHostingView(rootView: HStack(spacing: 28) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in NotchStatusView(status: state).frame(width: 40, height: 32) }
        }.padding(12).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark))
        strip.frame = NSRect(x: 0, y: 0, width: 520, height: 56)
        let stripWindow = NSWindow(contentRect: strip.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        stripWindow.contentView = strip
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let stripRep = try XCTUnwrap(strip.bitmapImageRepForCachingDisplay(in: strip.bounds))
        strip.cacheDisplay(in: strip.bounds, to: stripRep)
        try XCTUnwrap(stripRep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("notch-states.png"))
        // Preview footer with the folder chips open, at the preview's content width.
        let footer = NSHostingView(rootView: VStack(spacing: 18) {
            PreviewFolderFooter(model: model)
            PreviewFolderFooter(model: model, choosing: true)
        }.frame(width: 518).padding(26).background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark))
        footer.frame = NSRect(x: 0, y: 0, width: 570, height: 120)
        let footerWindow = NSWindow(contentRect: footer.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        footerWindow.contentView = footer
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let footerRep = try XCTUnwrap(footer.bitmapImageRepForCachingDisplay(in: footer.bounds))
        footer.cacheDisplay(in: footer.bounds, to: footerRep)
        try XCTUnwrap(footerRep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("footer.png"))
    }
}

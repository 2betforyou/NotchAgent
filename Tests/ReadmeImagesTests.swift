import AppKit
import SwiftUI
import XCTest
@testable import NotchAgent

/// Renders the README screenshots from the real views with sample data only (no personal folders,
/// accounts, or terminal output). Opt-in; run `bash Scripts/readme-images.sh`.
@MainActor
final class ReadmeImagesTests: XCTestCase {
    private var output: URL!
    private var defaults: UserDefaults!
    private var suite = ""
    private var sessions: [TerminalSession] = []
    private var scratch: URL!

    override func setUp() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["NOTCHAGENT_README_DIR"] != nil && env["NOTCHAGENT_SUPPORT_DIR"] != nil)
        output = URL(fileURLWithPath: env["NOTCHAGENT_README_DIR"]!)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        suite = "NotchAgent.readme.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) // never the user's real settings
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentReadme-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        for folder in folders { try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true) }
    }
    override func tearDown() async throws {
        TerminalSession.stopAll(sessions, grace: 0.2)
        defaults?.removePersistentDomain(forName: suite)
        if let scratch { try? FileManager.default.removeItem(at: scratch) }
        AppLanguage.current = .korean
    }

    // MARK: Sample data

    /// Real (empty) folders in the scratch dir, so chips show folder icons, not "missing" marks.
    private var folders: [String] { ["my-app", "website", "notes"].map { scratch.appendingPathComponent("Projects/" + $0).path } }
    private func quota(_ fiveHourUsed: Double, _ weekUsed: Double) -> UsageSnapshot {
        let now = Date()
        return UsageSnapshot(windows: [
            UsageWindow(id: "primary", usedPercent: fiveHourUsed, durationMinutes: 300, resetsAt: now.addingTimeInterval(2 * 3600 + 20 * 60)),
            UsageWindow(id: "secondary", usedPercent: weekUsed, durationMinutes: 10080, resetsAt: now.addingTimeInterval(4 * 86400))
        ], fetchedAt: now)
    }
    /// The language being rendered; images go to `docs/images/<en|ko>/`.
    private var language = AppLanguage.english
    private func makeModel(repository: RepositoryStatusService? = nil) -> AppModel {
        let codex = UsageService(snapshot: quota(32, 58))
        codex.enabled = true
        let model = AppModel(defaults: defaults, usage: codex, repositoryStatus: repository)
        AppLanguage.current = language
        let now = Date().timeIntervalSince1970
        ClaudeStatusLine.record(["five_hour": ["used_percentage": 23, "resets_at": now + 9000],
                                 "seven_day": ["used_percentage": 41, "resets_at": now + 400_000]])
        model.claudeUsage.enabled = true
        model.claudeUsage.reload()
        model.workspaces = folders.map { SavedWorkspace(path: $0) }
        model.workspacePath = folders[0]
        model.notchHeight = 32
        model.compactWidth = 285 // 185 pt camera housing + 100
        model.hasPhysicalNotch = true
        model.physicalNotchWidth = 185
        model.panelWidth = 940; model.panelHeight = 600
        return model
    }
    /// A tab whose program prints `text` and waits, so the terminal has real content to draw.
    private func session(_ kind: AgentKind, folder: String, title: String, printing text: String = "") throws -> TerminalSession {
        let script = scratch.appendingPathComponent("tab-\(sessions.count).zsh")
        let body = text.isEmpty ? "sleep 120" : "printf '%b' \(ShellSafety.quote(text))\nsleep 120"
        try ("#!/bin/zsh -f\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let s = TerminalSession(kind: kind, directory: URL(fileURLWithPath: folder), executable: script.path,
                                fontSize: 13, customTitle: title)
        sessions.append(s)
        return s
    }

    // MARK: Rendering

    private func render<V: View>(_ view: V, size: CGSize, settle: TimeInterval = 0.8) throws -> NSImage {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.backgroundColor = .clear
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
    private func save(_ image: NSImage, _ name: String) throws {
        let folder = output.appendingPathComponent(language == .korean ? "ko" : "en")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name))
    }
    /// Draws at 2x into a canvas of `size` points.
    private func canvas(_ size: CGSize, _ draw: () -> Void) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size); image.addRepresentation(rep)
        return image
    }
    private func wallpaper(_ rect: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.16, blue: 0.30, alpha: 1),
                            NSColor(srgbRed: 0.27, green: 0.20, blue: 0.40, alpha: 1),
                            NSColor(srgbRed: 0.10, green: 0.24, blue: 0.30, alpha: 1)])!.draw(in: rect, angle: -35)
    }
    /// A dark menu bar with neutral placeholder menus and the NotchAgent status item.
    private func menuBar(width: CGFloat, top: CGFloat) {
        NSColor(white: 0.08, alpha: 0.55).setFill()
        NSRect(x: 0, y: top - 32, width: width, height: 32).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.85)]
        (L("파일      편집      보기      윈도우      도움말", "File      Edit      View      Window      Help") as NSString).draw(at: NSPoint(x: 22, y: top - 24), withAttributes: attrs)
        (L("월 9:41", "Mon 9:41") as NSString).draw(at: NSPoint(x: width - 84, y: top - 24), withAttributes: attrs)
        let icon = MenuBarIcon.make()
        let tinted = NSImage(size: icon.size, flipped: false) { r in icon.draw(in: r); NSColor(white: 1, alpha: 0.85).set(); r.fill(using: .sourceAtop); return true }
        tinted.draw(in: NSRect(x: width - 118, y: top - 25, width: 18, height: 18))
    }

    // MARK: Images

    func testRenderReadmeImages() throws {
        for language in [AppLanguage.english, .korean] {
            self.language = language
            AppLanguage.current = language
            defaults.removePersistentDomain(forName: suite) // recent activity is saved; start each language clean
            try heroImage()
            try notchStatesImage()
            try terminalImage()
            try homeImage()
        }
    }

    /// Menu bar with the preview open beneath the notch.
    private func heroImage() throws {
        let model = makeModel()
        let tab = try session(.claude, folder: folders[0], title: L("로그인 폼 검증", "Login form validation"))
        tab.start()
        let other = try session(.codex, folder: folders[1], title: L("빌드 오류 수정", "Fix build error"))
        other.start()
        model.sessions = [tab, other]
        model.selectedID = tab.id
        model.recordActivity(.finished, for: other, now: Date().addingTimeInterval(-180))
        model.recordActivity(.bell, for: tab, now: Date().addingTimeInterval(-40))
        model.phase = .preview
        let island = try render(IslandView(model: model), size: CGSize(width: model.panelWidth + 32, height: model.hostHeight + 32), settle: 1.2)
        let size = CGSize(width: 1512, height: model.previewHeight + 40) // the view measured itself while rendering
        let image = canvas(size) {
            wallpaper(NSRect(origin: .zero, size: size))
            menuBar(width: size.width, top: size.height)
            island.draw(in: NSRect(x: (size.width - island.size.width) / 2, y: size.height - island.size.height,
                                   width: island.size.width, height: island.size.height))
        }
        try save(image, "hero.png")
    }

    /// The closed notch in each state, each on its own strip of menu bar.
    private func notchStatesImage() throws {
        var rows: [(String, String, NSImage)] = []
        func closed(_ label: String, _ note: String, height: CGFloat = 44, _ setup: (AppModel) throws -> Void) throws {
            let model = makeModel()
            try setup(model)
            model.phase = .closed
            // IslandView has a fixed, top-aligned frame; render it whole and keep the top strip.
            let full = try render(IslandView(model: model), size: CGSize(width: model.panelWidth + 32, height: model.hostHeight + 32))
            let strip = NSImage(size: CGSize(width: full.size.width, height: height), flipped: false) { rect in
                full.draw(in: rect, from: NSRect(x: 0, y: full.size.height - height, width: full.size.width, height: height), operation: .copy, fraction: 1)
                return true
            }
            rows.append((label, note, strip))
        }
        func working(_ kind: AgentKind, for seconds: TimeInterval) throws -> TerminalSession {
            let s = try session(kind, folder: folders[0], title: "task"); s.start()
            for x in stride(from: seconds, through: 0, by: -1.5) { s.recordOutput(at: Date().addingTimeInterval(-x)) }
            _ = s.tick(now: Date(), visible: false)
            return s
        }
        try closed(L("대기", "Idle"), L("숫자: 5시간 사용률 · 링: 주간 사용률", "Number: 5-hour quota used · ring: weekly quota used")) { _ in }
        try closed(L("작업 시작", "Working"), L("첫 1분은 •••", "••• for the first minute")) { m in
            m.sessions = [try working(.claude, for: 6)]
        }
        try closed(L("작업 중", "Still working"), L("1분이 지나면 경과 시간", "Elapsed time after a minute")) { m in
            m.sessions = [try working(.claude, for: 150)]
        }
        try closed(L("여러 세션 작업 중", "Several working"), L("선택: 작업 중인 세션 수", "Optional: number of working sessions")) { m in
            m.notchShowsWorkCount = true
            m.sessions = [try working(.claude, for: 150), try working(.codex, for: 40)]
        }
        try closed(L("완료 알림", "Completion notice"), L("약 6초 뒤 사라지고 최근 활동에 남음", "Fades after about 6 seconds; kept in Recent Activity"), height: 96) { m in
            let s = try session(.codex, folder: folders[0], title: L("빌드 오류 수정", "Fix build error")); s.start()
            m.sessions = [s]
            m.banner = NotchBanner(sessionID: s.id, kind: .codex, reason: .finished, folder: "my-app", shownAt: Date())
        }
        let gap: CGFloat = 20, width: CGFloat = 1512
        let heights = rows.map { max(64, $0.2.size.height + gap) }
        let size = CGSize(width: width, height: heights.reduce(0, +) + 24)
        let image = canvas(size) {
            wallpaper(NSRect(origin: .zero, size: size))
            var top = size.height - 12
            for (index, row) in rows.enumerated() {
                NSColor(white: 0.08, alpha: 0.55).setFill()
                NSRect(x: 0, y: top - 32, width: width, height: 32).fill()
                row.2.draw(in: NSRect(x: (width - row.2.size.width) / 2, y: top - row.2.size.height, width: row.2.size.width, height: row.2.size.height))
                (row.0 as NSString).draw(at: NSPoint(x: 24, y: top - 24), withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white])
                (row.1 as NSString).draw(at: NSPoint(x: 24, y: top - 50), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 1, alpha: 0.7)])
                top -= heights[index]
            }
        }
        try save(image, "notch-states.png")
    }

    /// The expanded workspace with a sample agent transcript.
    private func terminalImage() throws {
        let model = makeModel()
        let transcript = [
            "\\033[1m> " + L("로그인 폼에 이메일 형식 검사를 추가해 줘", "Add email format validation to the login form") + "\\033[0m\\r\\n\\r\\n",
            "\\033[38;5;173m●\\033[0m " + L("LoginForm에 이메일 검사를 추가하고 테스트를 실행하겠습니다.", "I'll add email validation to LoginForm and run the tests.") + "\\r\\n\\r\\n",
            "\\033[2m  ⎿ Read\\033[0m src/components/LoginForm.tsx\\r\\n",
            "\\033[2m  ⎿ Edit\\033[0m src/components/LoginForm.tsx \\033[32m+18\\033[0m \\033[31m-2\\033[0m\\r\\n",
            "\\033[2m  ⎿ Run\\033[0m  npm test -- LoginForm\\r\\n",
            "\\033[32m     ✓ 12 passed\\033[0m\\r\\n\\r\\n",
            "\\033[38;5;173m●\\033[0m " + L("이메일 형식이 맞지 않으면 입력란 아래에 안내가 보입니다. 테스트 12개가 모두 통과했습니다.", "Invalid emails now show a hint under the field. All 12 tests pass.") + "\\r\\n\\r\\n",
            "\\033[1m> \\033[0m"
        ].joined()
        let main = try session(.claude, folder: folders[0], title: L("로그인 폼 검증", "Login form validation"), printing: transcript)
        let second = try session(.codex, folder: folders[0], title: L("API 문서 정리", "Tidy API docs"))
        let shell = try session(.shell, folder: folders[0], title: "dev server")
        second.start(); shell.start()
        model.sessions = [main, second, shell]
        model.selectedID = main.id
        model.phase = .terminal
        let image = try render(IslandView(model: model), size: CGSize(width: model.panelWidth + 32, height: model.hostHeight + 32), settle: 2.0)
        let size = CGSize(width: 1512, height: image.size.height + 20)
        let framed = canvas(size) {
            wallpaper(NSRect(origin: .zero, size: size))
            menuBar(width: size.width, top: size.height)
            image.draw(in: NSRect(x: (size.width - image.size.width) / 2, y: size.height - image.size.height, width: image.size.width, height: image.size.height))
        }
        try save(framed, "workspace.png")
    }

    /// Project Home: activity heatmap and repository row. The repository is sample data, so no
    /// git or gh command runs and nothing about real repositories appears.
    private func homeImage() throws {
        let path = Workspaces.normalize(folders[0])
        var days: [String: Int] = [:]
        let calendar = Calendar.current
        for offset in 0..<84 {
            let date = calendar.date(byAdding: .day, value: -offset, to: Date())!
            let weekday = calendar.component(.weekday, from: date)
            let base = (weekday == 1 || weekday == 7) ? 1 : 4
            let count = (offset * 7 + offset / 3) % 9 < 3 ? 0 : base + (offset * 5) % 7
            if count > 0 { days[ProjectActivity.dayKey(date, calendar: calendar)] = count }
        }
        defaults.set(try JSONEncoder().encode([path: days]), forKey: "projectActivityV1")
        defaults.set(true, forKey: "repositoryGitHubEnabled")
        let github = GitHubRepository(owner: "you", name: "my-app")
        let sample = RepositorySnapshot(
            // A root that doesn't exist keeps the sample size: measuring it fails instead of reading 0 KB.
            root: path + "/.readme-sample", branch: "feature/login-validation", detached: false, changedFiles: 3, repository: github,
            pullRequest: RepositoryPullRequest(number: 42, title: "Validate email on the login form",
                                               url: URL(string: "https://github.com/you/my-app/pull/42")!,
                                               draft: false, review: "APPROVED", checks: .passed),
            sizeBytes: 184_000_000, sizeCalculatedAt: Date())
        let repository = RepositoryStatusService(defaults: defaults, snapshot: sample, load: { _, _ in sample })
        let model = makeModel(repository: repository)
        let claude = try session(.claude, folder: folders[0], title: L("로그인 폼 검증", "Login form validation"))
        let codex = try session(.codex, folder: folders[0], title: L("API 문서 정리", "Tidy API docs"))
        claude.start(); codex.start()
        model.sessions = [claude, codex]
        model.selectHome()
        model.phase = .terminal
        let image = try render(IslandView(model: model), size: CGSize(width: model.panelWidth + 32, height: model.hostHeight + 32), settle: 1.5)
        let size = CGSize(width: 1512, height: image.size.height + 20)
        let framed = canvas(size) {
            wallpaper(NSRect(origin: .zero, size: size))
            menuBar(width: size.width, top: size.height)
            image.draw(in: NSRect(x: (size.width - image.size.width) / 2, y: size.height - image.size.height, width: image.size.width, height: image.size.height))
        }
        try save(framed, "home.png")
    }
}

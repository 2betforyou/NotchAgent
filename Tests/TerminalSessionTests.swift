import AppKit
import SwiftTerm
import XCTest
@testable import NotchAgent

/// Runs real PTY sessions through the same TerminalSession/AgentTerminalView path the app uses.
@MainActor
final class TerminalSessionTests: XCTestCase {
    private var directory: URL!
    private var sessions: [TerminalSession] = []

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotchAgentTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        for session in sessions { session.stop(grace: 0.2) }
        sessions = []
        try? FileManager.default.removeItem(at: directory)
    }

    /// Starts `body` as a zsh script inside a session, exactly like an agent CLI launch.
    private func session(running body: String) throws -> TerminalSession {
        let script = directory.appendingPathComponent("script-\(sessions.count).zsh")
        try ("#!/bin/zsh -f\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let session = TerminalSession(kind: .codex, directory: directory, executable: script.path, fontSize: 13)
        sessions.append(session)
        session.start()
        XCTAssertTrue(session.terminal.process.running)
        return session
    }
    private func path(_ name: String) -> String { directory.appendingPathComponent(name).path }
    private func contents(_ name: String) -> String? { try? String(contentsOfFile: path(name), encoding: .utf8) }
    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        return condition()
    }
    private func lineReader(into file: String) throws -> TerminalSession {
        try session(running: "print ready > \(ShellSafety.quote(path("ready")))\nwhile IFS= read -r line; do print -r -- \"$line\" >> \(ShellSafety.quote(path(file))); done")
    }
    private func noRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func testDroppedFilePathsReachPTYWithoutSubmitting() throws {
        let s = try lineReader(into: "out")
        XCTAssertTrue(waitUntil { self.contents("ready") != nil })
        let files = [directory.appendingPathComponent("screen shot.png"), directory.appendingPathComponent("it's a file.txt")]
        XCTAssertTrue(s.terminal.insertDroppedFiles(files))
        XCTAssertNil(contents("out"), "dropping must not submit the input")
        s.terminal.send(txt: "\r")
        XCTAssertTrue(waitUntil { self.contents("out") != nil })
        XCTAssertEqual(contents("out"), FileDrop.text(for: files)! + "\n")
    }
    func testDroppedImageWithoutAFilePathIsSavedAndInserted() throws {
        let s = try lineReader(into: "out")
        XCTAssertTrue(waitUntil { self.contents("ready") != nil })
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NotchAgentImageDrop-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        pasteboard.setData(png, forType: .png)
        XCTAssertTrue(s.terminal.acceptFileDrop(pasteboard))
        s.terminal.send(txt: "\r")
        XCTAssertTrue(waitUntil { self.contents("out") != nil })
        let quoted = try XCTUnwrap(contents("out")).trimmingCharacters(in: .whitespacesAndNewlines)
        let file = URL(fileURLWithPath: String(quoted.dropFirst().dropLast()))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        XCTAssertEqual(file.lastPathComponent, "Dropped Image.png")
        XCTAssertEqual(try Data(contentsOf: file), png)
    }

    // MARK: Exit codes

    func testWaitStatusDecoding() {
        XCTAssertEqual(ProcessCleanup.exitCode(fromWaitStatus: 0), 0)
        XCTAssertEqual(ProcessCleanup.exitCode(fromWaitStatus: 3 << 8), 3)
        XCTAssertEqual(ProcessCleanup.exitCode(fromWaitStatus: 255 << 8), 255)
        XCTAssertEqual(ProcessCleanup.exitCode(fromWaitStatus: SIGKILL), 128 + SIGKILL)
    }
    func testExitCodeIsShellStatusNotRawWaitStatus() throws {
        let s = try session(running: "exit 3")
        XCTAssertTrue(waitUntil { s.ended })
        XCTAssertEqual(s.exitCode, 3)
    }
    func testSuccessfulExitIsZero() throws {
        let s = try session(running: "true")
        XCTAssertTrue(waitUntil { s.ended })
        XCTAssertEqual(s.exitCode, 0)
    }

    // MARK: Korean input method

    func testComposedHangulReachesPTYOnlyWhenCommitted() throws {
        let s = try lineReader(into: "out")
        XCTAssertTrue(waitUntil { self.contents("ready") != nil })
        let t = s.terminal
        // Keystrokes ㅎ ㅏ ㄴ ㄱ ㅡ ㄹ as delivered by the 2-Set Korean input method.
        t.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        XCTAssertTrue(t.hasMarkedText())
        t.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        t.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        XCTAssertEqual(t.markedRange(), NSRange(location: 0, length: 1))
        t.insertText("한", replacementRange: noRange())
        XCTAssertFalse(t.hasMarkedText())
        t.setMarkedText("ㄱ", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        t.setMarkedText("글", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        t.insertText(NSAttributedString(string: "글"), replacementRange: noRange()) // attributed commit must not be dropped
        t.insertText(" 입력 ✓", replacementRange: noRange())
        t.send(txt: "\r")
        XCTAssertTrue(waitUntil { self.contents("out") != nil })
        XCTAssertEqual(contents("out"), "한글 입력 ✓\n")
    }
    func testControlKeyCommitsPendingSyllableFirst() throws {
        let s = try lineReader(into: "out")
        XCTAssertTrue(waitUntil { self.contents("ready") != nil })
        s.terminal.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        let controlA = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1}", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        s.terminal.commitComposition(before: controlA)
        XCTAssertFalse(s.terminal.hasMarkedText())
        s.terminal.send(txt: "\r")
        XCTAssertTrue(waitUntil { self.contents("out") != nil })
        XCTAssertEqual(contents("out"), "한\n")
    }
    func testPlainKeysDoNotCommitComposition() throws {
        let s = try lineReader(into: "out")
        s.terminal.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: noRange())
        let plain = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40))
        s.terminal.commitComposition(before: plain)
        XCTAssertEqual(s.terminal.markedText, "하")
    }

    /// Replays what the macOS 2-Set Korean input method does inside interpretKeyEvents for each
    /// physical key, so SwiftTerm's own keyDown/kitty path runs exactly as with a real keyboard.
    final class ScriptedIMEView: AgentTerminalView {
        var script: [(commit: String?, marked: String?, command: Selector?)] = []
        override func interpretKeyEvents(_ eventArray: [NSEvent]) {
            let step = script.removeFirst()
            if let commit = step.commit { insertText(commit, replacementRange: NSRange(location: NSNotFound, length: 0)) }
            if let marked = step.marked { setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
            if let command = step.command { doCommand(by: command) }
        }
    }
    private func key(_ chars: String, _ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }
    /// 안녕 + Enter typed with the 2-Set layout (d k s s u d ⏎) into a program that enabled the
    /// kitty keyboard protocol with the flags Codex uses (disambiguate | events | alternates).
    private func typeAnnyeong(kittyFlags: Int?) throws -> String? {
        let script = directory.appendingPathComponent("reader.zsh")
        try "#!/bin/zsh -f\nprint ready > \(ShellSafety.quote(path("ready")))\nIFS= read -r line\nprint -r -- \"$line\" > \(ShellSafety.quote(path("out")))\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let view = ScriptedIMEView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        view.startProcess(executable: script.path, environment: ShellSafety.environment().map { "\($0.key)=\($0.value)" }, currentDirectory: directory.path)
        defer { view.terminate() }
        XCTAssertTrue(waitUntil { self.contents("ready") != nil })
        if let kittyFlags { view.feed(text: "\u{1b}[>\(kittyFlags)u") } // as if the CLI had printed it
        view.script = [
            (nil, "ㅇ", nil), (nil, "아", nil), (nil, "안", nil),
            ("안", "ㄴ", nil),                    // second ㄴ starts a new syllable and commits 안
            (nil, "녀", nil), (nil, "녕", nil),
            ("녕", nil, #selector(NSResponder.insertNewline(_:)))
        ]
        for (chars, code) in [("ㅇ", 2), ("ㅏ", 40), ("ㄴ", 1), ("ㄴ", 1), ("ㅕ", 32), ("ㅇ", 2), ("\r", 36)] as [(String, UInt16)] {
            view.keyDown(with: key(chars, code))
        }
        _ = waitUntil(3) { self.contents("out") != nil }
        return contents("out")
    }
    func testHangulSyllableBoundaryWithKittyKeyboardProtocol() throws {
        XCTAssertEqual(try typeAnnyeong(kittyFlags: 7), "안녕\n")
    }
    func testHangulSyllableBoundaryInPlainShell() throws {
        XCTAssertEqual(try typeAnnyeong(kittyFlags: nil), "안녕\n")
    }

    // MARK: ANSI / TUI / scrolling

    func testANSIColorsAlternateScreenAndScrollback() {
        let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 300))
        let terminal = view.getTerminal()
        view.feed(text: "\u{1b}[31mR\u{1b}[0mN")
        XCTAssertEqual(terminal.getCharData(col: 0, row: 0)?.attribute.fg, .ansi256(code: 1))
        XCTAssertEqual(terminal.getCharData(col: 1, row: 0)?.attribute.fg, .defaultColor)
        view.feed(text: "\u{1b}[38;2;10;20;30mT")
        XCTAssertEqual(terminal.getCharData(col: 2, row: 0)?.attribute.fg, .trueColor(red: 10, green: 20, blue: 30))
        view.feed(text: "\u{1b}[?1049h")
        XCTAssertTrue(terminal.isCurrentBufferAlternate)
        view.feed(text: "\u{1b}[?1049l")
        XCTAssertFalse(terminal.isCurrentBufferAlternate)
        for i in 0..<300 { view.feed(text: "line \(i)\r\n") }
        let bottom = terminal.buffer.yDisp
        XCTAssertGreaterThan(bottom, 200)
        view.scrollUp(lines: 50)
        XCTAssertEqual(terminal.buffer.yDisp, bottom - 50)
        view.scrollDown(lines: 50)
        XCTAssertEqual(terminal.buffer.yDisp, bottom)
    }

    // MARK: Lifetime

    func testSessionKeepsRunningWhileDetachedFromView() throws {
        let s = try lineReader(into: "out")
        XCTAssertTrue(waitUntil { self.contents("ready") != nil })
        let host = NSView(), other = NSView()
        host.addSubview(s.terminal)
        s.terminal.removeFromSuperview() // notch collapsed
        s.terminal.send(txt: "hidden\r")
        other.addSubview(s.terminal)     // reopened on another tab host
        s.terminal.send(txt: "shown\r")
        XCTAssertTrue(waitUntil { self.contents("out") == "hidden\nshown\n" })
        XCTAssertFalse(s.ended)
    }
    func testStopKillsChildrenThatIgnoreHangupAndReapsShell() throws {
        let s = try session(running: "trap '' HUP TERM\nsleep 1000 &\nprint $! > \(ShellSafety.quote(path("child")))\nwhile true; do sleep 0.2; done")
        XCTAssertTrue(waitUntil { (self.contents("child") ?? "").hasSuffix("\n") })
        let child = try XCTUnwrap(pid_t(contents("child")!.trimmingCharacters(in: .whitespacesAndNewlines)))
        let shell = s.terminal.process.shellPid
        XCTAssertEqual(kill(child, 0), 0)
        s.stop(grace: 0.3)
        XCTAssertTrue(s.ended)
        XCTAssertTrue(waitUntil(3) { kill(child, 0) != 0 }, "a child ignoring SIGHUP/SIGTERM survived")
        var status: Int32 = 0
        XCTAssertEqual(waitpid(shell, &status, WNOHANG), -1, "shell was not reaped")
        XCTAssertEqual(errno, ECHILD)
    }
    func testStopIsIdempotentAndFastForWellBehavedPrograms() throws {
        let s = try session(running: "sleep 1000")
        let start = Date()
        s.stop()
        s.stop()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.8)
        XCTAssertTrue(s.ended)
    }
    func testScrollbackKeepsLongAgentTranscripts() {
        let s = TerminalSession(kind: .shell, directory: directory, executable: "/bin/zsh", fontSize: 13)
        for i in 0..<3_000 { s.terminal.feed(text: "line \(i)\r\n") }
        XCTAssertGreaterThan(s.terminal.getTerminal().buffer.yDisp, 2_900, "history was truncated")
    }
    func testStopAllEndsEverySessionWithinOneGracePeriod() throws {
        let a = try session(running: "trap '' HUP TERM\nwhile true; do sleep 0.2; done")
        let b = try session(running: "trap '' HUP TERM\nwhile true; do sleep 0.2; done")
        let shells = [a.terminal.process.shellPid, b.terminal.process.shellPid]
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let start = Date()
        TerminalSession.stopAll([a, b], grace: 0.4)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.2, "sessions were waited on one by one")
        XCTAssertTrue(a.ended && b.ended)
        for shell in shells { XCTAssertTrue(waitUntil(2) { kill(shell, 0) != 0 }) }
    }
    // MARK: Close confirmation only when work would be interrupted

    func testIdleShellClosesWithoutAskingButRunningCommandAsks() throws {
        let shell = TerminalSession(kind: .shell, directory: directory, executable: "/bin/zsh", fontSize: 13)
        sessions.append(shell)
        shell.start()
        let model = AppModel()
        model.sessions = [shell]
        var asked = 0
        model.runAlert = { _ in asked += 1; return .alertFirstButtonReturn } // "cancel" if asked
        XCTAssertTrue(waitUntil(10) { !shell.isBusy && shell.terminal.getTerminal().buffer.x > 0 }, "prompt drawn")
        shell.terminal.send(txt: "sleep 5\r")
        XCTAssertTrue(waitUntil(5) { shell.isBusy }, "a running command counts as work")
        model.closeSession(shell)
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(model.sessions.count, 1, "cancelled, so the session stays")
        shell.terminal.send(data: [3]) // Ctrl-C back to the prompt
        XCTAssertTrue(waitUntil(5) { !shell.isBusy })
        model.closeSession(shell)
        XCTAssertEqual(asked, 1, "an idle prompt closes without a question")
        XCTAssertTrue(model.sessions.isEmpty)
    }
    func testRunningAgentAlwaysRequiresCloseConfirmation() throws {
        let agent = try session(running: "while true; do sleep 1; done") // an idle agent waiting for input
        XCTAssertTrue(agent.isBusy)
        agent.recordOutput(at: Date())
        _ = agent.tick(now: Date(), visible: true)
        XCTAssertTrue(agent.isBusy)
        _ = agent.tick(now: Date().addingTimeInterval(5), visible: true)
        XCTAssertTrue(agent.isBusy)
        let model = AppModel()
        model.sessions = [agent]
        var asked = false
        model.runAlert = { _ in asked = true; return .alertFirstButtonReturn }
        model.closeSession(agent)
        XCTAssertTrue(asked)
        XCTAssertTrue(agent.isRunning)
    }
}

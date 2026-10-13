import AppKit
import Testing
@testable import NotchAgent

@MainActor
@Test("Full-width Korean glyphs use a two-cell cursor")
func fullWidthKoreanCursor() {
    let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    let singleCellWidth = view.caretFrame.width

    view.feed(text: "한\r")
    view.setFrameSize(view.frame.size)

    #expect(view.getTerminal().getCharData(col: 0, row: 0)?.width == 2)
    #expect(view.getTerminal().getCursorLocation().x == 0)
    #expect(view.caretFrame.width == singleCellWidth * 2)

    view.feed(text: "\u{1b}[2C")
    view.setFrameSize(view.frame.size)
    #expect(view.caretFrame.width == singleCellWidth)

}

@MainActor
@Test("Replacing a wide Korean cell clears its old inverse-color continuation")
func overwriteWideKoreanCell() {
    let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let terminal = view.getTerminal()
    view.feed(text: "\u{1b}[?1049h\u{1b}[7m한\u{1b}[0m\rA")

    #expect(terminal.getCharacter(for: terminal.getCharData(col: 0, row: 0)!) == "A")
    #expect(terminal.getCharData(col: 1, row: 0)?.width == 1)
    #expect(terminal.getCharData(col: 1, row: 0)?.attribute.style.contains(.inverse) == false)
}

@MainActor
@Test("Replacing the trailing half of a wide Korean cell clears its leading half")
func overwriteWideKoreanContinuation() {
    let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let terminal = view.getTerminal()
    view.feed(text: "\u{1b}[?1049h\u{1b}[7m한\u{1b}[0m\u{1b}[1;2Hx")

    #expect(terminal.getCharData(col: 0, row: 0)?.width == 1)
    #expect(terminal.getCharData(col: 0, row: 0)?.attribute.style.contains(.inverse) == false)
    #expect(terminal.getCharacter(for: terminal.getCharData(col: 1, row: 0)!) == "x")
}

@MainActor
@Test("Non-ASCII narrow overwrite also clears the old wide cell")
func overwriteWideKoreanWithNarrowUnicode() {
    let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let terminal = view.getTerminal()
    view.feed(text: "\u{1b}[?1049h\u{1b}[7m한\u{1b}[0m\rπ")

    #expect(terminal.getCharacter(for: terminal.getCharData(col: 0, row: 0)!) == "π")
    #expect(terminal.getCharData(col: 1, row: 0)?.width == 1)
    #expect(terminal.getCharData(col: 1, row: 0)?.attribute.style.contains(.inverse) == false)
}

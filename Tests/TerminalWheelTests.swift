import AppKit
import SwiftTerm
import Testing

private final class WheelCapture: TerminalViewDelegate {
    var sent: [UInt8] = []

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        sent.append(contentsOf: data)
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor
@Test("Wheel scroll reaches full-screen terminal apps")
func alternateScreenWheelDelivery() throws {
    let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let capture = WheelCapture()
    view.terminalDelegate = capture
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    let upEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                       wheel1: 1, wheel2: 0, wheel3: 0))
    let downEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                         wheel1: -1, wheel2: 0, wheel3: 0))
    upEvent.location = window.convertToScreen(NSRect(x: 40, y: 40, width: 0, height: 0)).origin
    downEvent.location = upEvent.location
    let wheelUp = try #require(NSEvent(cgEvent: upEvent))
    let wheelDown = try #require(NSEvent(cgEvent: downEvent))

    view.feed(text: "\u{1b}[?1049h")
    #expect(view.getTerminal().isCurrentBufferAlternate)
    view.scrollWheel(with: wheelUp)
    #expect(capture.sent == [27, 91, 53, 126]) // Page Up if the app did not request mouse events.

    view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
    capture.sent = []
    view.scrollWheel(with: wheelUp)
    #expect(String(decoding: capture.sent, as: UTF8.self).contains("\u{1b}[<64;"))
    capture.sent = []
    view.scrollWheel(with: wheelDown)
    #expect(String(decoding: capture.sent, as: UTF8.self).contains("\u{1b}[<65;"))

    view.feed(text: "\u{1b}[?1000l\u{1b}[?1006l\u{1b}[?1049l")
    for index in 0..<100 { view.feed(text: "line \(index)\r\n") }
    let bottom = view.getTerminal().buffer.yDisp
    #expect(bottom > 0)
    view.scrollWheel(with: wheelUp)
    #expect(view.getTerminal().buffer.yDisp < bottom)
}

@MainActor
@Test("Precise scrollback moves by text lines, not pixel count")
func preciseScrollbackWheelSpeed() throws {
    let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    for index in 0..<100 { view.feed(text: "line \(index)\r\n") }
    let bottom = view.getTerminal().buffer.yDisp
    #expect(bottom > 20)

    let upEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                       wheel1: 12, wheel2: 0, wheel3: 0))
    upEvent.location = window.convertToScreen(NSRect(x: 40, y: 40, width: 0, height: 0)).origin
    let wheelUp = try #require(NSEvent(cgEvent: upEvent))
    #expect(wheelUp.hasPreciseScrollingDeltas)
    view.scrollWheel(with: wheelUp)
    view.scrollWheel(with: wheelUp)
    let linesMoved = bottom - view.getTerminal().buffer.yDisp
    #expect((1...3).contains(linesMoved))
}

@MainActor
@Test("SGR mouse movement is not encoded as a button release")
func sgrMouseMotionDoesNotClick() {
    let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
    let capture = WheelCapture()
    view.terminalDelegate = capture
    view.feed(text: "\u{1b}[?1003h\u{1b}[?1006h")

    view.getTerminal().sendMotion(buttonFlags: 3, x: 5, y: 2, pixelX: 0, pixelY: 0)
    #expect(String(decoding: capture.sent, as: UTF8.self) == "\u{1b}[<35;6;3M")

    capture.sent = []
    view.getTerminal().sendEvent(buttonFlags: 3, x: 5, y: 2, pixelX: 0, pixelY: 0)
    #expect(String(decoding: capture.sent, as: UTF8.self) == "\u{1b}[<0;6;3m")

    view.feed(text: "\u{1b}[?1016h")
    capture.sent = []
    view.getTerminal().sendMotion(buttonFlags: 3, x: 5, y: 2, pixelX: 8, pixelY: 9)
    #expect(String(decoding: capture.sent, as: UTF8.self) == "\u{1b}[<35;8;9M")
}

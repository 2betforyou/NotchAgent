import AppKit
import SwiftUI
import XCTest
@testable import NotchAgent

@MainActor
final class StripScrollTests: XCTestCase {
    private struct Strip: View {
        let items: [Int]
        var target: Int?
        var body: some View {
            FadingHScroll(target: target) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { i in Text("Codex session \(i)").frame(width: 140, height: 30).id(i) }
                }
            }.frame(width: 400, height: 32)
        }
    }
    private func host(_ view: Strip) -> (NSWindow, NSHostingView<Strip>) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 32)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        settle()
        return (window, hosting)
    }
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
    private func strip(in window: NSWindow) throws -> NSScrollView {
        try XCTUnwrap(HorizontalWheel.registered.first { $0.window === window }, "strip scroll view was not registered")
    }

    func testSelectedItemIsScrolledIntoView() throws {
        let (window, hosting) = host(Strip(items: Array(0..<8), target: 0))
        let scroll = try strip(in: window)
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 0, accuracy: 1)
        hosting.rootView = Strip(items: Array(0..<8), target: 7) // e.g. a new session was opened
        settle()
        let visible = scroll.contentView.bounds
        XCTAssertGreaterThan(visible.origin.x, 700, "last tab should be scrolled into view")
        XCTAssertLessThanOrEqual(visible.maxX, (scroll.documentView?.frame.width ?? 0) + 1)
    }
    func testWheelScrollsSidewaysWithinBounds() throws {
        let (window, _) = host(Strip(items: Array(0..<8)))
        let scroll = try strip(in: window)
        XCTAssertTrue(HorizontalWheel.scroll(scroll, by: -120)) // wheel down → move right
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 120, accuracy: 1)
        HorizontalWheel.scroll(scroll, by: -100_000)
        let maxX = (scroll.documentView?.frame.width ?? 0) - scroll.contentView.bounds.width
        XCTAssertEqual(scroll.contentView.bounds.origin.x, maxX, accuracy: 1)
        HorizontalWheel.scroll(scroll, by: 100_000)
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 0, accuracy: 1)
    }
    func testWheelIsNotStolenWhenNothingOverflows() throws {
        let (window, _) = host(Strip(items: [0, 1]))
        let scroll = try strip(in: window)
        XCTAssertFalse(HorizontalWheel.scroll(scroll, by: -120))
    }
}

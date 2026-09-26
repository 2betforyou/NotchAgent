import AppKit
import XCTest
@testable import NotchAgent

@MainActor
final class TerminalBasicsTests: XCTestCase {
    private func model(tabs: Int) -> (AppModel, [TerminalSession]) {
        let model = AppModel()
        let folder = model.workspacePath
        let sessions = (0..<tabs).map { _ in TerminalSession(kind: .claude, directory: URL(fileURLWithPath: folder), executable: "/bin/zsh", fontSize: 13) }
        model.sessions = sessions
        model.selectedID = sessions.first?.id
        return (model, sessions)
    }
    func testNumberKeysPickTabs() {
        let (model, s) = model(tabs: 3)
        XCTAssertTrue(model.handleTabShortcut(key: "3", shift: false))
        XCTAssertEqual(model.selectedID, s[2].id)
        XCTAssertTrue(model.handleTabShortcut(key: "7", shift: false), "consumed even without a 7th tab")
        XCTAssertEqual(model.selectedID, s[2].id)
    }
    func testBracketsCycleTabs() {
        let (model, s) = model(tabs: 3)
        XCTAssertTrue(model.handleTabShortcut(key: "]", shift: true))
        XCTAssertEqual(model.selectedID, s[1].id)
        XCTAssertTrue(model.handleTabShortcut(key: "[", shift: true))
        XCTAssertTrue(model.handleTabShortcut(key: "[", shift: true))
        XCTAssertEqual(model.selectedID, s[2].id, "wraps around")
    }
    func testOtherKeysReachTheTerminal() {
        let (model, _) = model(tabs: 2)
        XCTAssertFalse(model.handleTabShortcut(key: "c", shift: false), "⌘C stays copy")
        XCTAssertFalse(model.handleTabShortcut(key: "k", shift: false))
    }
    func testFindShowsTheTerminalSearchBar() {
        let view = AgentTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        let before = view.subviews.count
        let item = NSMenuItem(title: "Find", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        view.performTextFinderAction(item)
        XCTAssertGreaterThan(view.subviews.count, before, "find bar appears inside the terminal")
    }
}

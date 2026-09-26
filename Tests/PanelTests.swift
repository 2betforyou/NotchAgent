import AppKit
import XCTest
@testable import NotchAgent

@MainActor
final class PanelTests: XCTestCase {
    /// Regression: closing a session from the X button froze the app because its confirmation
    /// alert opened underneath the always-on-top island.
    func testConfirmationAlertIsAboveTheIsland() {
        let panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        let islandLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.level = islandLevel
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }
        let alert = NSAlert()
        alert.messageText = "이 터미널 세션을 종료할까요?"
        alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "세션 종료")
        var seen: (alert: Int, panel: Int, visible: Bool)?
        let probe = Timer(timeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated {
                seen = (alert.window.level.rawValue, panel.level.rawValue, alert.window.isVisible)
                NSApp.stopModal(withCode: .alertSecondButtonReturn)
            }
        }
        RunLoop.main.add(probe, forMode: .modalPanel)
        let response = AppDelegate.runAlert(alert, below: panel)
        XCTAssertEqual(response, .alertSecondButtonReturn)
        let observed = try? XCTUnwrap(seen)
        XCTAssertEqual(observed?.visible, true)
        XCTAssertGreaterThan(observed?.alert ?? 0, observed?.panel ?? .max, "alert must be above the island")
        XCTAssertEqual(panel.level, islandLevel, "island returns above the menu bar afterwards")
    }
}

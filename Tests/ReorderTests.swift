import XCTest
@testable import NotchAgent

final class ReorderTests: XCTestCase {
    func testDraggingRightAndLeft() {
        var items = ["a", "b", "c", "d"]
        Reorder.move(&items, id: "a", onto: "c", key: { $0 })
        XCTAssertEqual(items, ["b", "c", "a", "d"], "dragging right lands after the target")
        Reorder.move(&items, id: "d", onto: "b", key: { $0 })
        XCTAssertEqual(items, ["d", "b", "c", "a"], "dragging left lands before it")
        Reorder.move(&items, id: "x", onto: "b", key: { $0 })
        Reorder.move(&items, id: "b", onto: "b", key: { $0 })
        XCTAssertEqual(items, ["d", "b", "c", "a"], "unknown or same item is a no-op")
    }
    @MainActor func testModelReordersAndRemembers() {
        let d = UserDefaults.standard
        let keys = ["workspace", "workspaces", "savedSessions"]
        let saved = keys.map { d.object(forKey: $0) }
        defer { for (k, v) in zip(keys, saved) { d.set(v, forKey: k) } }
        let model = AppModel()
        model.workspaces = ["/p/a", "/p/b", "/p/c"].map { SavedWorkspace(path: $0) }
        model.moveWorkspace("/p/c", onto: "/p/a")
        XCTAssertEqual(model.workspaces.map(\.path), ["/p/c", "/p/a", "/p/b"])
        XCTAssertEqual(AppModel().workspaces.map(\.path).filter { $0.hasPrefix("/p/") }, ["/p/c", "/p/a", "/p/b"], "order is saved")

        let s = (0..<3).map { _ in TerminalSession(kind: .shell, directory: URL(fileURLWithPath: "/p/a"), executable: "/bin/zsh", fontSize: 13) }
        model.sessions = s
        model.moveSession(s[0].id, onto: s[2].id)
        XCTAssertEqual(model.sessions.map(\.id), [s[1].id, s[2].id, s[0].id])
    }
}

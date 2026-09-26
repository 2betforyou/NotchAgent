import AppKit
import Carbon.HIToolbox
import XCTest
@testable import NotchAgent

final class HotkeyTests: XCTestCase {
    func testDefaultIsControlOptionSpace() {
        XCTAssertEqual(Hotkey.default.label, "⌃⌥Space")
    }
    func testRecordedCombinationUsesAppleModifierOrderAndUSKeyNames() throws {
        let key = try XCTUnwrap(Hotkey(keyCode: UInt16(kVK_ANSI_A), flags: [.command, .shift, .option, .control, .capsLock]))
        XCTAssertEqual(key.label, "⌃⌥⇧⌘A", "caps lock is ignored; A is shown even with a Korean input source")
        XCTAssertEqual(key.modifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(Hotkey(keyCode: UInt16(kVK_F5), flags: [.option])?.label, "⌥F5")
    }
    func testNeedsARealModifierAndARealKey() {
        XCTAssertNil(Hotkey(keyCode: UInt16(kVK_ANSI_K), flags: []), "plain keys would break typing everywhere")
        XCTAssertNil(Hotkey(keyCode: UInt16(kVK_ANSI_K), flags: [.shift]))
        XCTAssertNil(Hotkey(keyCode: UInt16(kVK_Option), flags: [.option]), "a modifier alone is not a shortcut")
    }
    func testRoundTripsThroughStorage() throws {
        let key = try XCTUnwrap(Hotkey(keyCode: UInt16(kVK_ANSI_J), flags: [.command, .option]))
        let decoded = try JSONDecoder().decode(Hotkey.self, from: JSONEncoder().encode(key))
        XCTAssertEqual(decoded, key)
    }
}

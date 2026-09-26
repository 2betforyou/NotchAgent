import AppKit
import Carbon.HIToolbox

/// The global open/close shortcut. Stored as a Carbon key code and modifier mask so it can be
/// registered with RegisterEventHotKey (no Accessibility permission needed).
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = Hotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))

    /// A recorded key press, or nil when it cannot be a global shortcut (needs ⌘, ⌃ or ⌥).
    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection([.command, .control, .option, .shift])
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              !Self.modifierKeyCodes.contains(Int(keyCode)) else { return nil }
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        self.init(keyCode: UInt32(keyCode), modifiers: UInt32(carbon))
    }
    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode; self.modifiers = modifiers
    }

    /// "⌃⌥Space", in Apple's modifier order.
    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(Int(keyCode))
    }

    private static let modifierKeyCodes: Set<Int> = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
                                                     kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
                                                     kVK_CapsLock, kVK_Function]
    /// Names follow the US layout so a Korean input source does not show "ㅁ" for A.
    static func keyName(_ code: Int) -> String {
        let named: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_ANSI_Grave: "`", kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[",
            kVK_ANSI_RightBracket: "]", kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'",
            kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/"
        ]
        if let name = named[code] { return name }
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9"
        ]
        return letters[code] ?? "#\(code)"
    }
}

import CoreGraphics
import Carbon.HIToolbox

/// Injects keystrokes into the frontmost app via CGEvent.
/// Requires Accessibility permission.
enum KeystrokeEngine {

    // MARK: - Public API

    /// Send a single key press (down + up) with optional modifiers.
    static func sendKeystroke(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = flags
        keyUp.flags = flags

        // Tag synthetic events so we can distinguish them from physical input
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    /// Type an arbitrary Unicode string into the frontmost app.
    static func typeString(_ string: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(string.utf16)

        let chunkSize = 20
        for i in stride(from: 0, to: utf16.count, by: chunkSize) {
            let end = min(i + chunkSize, utf16.count)
            var chunk = Array(utf16[i..<end])

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)

            keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
            keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)

            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)

            usleep(4000) // 4ms delay to avoid dropped characters
        }
    }

    // MARK: - Key Code Map

    /// Virtual key codes for all keys on a Mac keyboard (Carbon HIToolbox constants).
    static let keyCodes: [String: CGKeyCode] = [
        // Letters
        "a": CGKeyCode(kVK_ANSI_A), "b": CGKeyCode(kVK_ANSI_B), "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D), "e": CGKeyCode(kVK_ANSI_E), "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G), "h": CGKeyCode(kVK_ANSI_H), "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M), "n": CGKeyCode(kVK_ANSI_N), "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P), "q": CGKeyCode(kVK_ANSI_Q), "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S), "t": CGKeyCode(kVK_ANSI_T), "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V), "w": CGKeyCode(kVK_ANSI_W), "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y), "z": CGKeyCode(kVK_ANSI_Z),
        // Numbers
        "1": CGKeyCode(kVK_ANSI_1), "2": CGKeyCode(kVK_ANSI_2), "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4), "5": CGKeyCode(kVK_ANSI_5), "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7), "8": CGKeyCode(kVK_ANSI_8), "9": CGKeyCode(kVK_ANSI_9),
        "0": CGKeyCode(kVK_ANSI_0),
        // Punctuation / symbols
        "`": CGKeyCode(kVK_ANSI_Grave),
        "-": CGKeyCode(kVK_ANSI_Minus),
        "=": CGKeyCode(kVK_ANSI_Equal),
        "[": CGKeyCode(kVK_ANSI_LeftBracket),
        "]": CGKeyCode(kVK_ANSI_RightBracket),
        "\\": CGKeyCode(kVK_ANSI_Backslash),
        ";": CGKeyCode(kVK_ANSI_Semicolon),
        "'": CGKeyCode(kVK_ANSI_Quote),
        ",": CGKeyCode(kVK_ANSI_Comma),
        ".": CGKeyCode(kVK_ANSI_Period),
        "/": CGKeyCode(kVK_ANSI_Slash),
        // Whitespace / editing
        "space": CGKeyCode(kVK_Space),
        "return": CGKeyCode(kVK_Return),
        "tab": CGKeyCode(kVK_Tab),
        "delete": CGKeyCode(kVK_Delete),           // Backspace
        "forwardDelete": CGKeyCode(kVK_ForwardDelete),
        "escape": CGKeyCode(kVK_Escape),
        // Navigation
        "left": CGKeyCode(kVK_LeftArrow),
        "right": CGKeyCode(kVK_RightArrow),
        "up": CGKeyCode(kVK_UpArrow),
        "down": CGKeyCode(kVK_DownArrow),
        "home": CGKeyCode(kVK_Home),
        "end": CGKeyCode(kVK_End),
        "pageUp": CGKeyCode(kVK_PageUp),
        "pageDown": CGKeyCode(kVK_PageDown),
        // Function keys
        "f1": CGKeyCode(kVK_F1), "f2": CGKeyCode(kVK_F2), "f3": CGKeyCode(kVK_F3),
        "f4": CGKeyCode(kVK_F4), "f5": CGKeyCode(kVK_F5), "f6": CGKeyCode(kVK_F6),
        "f7": CGKeyCode(kVK_F7), "f8": CGKeyCode(kVK_F8), "f9": CGKeyCode(kVK_F9),
        "f10": CGKeyCode(kVK_F10), "f11": CGKeyCode(kVK_F11), "f12": CGKeyCode(kVK_F12),
        "f13": CGKeyCode(kVK_F13), "f14": CGKeyCode(kVK_F14), "f15": CGKeyCode(kVK_F15),
        "f16": CGKeyCode(kVK_F16), "f17": CGKeyCode(kVK_F17), "f18": CGKeyCode(kVK_F18),
        "f19": CGKeyCode(kVK_F19),
        // Modifier key codes (for standalone presses)
        "capsLock": CGKeyCode(kVK_CapsLock),
        "leftShift": CGKeyCode(kVK_Shift),
        "rightShift": CGKeyCode(kVK_RightShift),
        "leftCommand": CGKeyCode(kVK_Command),
        "rightCommand": CGKeyCode(kVK_RightCommand),
        "leftOption": CGKeyCode(kVK_Option),
        "rightOption": CGKeyCode(kVK_RightOption),
        "leftControl": CGKeyCode(kVK_Control),
        "rightControl": CGKeyCode(kVK_RightControl),
        "function": CGKeyCode(kVK_Function),
    ]

    // MARK: - Private

    /// Tag to identify events generated by Tekla.
    private static let syntheticEventTag: Int64 = 0x54454B4C41 // "TEKLA" in hex
}

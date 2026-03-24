import Foundation
import CoreGraphics
import Carbon.HIToolbox

// MARK: - Key Model

/// Represents a single key on the virtual keyboard.
struct KeyModel: Identifiable {
    let id = UUID()
    let label: String
    let action: KeyAction
    var widthMultiplier: CGFloat = 1.0
    /// Label shown when shift is active (for keys with shifted symbols).
    var shiftedLabel: String? = nil
    /// Smaller secondary label shown on the key (e.g., shifted symbol above the number).
    var secondaryLabel: String? = nil
}

// MARK: - Key Action

/// What happens when a key is tapped.
enum KeyAction: Hashable {
    // Characters
    case character(Character)
    // Whitespace / editing
    case space
    case backspace
    case forwardDelete
    case returnKey
    case tab
    case escape
    // Modifiers (sticky — toggle on/off)
    case shift
    case capsLock
    case command
    case option
    case control
    case fn
    case globe
    // Navigation
    case arrowLeft
    case arrowRight
    case arrowUp
    case arrowDown
    case home
    case end
    case pageUp
    case pageDown
    // Function keys
    case functionKey(Int) // F1–F19
}

// MARK: - Full Desktop Layout (Mac TKL — Tenkeyless)

enum KeyboardLayout {

    // MARK: Function Row

    static let functionRow: [KeyModel] = [
        KeyModel(label: "esc", action: .escape, widthMultiplier: 1.0),
        // Gap handled in view
        KeyModel(label: "F1", action: .functionKey(1)),
        KeyModel(label: "F2", action: .functionKey(2)),
        KeyModel(label: "F3", action: .functionKey(3)),
        KeyModel(label: "F4", action: .functionKey(4)),
        // Gap
        KeyModel(label: "F5", action: .functionKey(5)),
        KeyModel(label: "F6", action: .functionKey(6)),
        KeyModel(label: "F7", action: .functionKey(7)),
        KeyModel(label: "F8", action: .functionKey(8)),
        // Gap
        KeyModel(label: "F9", action: .functionKey(9)),
        KeyModel(label: "F10", action: .functionKey(10)),
        KeyModel(label: "F11", action: .functionKey(11)),
        KeyModel(label: "F12", action: .functionKey(12)),
    ]

    // MARK: Main Rows

    static let numberRow: [KeyModel] = [
        KeyModel(label: "`", action: .character("`"), shiftedLabel: "~", secondaryLabel: "~"),
        KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
        KeyModel(label: "2", action: .character("2"), shiftedLabel: "@", secondaryLabel: "@"),
        KeyModel(label: "3", action: .character("3"), shiftedLabel: "#", secondaryLabel: "#"),
        KeyModel(label: "4", action: .character("4"), shiftedLabel: "$", secondaryLabel: "$"),
        KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
        KeyModel(label: "6", action: .character("6"), shiftedLabel: "^", secondaryLabel: "^"),
        KeyModel(label: "7", action: .character("7"), shiftedLabel: "&", secondaryLabel: "&"),
        KeyModel(label: "8", action: .character("8"), shiftedLabel: "*", secondaryLabel: "*"),
        KeyModel(label: "9", action: .character("9"), shiftedLabel: "(", secondaryLabel: "("),
        KeyModel(label: "0", action: .character("0"), shiftedLabel: ")", secondaryLabel: ")"),
        KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
        KeyModel(label: "=", action: .character("="), shiftedLabel: "+", secondaryLabel: "+"),
        KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
    ]

    static let tabRow: [KeyModel] = [
        KeyModel(label: "⇥", action: .tab, widthMultiplier: 1.6),
        KeyModel(label: "Q", action: .character("q")),
        KeyModel(label: "W", action: .character("w")),
        KeyModel(label: "E", action: .character("e")),
        KeyModel(label: "R", action: .character("r")),
        KeyModel(label: "T", action: .character("t")),
        KeyModel(label: "Y", action: .character("y")),
        KeyModel(label: "U", action: .character("u")),
        KeyModel(label: "I", action: .character("i")),
        KeyModel(label: "O", action: .character("o")),
        KeyModel(label: "P", action: .character("p")),
        KeyModel(label: "[", action: .character("["), shiftedLabel: "{", secondaryLabel: "{"),
        KeyModel(label: "]", action: .character("]"), shiftedLabel: "}", secondaryLabel: "}"),
        KeyModel(label: "\\", action: .character("\\"), shiftedLabel: "|", secondaryLabel: "|"),
    ]

    static let capsRow: [KeyModel] = [
        KeyModel(label: "⇪", action: .capsLock, widthMultiplier: 1.8),
        KeyModel(label: "A", action: .character("a")),
        KeyModel(label: "S", action: .character("s")),
        KeyModel(label: "D", action: .character("d")),
        KeyModel(label: "F", action: .character("f")),
        KeyModel(label: "G", action: .character("g")),
        KeyModel(label: "H", action: .character("h")),
        KeyModel(label: "J", action: .character("j")),
        KeyModel(label: "K", action: .character("k")),
        KeyModel(label: "L", action: .character("l")),
        KeyModel(label: ";", action: .character(";"), shiftedLabel: ":", secondaryLabel: ":"),
        KeyModel(label: "'", action: .character("'"), shiftedLabel: "\"", secondaryLabel: "\""),
        KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.8),
    ]

    static let shiftRow: [KeyModel] = [
        KeyModel(label: "⇧", action: .shift, widthMultiplier: 2.3),
        KeyModel(label: "Z", action: .character("z")),
        KeyModel(label: "X", action: .character("x")),
        KeyModel(label: "C", action: .character("c")),
        KeyModel(label: "V", action: .character("v")),
        KeyModel(label: "B", action: .character("b")),
        KeyModel(label: "N", action: .character("n")),
        KeyModel(label: "M", action: .character("m")),
        KeyModel(label: ",", action: .character(","), shiftedLabel: "<", secondaryLabel: "<"),
        KeyModel(label: ".", action: .character("."), shiftedLabel: ">", secondaryLabel: ">"),
        KeyModel(label: "/", action: .character("/"), shiftedLabel: "?", secondaryLabel: "?"),
        KeyModel(label: "⇧", action: .shift, widthMultiplier: 2.3),
    ]

    static let bottomRow: [KeyModel] = [
        KeyModel(label: "fn", action: .fn, widthMultiplier: 1.0),
        KeyModel(label: "⌃", action: .control, widthMultiplier: 1.0),
        KeyModel(label: "⌥", action: .option, widthMultiplier: 1.0),
        KeyModel(label: "⌘", action: .command, widthMultiplier: 1.3),
        KeyModel(label: "", action: .space, widthMultiplier: 5.5),
        KeyModel(label: "⌘", action: .command, widthMultiplier: 1.3),
        KeyModel(label: "⌥", action: .option, widthMultiplier: 1.0),
        KeyModel(label: "⌃", action: .control, widthMultiplier: 1.0),
    ]

    /// All main-section rows (excluding function row) — base US QWERTY.
    static let mainRows: [[KeyModel]] = [
        numberRow,
        tabRow,
        capsRow,
        shiftRow,
        bottomRow,
    ]

    /// Returns main rows customized for the given language.
    /// Uses complete per-language layout definitions from LanguageManager.
    static func mainRows(for language: String) -> [[KeyModel]] {
        LanguageManager.layout(for: language).mainRows
    }

    /// Compute the minimum window width needed for a language layout at a given
    /// minimum key unit size. Accounts for inter-key spacing, horizontal padding,
    /// and navigation cluster.
    static func minimumWidth(
        for language: String,
        minKeyUnit: CGFloat = 34,
        showNavigationCluster: Bool = true
    ) -> CGFloat {
        let rows = mainRows(for: language)
        let widestUnits = rows.map { $0.reduce(CGFloat(0)) { $0 + $1.widthMultiplier } }.max() ?? 14
        let maxKeyCount = rows.map(\.count).max() ?? 14
        let spacing = CGFloat(maxKeyCount - 1) * (3.0 * minKeyUnit / 38.0)
        let hPad: CGFloat = 32 // 16pt each side
        let navWidth: CGFloat = showNavigationCluster
            ? (3.0 * minKeyUnit + 2.0 * (3.0 * minKeyUnit / 38.0) + 14.0 * minKeyUnit / 38.0)
            : 0
        return widestUnits * minKeyUnit + spacing + hPad + navWidth
    }

    // MARK: Navigation Cluster

    static let navTopRow: [KeyModel] = [
        KeyModel(label: "⌦", action: .forwardDelete),
        KeyModel(label: "↖", action: .home),
        KeyModel(label: "⇞", action: .pageUp),
    ]

    static let navBottomRow: [KeyModel] = [
        KeyModel(label: "↘", action: .end),
        KeyModel(label: "⇟", action: .pageDown),
    ]

    // MARK: Arrow Cluster (inverted-T)

    static let arrowTopRow: [KeyModel] = [
        KeyModel(label: "▲", action: .arrowUp),
    ]

    static let arrowBottomRow: [KeyModel] = [
        KeyModel(label: "◀", action: .arrowLeft),
        KeyModel(label: "▼", action: .arrowDown),
        KeyModel(label: "▶", action: .arrowRight),
    ]
}

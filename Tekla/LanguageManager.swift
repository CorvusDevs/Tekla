import Foundation

/// Manages keyboard language/layout selection and auto-detection.
/// All data is local — no network calls.
enum LanguageManager {

    // MARK: - Supported Languages

    struct Language: Identifiable, Hashable {
        let id: String           // ISO 639-1 code (e.g., "en", "es")
        let name: String         // Localized display name
        let nativeName: String   // Name in the language itself
        let spellCheckerCode: String // NSSpellChecker language identifier
    }

    static let supportedLanguages: [Language] = [
        Language(id: "en", name: String(localized: "English"), nativeName: "English", spellCheckerCode: "en"),
        Language(id: "es", name: String(localized: "Spanish"), nativeName: "Español", spellCheckerCode: "es"),
        Language(id: "fr", name: String(localized: "French"), nativeName: "Français", spellCheckerCode: "fr"),
        Language(id: "de", name: String(localized: "German"), nativeName: "Deutsch", spellCheckerCode: "de"),
        Language(id: "it", name: String(localized: "Italian"), nativeName: "Italiano", spellCheckerCode: "it"),
        Language(id: "pt", name: String(localized: "Portuguese"), nativeName: "Português", spellCheckerCode: "pt"),
        Language(id: "nl", name: String(localized: "Dutch"), nativeName: "Nederlands", spellCheckerCode: "nl"),
        Language(id: "sv", name: String(localized: "Swedish"), nativeName: "Svenska", spellCheckerCode: "sv"),
        Language(id: "da", name: String(localized: "Danish"), nativeName: "Dansk", spellCheckerCode: "da"),
        Language(id: "no", name: String(localized: "Norwegian"), nativeName: "Norsk", spellCheckerCode: "nb"),
        Language(id: "fi", name: String(localized: "Finnish"), nativeName: "Suomi", spellCheckerCode: "fi"),
        Language(id: "pl", name: String(localized: "Polish"), nativeName: "Polski", spellCheckerCode: "pl"),
        Language(id: "tr", name: String(localized: "Turkish"), nativeName: "Türkçe", spellCheckerCode: "tr"),
        Language(id: "ru", name: String(localized: "Russian"), nativeName: "Русский", spellCheckerCode: "ru"),
    ]

    // MARK: - Auto-Detection

    /// Detect the user's preferred language from system settings.
    static func detectedSystemLanguage() -> String {
        // Use the user's preferred language list
        let preferred = Locale.preferredLanguages
        for lang in preferred {
            // Extract the language code (e.g., "en-US" → "en")
            let code = Locale(identifier: lang).language.languageCode?.identifier ?? ""
            if supportedLanguages.contains(where: { $0.id == code }) {
                return code
            }
        }
        return "en"
    }

    /// Get a language by its ID.
    static func language(for id: String) -> Language {
        supportedLanguages.first { $0.id == id } ?? supportedLanguages[0]
    }

    /// Get the spell checker code for predictions.
    static func spellCheckerCode(for languageID: String) -> String {
        language(for: languageID).spellCheckerCode
    }

    // MARK: - Keyboard Layouts per Language

    /// Complete keyboard layout definition for a language.
    /// Each language defines its own number row, tab row, caps row, and shift row.
    /// The bottom row (modifiers + space) is shared across all languages.
    struct LanguageLayout {
        let numberRow: [KeyModel]
        let tabRow: [KeyModel]
        let capsRow: [KeyModel]
        let shiftRow: [KeyModel]

        /// All main rows assembled in order (number, tab, caps, shift, bottom).
        var mainRows: [[KeyModel]] {
            [numberRow, tabRow, capsRow, shiftRow, KeyboardLayout.bottomRow]
        }
    }

    // MARK: - Layout Factory

    /// Returns the complete keyboard layout for a language.
    static func layout(for languageID: String) -> LanguageLayout {
        switch languageID {
        case "es": return spanishLayout
        case "de": return germanLayout
        case "fr": return frenchLayout
        case "pt": return portugueseLayout
        case "it": return italianLayout
        case "sv", "fi": return swedishLayout  // Finnish = Swedish layout
        case "da": return danishLayout
        case "no": return norwegianLayout
        case "nl", "pl": return isoEnglishLayout  // Dutch/Polish use ISO English base
        case "tr": return turkishLayout
        case "ru": return russianLayout
        default: return englishLayout
        }
    }

    // MARK: - English (US ANSI)

    private static let englishLayout = LanguageLayout(
        numberRow: KeyboardLayout.numberRow,
        tabRow: KeyboardLayout.tabRow,
        capsRow: KeyboardLayout.capsRow,
        shiftRow: KeyboardLayout.shiftRow
    )

    // MARK: - ISO English (International)
    // Used by Dutch, Polish — same as US QWERTY but with § on far-left
    // and the extra ISO key (` ~) left of Z.

    private static let isoEnglishLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "§", action: .character("§"), shiftedLabel: "±", secondaryLabel: "±"),
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
        ],
        tabRow: KeyboardLayout.tabRow,
        capsRow: KeyboardLayout.capsRow,
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "`", action: .character("`"), shiftedLabel: "~", secondaryLabel: "~"),
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
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Spanish (ISO Spanish)

    private static let spanishLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "º", action: .character("º"), shiftedLabel: "ª", secondaryLabel: "ª"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "·", secondaryLabel: "·"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "$", secondaryLabel: "$"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "¡", action: .character("¡"), shiftedLabel: "¿", secondaryLabel: "¿"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
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
            KeyModel(label: "`", action: .character("`"), shiftedLabel: "^", secondaryLabel: "^"),
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "*", secondaryLabel: "*"),
        ],
        capsRow: [
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
            KeyModel(label: "Ñ", action: .character("ñ")),
            KeyModel(label: "´", action: .character("´"), shiftedLabel: "¨", secondaryLabel: "¨"),
            KeyModel(label: "Ç", action: .character("ç")),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - German (ISO QWERTZ)

    private static let germanLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "^", action: .character("^"), shiftedLabel: "°", secondaryLabel: "°"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "§", secondaryLabel: "§"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "$", secondaryLabel: "$"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "ß", action: .character("ß"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "´", action: .character("´"), shiftedLabel: "`", secondaryLabel: "`"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
            KeyModel(label: "⇥", action: .tab, widthMultiplier: 1.6),
            KeyModel(label: "Q", action: .character("q")),
            KeyModel(label: "W", action: .character("w")),
            KeyModel(label: "E", action: .character("e")),
            KeyModel(label: "R", action: .character("r")),
            KeyModel(label: "T", action: .character("t")),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "U", action: .character("u")),
            KeyModel(label: "I", action: .character("i")),
            KeyModel(label: "O", action: .character("o")),
            KeyModel(label: "P", action: .character("p")),
            KeyModel(label: "Ü", action: .character("ü")),
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "*", secondaryLabel: "*"),
        ],
        capsRow: [
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
            KeyModel(label: "Ö", action: .character("ö")),
            KeyModel(label: "Ä", action: .character("ä")),
            KeyModel(label: "#", action: .character("#"), shiftedLabel: "'", secondaryLabel: "'"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Y", action: .character("y")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - French (ISO AZERTY)

    private static let frenchLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "@", action: .character("@"), shiftedLabel: "#", secondaryLabel: "#"),
            KeyModel(label: "&", action: .character("&"), shiftedLabel: "1", secondaryLabel: "1"),
            KeyModel(label: "é", action: .character("é"), shiftedLabel: "2", secondaryLabel: "2"),
            KeyModel(label: "\"", action: .character("\""), shiftedLabel: "3", secondaryLabel: "3"),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "4", secondaryLabel: "4"),
            KeyModel(label: "(", action: .character("("), shiftedLabel: "5", secondaryLabel: "5"),
            KeyModel(label: "§", action: .character("§"), shiftedLabel: "6", secondaryLabel: "6"),
            KeyModel(label: "è", action: .character("è"), shiftedLabel: "7", secondaryLabel: "7"),
            KeyModel(label: "!", action: .character("!"), shiftedLabel: "8", secondaryLabel: "8"),
            KeyModel(label: "ç", action: .character("ç"), shiftedLabel: "9", secondaryLabel: "9"),
            KeyModel(label: "à", action: .character("à"), shiftedLabel: "0", secondaryLabel: "0"),
            KeyModel(label: ")", action: .character(")"), shiftedLabel: "°", secondaryLabel: "°"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
            KeyModel(label: "⇥", action: .tab, widthMultiplier: 1.6),
            KeyModel(label: "A", action: .character("a")),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "E", action: .character("e")),
            KeyModel(label: "R", action: .character("r")),
            KeyModel(label: "T", action: .character("t")),
            KeyModel(label: "Y", action: .character("y")),
            KeyModel(label: "U", action: .character("u")),
            KeyModel(label: "I", action: .character("i")),
            KeyModel(label: "O", action: .character("o")),
            KeyModel(label: "P", action: .character("p")),
            KeyModel(label: "^", action: .character("^"), shiftedLabel: "¨", secondaryLabel: "¨"),
            KeyModel(label: "$", action: .character("$"), shiftedLabel: "*", secondaryLabel: "*"),
        ],
        capsRow: [
            KeyModel(label: "⇪", action: .capsLock, widthMultiplier: 1.8),
            KeyModel(label: "Q", action: .character("q")),
            KeyModel(label: "S", action: .character("s")),
            KeyModel(label: "D", action: .character("d")),
            KeyModel(label: "F", action: .character("f")),
            KeyModel(label: "G", action: .character("g")),
            KeyModel(label: "H", action: .character("h")),
            KeyModel(label: "J", action: .character("j")),
            KeyModel(label: "K", action: .character("k")),
            KeyModel(label: "L", action: .character("l")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: "ù", action: .character("ù"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "`", action: .character("`"), shiftedLabel: "£", secondaryLabel: "£"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "W", action: .character("w")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: ";", action: .character(";"), shiftedLabel: ".", secondaryLabel: "."),
            KeyModel(label: ":", action: .character(":"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "=", action: .character("="), shiftedLabel: "+", secondaryLabel: "+"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Portuguese (ISO Portuguese)

    private static let portugueseLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "\\", action: .character("\\"), shiftedLabel: "|", secondaryLabel: "|"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "#", secondaryLabel: "#"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "$", secondaryLabel: "$"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "«", action: .character("«"), shiftedLabel: "»", secondaryLabel: "»"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
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
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "*", secondaryLabel: "*"),
            KeyModel(label: "´", action: .character("´"), shiftedLabel: "`", secondaryLabel: "`"),
        ],
        capsRow: [
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
            KeyModel(label: "Ç", action: .character("ç")),
            KeyModel(label: "º", action: .character("º"), shiftedLabel: "ª", secondaryLabel: "ª"),
            KeyModel(label: "~", action: .character("~"), shiftedLabel: "^", secondaryLabel: "^"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Italian (ISO Italian)

    private static let italianLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "\\", action: .character("\\"), shiftedLabel: "|", secondaryLabel: "|"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "£", secondaryLabel: "£"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "$", secondaryLabel: "$"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "ì", action: .character("ì"), shiftedLabel: "^", secondaryLabel: "^"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
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
            KeyModel(label: "è", action: .character("è"), shiftedLabel: "é", secondaryLabel: "é"),
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "*", secondaryLabel: "*"),
        ],
        capsRow: [
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
            KeyModel(label: "ò", action: .character("ò"), shiftedLabel: "ç", secondaryLabel: "ç"),
            KeyModel(label: "à", action: .character("à"), shiftedLabel: "@", secondaryLabel: "@"),
            KeyModel(label: "#", action: .character("#"), shiftedLabel: "~", secondaryLabel: "~"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Swedish / Finnish (ISO Nordic)

    private static let swedishLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "§", action: .character("§"), shiftedLabel: "°", secondaryLabel: "°"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "#", secondaryLabel: "#"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "¤", secondaryLabel: "¤"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "´", action: .character("´"), shiftedLabel: "`", secondaryLabel: "`"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
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
            KeyModel(label: "Å", action: .character("å")),
            KeyModel(label: "¨", action: .character("¨"), shiftedLabel: "^", secondaryLabel: "^"),
        ],
        capsRow: [
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
            KeyModel(label: "Ö", action: .character("ö")),
            KeyModel(label: "Ä", action: .character("ä")),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "*", secondaryLabel: "*"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Danish (ISO Danish)

    private static let danishLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "§", action: .character("§"), shiftedLabel: "½", secondaryLabel: "½"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "#", secondaryLabel: "#"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "¤", secondaryLabel: "¤"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "´", action: .character("´"), shiftedLabel: "`", secondaryLabel: "`"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
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
            KeyModel(label: "Å", action: .character("å")),
            KeyModel(label: "¨", action: .character("¨"), shiftedLabel: "^", secondaryLabel: "^"),
        ],
        capsRow: [
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
            KeyModel(label: "Æ", action: .character("æ")),
            KeyModel(label: "Ø", action: .character("ø")),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "*", secondaryLabel: "*"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Norwegian (ISO Norwegian)

    private static let norwegianLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "|", action: .character("|"), shiftedLabel: "§", secondaryLabel: "§"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "#", secondaryLabel: "#"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "¤", secondaryLabel: "¤"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "+", action: .character("+"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "\\", action: .character("\\"), shiftedLabel: "`", secondaryLabel: "`"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
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
            KeyModel(label: "Å", action: .character("å")),
            KeyModel(label: "¨", action: .character("¨"), shiftedLabel: "^", secondaryLabel: "^"),
        ],
        capsRow: [
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
            KeyModel(label: "Ø", action: .character("ø")),
            KeyModel(label: "Æ", action: .character("æ")),
            KeyModel(label: "'", action: .character("'"), shiftedLabel: "*", secondaryLabel: "*"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Turkish Q (ISO Turkish)

    private static let turkishLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "\"", action: .character("\""), shiftedLabel: "é", secondaryLabel: "é"),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "'", secondaryLabel: "'"),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "^", secondaryLabel: "^"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: "+", secondaryLabel: "+"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: "&", secondaryLabel: "&"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: "=", secondaryLabel: "="),
            KeyModel(label: "*", action: .character("*"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
            KeyModel(label: "⇥", action: .tab, widthMultiplier: 1.6),
            KeyModel(label: "Q", action: .character("q")),
            KeyModel(label: "W", action: .character("w")),
            KeyModel(label: "E", action: .character("e")),
            KeyModel(label: "R", action: .character("r")),
            KeyModel(label: "T", action: .character("t")),
            KeyModel(label: "Y", action: .character("y")),
            KeyModel(label: "U", action: .character("u")),
            KeyModel(label: "I", action: .character("ı")),
            KeyModel(label: "O", action: .character("o")),
            KeyModel(label: "P", action: .character("p")),
            KeyModel(label: "Ğ", action: .character("ğ")),
            KeyModel(label: "Ü", action: .character("ü")),
        ],
        capsRow: [
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
            KeyModel(label: "Ş", action: .character("ş")),
            KeyModel(label: "İ", action: .character("i")),
            KeyModel(label: ",", action: .character(","), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "<", action: .character("<"), shiftedLabel: ">", secondaryLabel: ">"),
            KeyModel(label: "Z", action: .character("z")),
            KeyModel(label: "X", action: .character("x")),
            KeyModel(label: "C", action: .character("c")),
            KeyModel(label: "V", action: .character("v")),
            KeyModel(label: "B", action: .character("b")),
            KeyModel(label: "N", action: .character("n")),
            KeyModel(label: "M", action: .character("m")),
            KeyModel(label: "Ö", action: .character("ö")),
            KeyModel(label: "Ç", action: .character("ç")),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )

    // MARK: - Russian (ЙЦУКЕН)

    private static let russianLayout = LanguageLayout(
        numberRow: [
            KeyModel(label: "ё", action: .character("ё")),
            KeyModel(label: "1", action: .character("1"), shiftedLabel: "!", secondaryLabel: "!"),
            KeyModel(label: "2", action: .character("2"), shiftedLabel: "\"", secondaryLabel: "\""),
            KeyModel(label: "3", action: .character("3"), shiftedLabel: "№", secondaryLabel: "№"),
            KeyModel(label: "4", action: .character("4"), shiftedLabel: ";", secondaryLabel: ";"),
            KeyModel(label: "5", action: .character("5"), shiftedLabel: "%", secondaryLabel: "%"),
            KeyModel(label: "6", action: .character("6"), shiftedLabel: ":", secondaryLabel: ":"),
            KeyModel(label: "7", action: .character("7"), shiftedLabel: "?", secondaryLabel: "?"),
            KeyModel(label: "8", action: .character("8"), shiftedLabel: "*", secondaryLabel: "*"),
            KeyModel(label: "9", action: .character("9"), shiftedLabel: "(", secondaryLabel: "("),
            KeyModel(label: "0", action: .character("0"), shiftedLabel: ")", secondaryLabel: ")"),
            KeyModel(label: "-", action: .character("-"), shiftedLabel: "_", secondaryLabel: "_"),
            KeyModel(label: "=", action: .character("="), shiftedLabel: "+", secondaryLabel: "+"),
            KeyModel(label: "⌫", action: .backspace, widthMultiplier: 1.6),
        ],
        tabRow: [
            KeyModel(label: "⇥", action: .tab, widthMultiplier: 1.6),
            KeyModel(label: "Й", action: .character("й")),
            KeyModel(label: "Ц", action: .character("ц")),
            KeyModel(label: "У", action: .character("у")),
            KeyModel(label: "К", action: .character("к")),
            KeyModel(label: "Е", action: .character("е")),
            KeyModel(label: "Н", action: .character("н")),
            KeyModel(label: "Г", action: .character("г")),
            KeyModel(label: "Ш", action: .character("ш")),
            KeyModel(label: "Щ", action: .character("щ")),
            KeyModel(label: "З", action: .character("з")),
            KeyModel(label: "Х", action: .character("х")),
            KeyModel(label: "Ъ", action: .character("ъ")),
        ],
        capsRow: [
            KeyModel(label: "⇪", action: .capsLock, widthMultiplier: 1.8),
            KeyModel(label: "Ф", action: .character("ф")),
            KeyModel(label: "Ы", action: .character("ы")),
            KeyModel(label: "В", action: .character("в")),
            KeyModel(label: "А", action: .character("а")),
            KeyModel(label: "П", action: .character("п")),
            KeyModel(label: "Р", action: .character("р")),
            KeyModel(label: "О", action: .character("о")),
            KeyModel(label: "Л", action: .character("л")),
            KeyModel(label: "Д", action: .character("д")),
            KeyModel(label: "Ж", action: .character("ж")),
            KeyModel(label: "Э", action: .character("э")),
            KeyModel(label: "\\", action: .character("\\"), shiftedLabel: "/", secondaryLabel: "/"),
            KeyModel(label: "⏎", action: .returnKey, widthMultiplier: 1.5),
        ],
        shiftRow: [
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
            KeyModel(label: "]", action: .character("]"), shiftedLabel: "[", secondaryLabel: "["),
            KeyModel(label: "Я", action: .character("я")),
            KeyModel(label: "Ч", action: .character("ч")),
            KeyModel(label: "С", action: .character("с")),
            KeyModel(label: "М", action: .character("м")),
            KeyModel(label: "И", action: .character("и")),
            KeyModel(label: "Т", action: .character("т")),
            KeyModel(label: "Ь", action: .character("ь")),
            KeyModel(label: "Б", action: .character("б")),
            KeyModel(label: "Ю", action: .character("ю")),
            KeyModel(label: ".", action: .character("."), shiftedLabel: ",", secondaryLabel: ","),
            KeyModel(label: "⇧", action: .shift, widthMultiplier: 1.3),
        ]
    )
}

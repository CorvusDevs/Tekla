import Foundation

/// Persists user preferences locally via UserDefaults.
@Observable
final class SettingsManager {

    // MARK: - Feedback

    var soundFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(soundFeedbackEnabled, forKey: Keys.soundFeedback) }
    }

    var hapticFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticFeedbackEnabled, forKey: Keys.hapticFeedback) }
    }

    var soundVolume: Float {
        didSet { UserDefaults.standard.set(soundVolume, forKey: Keys.soundVolume) }
    }

    var visualFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(visualFeedbackEnabled, forKey: Keys.visualFeedback) }
    }

    // MARK: - Typing

    var swipeTypingEnabled: Bool {
        didSet { UserDefaults.standard.set(swipeTypingEnabled, forKey: Keys.swipeTyping) }
    }

    var predictionsEnabled: Bool {
        didSet { UserDefaults.standard.set(predictionsEnabled, forKey: Keys.predictions) }
    }

    var autocorrectEnabled: Bool {
        didSet { UserDefaults.standard.set(autocorrectEnabled, forKey: Keys.autocorrect) }
    }

    /// Number of word predictions to show in the bar (3–7).
    var predictionCount: Int {
        didSet { UserDefaults.standard.set(predictionCount, forKey: Keys.predictionCount) }
    }

    /// Whether the engine learns from the user's typing to improve predictions.
    var learnFromTyping: Bool {
        didSet { UserDefaults.standard.set(learnFromTyping, forKey: Keys.learnFromTyping) }
    }

    /// Whether the primary prediction (middle slot) is auto-inserted on space after swiping.
    var autoInsertPrediction: Bool {
        didSet { UserDefaults.standard.set(autoInsertPrediction, forKey: Keys.autoInsertPrediction) }
    }

    // MARK: - Language

    var selectedLanguage: String {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: Keys.language) }
    }

    /// Number of trail points to display during swipe (10–60).
    var swipeTrailLength: Double {
        didSet { UserDefaults.standard.set(swipeTrailLength, forKey: Keys.swipeTrailLength) }
    }

    // MARK: - Appearance

    var showFunctionRow: Bool {
        didSet { UserDefaults.standard.set(showFunctionRow, forKey: Keys.showFunctionRow) }
    }

    var showNavigationCluster: Bool {
        didSet { UserDefaults.standard.set(showNavigationCluster, forKey: Keys.showNavCluster) }
    }

    var keyboardOpacity: Double {
        didSet { UserDefaults.standard.set(keyboardOpacity, forKey: Keys.keyboardOpacity) }
    }

    // MARK: - Activation

    var isUnlocked: Bool {
        didSet { UserDefaults.standard.set(isUnlocked, forKey: Keys.isUnlocked) }
    }

    private static let unlockCode = "TEKLA-UNLOCK-9V3R"

    /// Validates the code and persists the unlock state. Returns `true` on success.
    func activate(code: String) -> Bool {
        if code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.unlockCode {
            isUnlocked = true
            return true
        }
        return false
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        Self.registerDefaults()

        soundFeedbackEnabled = defaults.bool(forKey: Keys.soundFeedback)
        hapticFeedbackEnabled = defaults.bool(forKey: Keys.hapticFeedback)
        soundVolume = defaults.float(forKey: Keys.soundVolume)
        visualFeedbackEnabled = defaults.bool(forKey: Keys.visualFeedback)
        swipeTypingEnabled = defaults.bool(forKey: Keys.swipeTyping)
        predictionsEnabled = defaults.bool(forKey: Keys.predictions)
        autocorrectEnabled = defaults.bool(forKey: Keys.autocorrect)
        predictionCount = defaults.integer(forKey: Keys.predictionCount)
        learnFromTyping = defaults.bool(forKey: Keys.learnFromTyping)
        autoInsertPrediction = defaults.bool(forKey: Keys.autoInsertPrediction)
        selectedLanguage = defaults.string(forKey: Keys.language) ?? LanguageManager.detectedSystemLanguage()
        swipeTrailLength = defaults.double(forKey: Keys.swipeTrailLength)
        showFunctionRow = defaults.bool(forKey: Keys.showFunctionRow)
        showNavigationCluster = defaults.bool(forKey: Keys.showNavCluster)
        keyboardOpacity = defaults.double(forKey: Keys.keyboardOpacity)
        isUnlocked = defaults.bool(forKey: Keys.isUnlocked)
    }

    private static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.soundFeedback: true,
            Keys.hapticFeedback: true,
            Keys.soundVolume: Float(0.5),
            Keys.visualFeedback: true,
            Keys.swipeTyping: true,
            Keys.predictions: true,
            Keys.autocorrect: false,
            Keys.predictionCount: 5,
            Keys.learnFromTyping: true,
            Keys.autoInsertPrediction: true,
            Keys.language: LanguageManager.detectedSystemLanguage(),
            Keys.swipeTrailLength: Double(20),
            Keys.showFunctionRow: true,
            Keys.showNavCluster: true,
            Keys.keyboardOpacity: Double(1.0),
        ])
    }

    // MARK: - Keys

    private enum Keys {
        static let soundFeedback = "tekla.soundFeedback"
        static let hapticFeedback = "tekla.hapticFeedback"
        static let soundVolume = "tekla.soundVolume"
        static let visualFeedback = "tekla.visualFeedback"
        static let swipeTyping = "tekla.swipeTyping"
        static let predictions = "tekla.predictions"
        static let autocorrect = "tekla.autocorrect"
        static let predictionCount = "tekla.predictionCount"
        static let learnFromTyping = "tekla.learnFromTyping"
        static let autoInsertPrediction = "tekla.autoInsertPrediction"
        static let language = "tekla.language"
        static let swipeTrailLength = "tekla.swipeTrailLength"
        static let showFunctionRow = "tekla.showFunctionRow"
        static let showNavCluster = "tekla.showNavCluster"
        static let keyboardOpacity = "tekla.keyboardOpacity"
        static let isUnlocked = "tekla.isUnlocked"
    }
}

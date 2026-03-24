import SwiftUI
import AppKit
import CoreGraphics

/// Central state for the virtual keyboard.
@Observable
final class KeyboardViewModel {

    // MARK: - State

    var isShiftActive = false
    var isCapsLockActive = false
    var isCommandActive = false
    var isOptionActive = false
    var isControlActive = false
    var predictions: [String] = []

    let permissions = PermissionsManager()
    let settings = SettingsManager()
    let swipeEngine = SwipeEngine()
    let predictionEngine = PredictionEngine()

    /// The last completed word, used as bigram context for predictions.
    private var previousWord: String?

    /// The index of the primary (best) prediction in the `predictions` array.
    /// The primary is placed in the center of the prediction bar.
    var primaryPredictionIndex: Int {
        let count = predictions.count
        guard count > 0 else { return 0 }
        return count / 2
    }

    init() {
        swipeEngine.language = settings.selectedLanguage
        swipeEngine.predictionEngine = predictionEngine
        predictionEngine.maxResults = settings.predictionCount
        predictionEngine.loadLanguage(settings.selectedLanguage)
        predictionEngine.pruneUserDictionary()
        // First word typed should be capitalized (start of a new text).
        // Set both: shouldCapitalizeNext for prediction capitalization,
        // isShiftActive for visual uppercase keys (didSet doesn't fire in init).
        shouldCapitalizeNext = true
        isShiftActive = true
    }

    /// The current typed buffer for prediction.
    private(set) var currentWordBuffer = ""

    var activeModifiers: Set<KeyAction> {
        var mods = Set<KeyAction>()
        if isShiftActive { mods.insert(.shift) }
        if isCapsLockActive { mods.insert(.capsLock) }
        if isCommandActive { mods.insert(.command) }
        if isOptionActive { mods.insert(.option) }
        if isControlActive { mods.insert(.control) }
        return mods
    }

    // MARK: - Key Actions

    /// Called on mouse-down / press start — plays press feedback only.
    func handleKeyDown(_ key: KeyModel) {
        FeedbackEngine.shared.playKeyDownFeedback(settings: settings)
    }

    /// Called on mouse-up / press release — executes the key action and plays release feedback.
    func handleKeyTap(_ key: KeyModel) {
        FeedbackEngine.shared.playKeyUpFeedback(settings: settings)

        switch key.action {
        case .character(let char):
            // Any typing after a swipe clears the correction window
            lastSwipedWord = nil
            isShowingNextWordPredictions = false
            // Resolve the actual character for prediction/buffer: when shift is active
            // and the key has a shifted label (e.g., ' → ?), use the shifted character.
            // Letter keys don't need this — their shift behavior is uppercasing.
            let resolvedChar: Character
            if (isShiftActive || isCapsLockActive),
               let shifted = key.shiftedLabel,
               let shiftedChar = shifted.first,
               !char.isLetter {
                resolvedChar = shiftedChar
            } else {
                resolvedChar = char
            }
            handleCharacter(resolvedChar, keyChar: char)

        case .space:
            sendKey("space")
            lastSwipedWord = nil
            lastActionInsertedTrailingSpace = false
            commitCurrentWord()
            showNextWordPredictions()
            releaseOneShot()

        case .backspace:
            sendKey("delete")
            lastSwipedWord = nil
            lastActionInsertedTrailingSpace = false
            // Backspace cancels auto-capitalization — user is editing, not starting a new sentence
            if shouldCapitalizeNext {
                shouldCapitalizeNext = false
                isShiftActive = false
            }
            if !currentWordBuffer.isEmpty {
                currentWordBuffer.removeLast()
            }
            updatePredictions()
            releaseOneShot()

        case .forwardDelete:
            sendKey("forwardDelete")
            lastSwipedWord = nil
            releaseOneShot()

        case .returnKey:
            sendKey("return")
            lastSwipedWord = nil
            lastActionInsertedTrailingSpace = false
            commitCurrentWord()
            releaseOneShot()

        case .tab:
            sendKey("tab")
            releaseOneShot()

        case .escape:
            sendKey("escape")
            releaseOneShot()

        case .shift:
            isShiftActive.toggle()

        case .capsLock:
            isCapsLockActive.toggle()

        case .command:
            isCommandActive.toggle()

        case .option:
            isOptionActive.toggle()

        case .control:
            isControlActive.toggle()

        case .fn, .globe:
            sendKey("function")

        case .arrowLeft:  sendKey("left");  releaseOneShot()
        case .arrowRight: sendKey("right"); releaseOneShot()
        case .arrowUp:    sendKey("up");    releaseOneShot()
        case .arrowDown:  sendKey("down");  releaseOneShot()
        case .home:       sendKey("home");  releaseOneShot()
        case .end:        sendKey("end");   releaseOneShot()
        case .pageUp:     sendKey("pageUp"); releaseOneShot()
        case .pageDown:   sendKey("pageDown"); releaseOneShot()

        case .functionKey(let n):
            sendKey("f\(n)")
            releaseOneShot()
        }
    }

    /// The last word typed by swipe, used for correction when the user picks an alternative.
    private var lastSwipedWord: String?

    /// When true, the prediction bar shows next-word suggestions (not corrections).
    /// Enter key inserts the primary prediction in this mode.
    private var isShowingNextWordPredictions = false

    /// When true, the last action inserted a word followed by a trailing space.
    /// Used for smart punctuation: if the next character is punctuation, the
    /// trailing space is deleted first so the symbol sits against the word.
    private var lastActionInsertedTrailingSpace = false

    /// Characters that should be placed directly against the previous word
    /// (deleting any auto-inserted trailing space).
    private static let smartPunctuationChars: Set<Character> = [".", ",", "?", "!", ";", ":", "…"]

    /// Punctuation that ends a sentence — next-word predictions should be capitalized
    /// and shift auto-activates so the keyboard visually reflects uppercase.
    private static let sentenceEndingChars: Set<Character> = [".", "?", "!"]

    /// When true, the next predicted/typed word should be capitalized.
    /// Setting this also auto-activates shift so the keyboard shows uppercase keys.
    private var shouldCapitalizeNext = false {
        didSet {
            if shouldCapitalizeNext {
                isShiftActive = true
            }
        }
    }

    /// Called during a swipe as the finger crosses new letters — updates the
    /// prediction bar with live completions so the user gets real-time feedback.
    ///
    /// Strategy: As the swipe progresses and more keys are crossed, the
    /// predictions narrow. With < 3 unique keys we use a broad first-letter
    /// prefix query. With >= 3 unique keys we use `completionsForSwipe` which
    /// filters by both first and last letter — much more specific.
    func handleSwipeLettersChanged(_ letters: [Character]) {
        guard settings.predictionsEnabled else { return }
        isShowingNextWordPredictions = false

        // Use intentional key extraction to filter out transit noise.
        // This gives us only the keys the user actually dwelled on,
        // not every key the path happened to cross.
        let intentional = swipeEngine.extractIntentionalKeys()

        // Wait until at least 2 intentional keys have been identified.
        guard intentional.count >= 2 else { return }

        syncLanguage()

        let count = settings.predictionCount
        let firstLetter = intentional.first!
        let lastLetter = intentional.last!

        var results: [String] = []
        var seen = Set<String>()

        // With enough intentional keys, use trie first+last letter filtering
        // for targeted predictions that narrow as the swipe progresses.
        if intentional.count >= 3 {
            let trieResults = predictionEngine.completionsForSwipe(
                firstLetter: firstLetter,
                lastLetter: lastLetter
            )
            for word in trieResults {
                if seen.insert(word.lowercased()).inserted {
                    results.append(word)
                }
                if results.count >= count { break }
            }
        }

        // Fill remaining slots with general first-letter prefix predictions,
        // prioritizing words ending with the current last letter.
        if results.count < count {
            let prefixPredictions = predictionEngine.predict(
                prefix: String(firstLetter),
                previousWord: previousWord
            )

            var primary: [String] = []
            var secondary: [String] = []
            for word in prefixPredictions {
                guard !seen.contains(word.lowercased()) else { continue }
                if word.lowercased().last == lastLetter {
                    primary.append(word)
                } else {
                    secondary.append(word)
                }
            }

            for word in primary {
                if seen.insert(word.lowercased()).inserted {
                    results.append(word)
                }
                if results.count >= count { break }
            }
            for word in secondary where results.count < count {
                if seen.insert(word.lowercased()).inserted {
                    results.append(word)
                }
            }
        }

        // Final padding if still under-filled
        if results.count < count {
            let extra = predictionEngine.predict(
                prefix: String(firstLetter),
                previousWord: nil
            )
            for word in extra where results.count < count {
                if seen.insert(word.lowercased()).inserted {
                    results.append(word)
                }
            }
        }

        let displayed = centerBestPrediction(Array(results.prefix(count)))
        predictions = displayed
    }

    /// Called when a swipe gesture ends — re-ranks with LM and types the best match.
    func handleSwipeResult(_ scoredCandidates: [(word: String, geometricScore: Double)]) {
        // Keep engines in sync with current language
        syncLanguage()
        guard !scoredCandidates.isEmpty, permissions.isAccessibilityGranted else { return }

        // If the user typed a word and then swiped, the typed characters are
        // already in the document (sent key-by-key). Commit the buffer and
        // insert a space so the swiped word doesn't merge with the typed one.
        if !currentWordBuffer.isEmpty {
            commitCurrentWord()
            KeystrokeEngine.typeString(" ")
        }

        let count = settings.predictionCount

        // Re-rank using the language model (trie + bigrams + user learning)
        let reranked = predictionEngine.rerankSwipeCandidates(
            scoredCandidates,
            previousWord: previousWord
        )

        // Fall back to geometric-only order if re-ranking returned nothing
        var ranked = reranked.isEmpty
            ? Array(scoredCandidates.prefix(count).map(\.word))
            : reranked

        // Inject bigram-predicted words into the alternatives. When a strong
        // contextual prediction exists (e.g. "como" after "hola"), it should appear
        // as a tappable alternative even if it scored poorly geometrically.
        if let prev = previousWord,
           let firstChar = ranked.first?.first ?? scoredCandidates.first?.word.first {
            var seen = Set(ranked.map { $0.lowercased() })
            let bigramWords = predictionEngine.bigramCompletions(
                after: prev, startingWith: firstChar
            )
            // Insert bigram suggestions right after the best candidate (position 2+)
            // so they're prominently visible but don't override the geometric winner.
            for word in bigramWords {
                guard ranked.count < count else { break }
                if seen.insert(word.lowercased()).inserted {
                    ranked.append(word)
                }
            }
        }

        // Fill remaining prediction slots with first-letter prefix predictions
        // so the user never sees a prediction bar with empty spaces.
        if ranked.count < count, let firstChar = ranked.first?.first ?? scoredCandidates.first?.word.first {
            var seen = Set(ranked.map { $0.lowercased() })

            let prefixPredictions = predictionEngine.predict(
                prefix: String(firstChar),
                previousWord: previousWord
            )
            for word in prefixPredictions where ranked.count < count {
                if seen.insert(word.lowercased()).inserted {
                    ranked.append(word)
                }
            }

            // If still not enough, broaden to context-only predictions
            if ranked.count < count {
                let broader = predictionEngine.predict(
                    prefix: String(firstChar),
                    previousWord: nil
                )
                for word in broader where ranked.count < count {
                    if seen.insert(word.lowercased()).inserted {
                        ranked.append(word)
                    }
                }
            }
        }

        // Capitalize after sentence-ending punctuation (. ? !)
        if shouldCapitalizeNext {
            ranked = ranked.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            shouldCapitalizeNext = false
        }

        // Reorder so the best prediction sits in the center slot
        let displayed = centerBestPrediction(Array(ranked.prefix(count)))
        predictions = displayed

        // The best match is at the center index
        let best = ranked.first ?? ""
        guard !best.isEmpty else { return }

        KeystrokeEngine.typeString(best + " ")
        lastActionInsertedTrailingSpace = true
        if settings.learnFromTyping {
            predictionEngine.recordWordInContext(best.lowercased(), after: previousWord)
        }
        lastSwipedWord = best
        previousWord = best
    }

    /// Insert a predicted word. Handles two cases:
    /// 1. **Typing prediction**: replaces the partially typed buffer.
    /// 2. **Swipe correction**: replaces the last swiped word with the user's choice,
    ///    recording it with extra weight so the engine learns the preference.
    func insertPrediction(_ word: String) {
        guard permissions.isAccessibilityGranted else { return }

        if let swiped = lastSwipedWord {
            // If the user taps the already-typed primary word, confirm it
            if word.lowercased() == swiped.lowercased() {
                debugLog("[Tap] confirmed swiped word \"\(word)\"")
                lastSwipedWord = nil
                predictions = []
                showNextWordPredictions()
                return
            }

            // Swipe correction: delete the swiped word + trailing space
            debugLog("[Tap] swipe correction: \"\(swiped)\" → \"\(word)\"")
            if let deleteCode = KeystrokeEngine.keyCodes["delete"] {
                KeystrokeEngine.sendRepeatedKeystroke(keyCode: deleteCode, count: swiped.count + 1)
            }
            lastSwipedWord = nil

            KeystrokeEngine.typeString(word + " ")

            // Record with extra weight — this is an explicit correction
            if settings.learnFromTyping {
                predictionEngine.recordWord(word.lowercased(), weight: 3)
            }
            previousWord = word.lowercased()
        } else {
            // Normal typing prediction: delete the partial buffer
            debugLog("[Tap] typing prediction: buffer=\"\(currentWordBuffer)\" → \"\(word)\"")
            if let deleteCode = KeystrokeEngine.keyCodes["delete"] {
                KeystrokeEngine.sendRepeatedKeystroke(keyCode: deleteCode, count: currentWordBuffer.count)
            }

            KeystrokeEngine.typeString(word + " ")

            // Record for learning and update context
            if settings.learnFromTyping {
                predictionEngine.recordWordInContext(word.lowercased(), after: previousWord)
            }
            previousWord = word.lowercased()
        }

        currentWordBuffer = ""
        predictions = []
        shouldCapitalizeNext = false
        lastActionInsertedTrailingSpace = true
        // User explicitly picked a word — show next-word predictions
        showNextWordPredictions()
    }

    // MARK: - Prediction Helpers

    /// Reorder ranked predictions so the best (first) goes to the center slot,
    /// with alternatives fanning out left and right by rank.
    ///
    /// Input:  [1st, 2nd, 3rd, 4th, 5th]  (best-first ranking)
    /// Output: [2nd, 4th, 1st, 3rd, 5th]  (center = best, alternating L/R)
    private func centerBestPrediction(_ ranked: [String]) -> [String] {
        guard ranked.count > 1 else { return ranked }
        var result = Array(repeating: "", count: ranked.count)
        let center = ranked.count / 2
        result[center] = ranked[0] // Best goes to center

        var leftIdx = center - 1
        var rightIdx = center + 1
        for i in 1..<ranked.count {
            if i % 2 == 1, leftIdx >= 0 {
                result[leftIdx] = ranked[i]
                leftIdx -= 1
            } else if rightIdx < ranked.count {
                result[rightIdx] = ranked[i]
                rightIdx += 1
            } else if leftIdx >= 0 {
                result[leftIdx] = ranked[i]
                leftIdx -= 1
            }
        }
        return result
    }

    // MARK: - Debug Logging

    /// Append a timestamped line to the shared debug log (same file as SwipeEngine).
    private func debugLog(_ line: String) {
        print(line)
        let url = SwipeEngine.debugLogURL
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = entry.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            try? entry.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Private Helpers

    /// - Parameters:
    ///   - char: The resolved character (shifted symbol for non-letter keys, base for letters).
    ///           Used for prediction, buffer, and punctuation logic.
    ///   - keyChar: The original key action character (always the base/unshifted).
    ///             Used for keystroke injection (shift flag handles the actual output).
    ///             Defaults to `char` when not provided (e.g., for direct calls).
    private func handleCharacter(_ char: Character, keyChar: Character? = nil) {
        let shouldUpper = isShiftActive || isCapsLockActive
        let injectionChar = keyChar ?? char

        // Smart punctuation: if the previous action inserted a trailing space
        // and this character is punctuation, delete the space first so the
        // symbol sits directly against the word (e.g. "hola." not "hola .").
        let isPunctuation = Self.smartPunctuationChars.contains(char)
        if isPunctuation && lastActionInsertedTrailingSpace && permissions.isAccessibilityGranted {
            debugLog("[SmartPunct] \"\(char)\" — deleted trailing space after \"\(previousWord ?? "?")\"")
            sendKey("delete")
        }
        lastActionInsertedTrailingSpace = false

        // Only inject keystrokes if we have permission.
        if permissions.isAccessibilityGranted {
            var flags: CGEventFlags = []
            if shouldUpper { flags.insert(.maskShift) }
            if isCommandActive { flags.insert(.maskCommand) }
            if isOptionActive { flags.insert(.maskAlternate) }
            if isControlActive { flags.insert(.maskControl) }

            // When modifier keys (Cmd/Opt/Ctrl) are held, use keyCode so the
            // shortcut reaches the target app correctly (e.g., Cmd+/ to comment).
            // For plain typing (no modifiers beyond shift), non-letter characters
            // use typeString with the resolved character to avoid keyboard layout
            // mismatches (e.g., US keyCode for "/" producing "¨" on Spanish layout).
            let hasActionModifier = isCommandActive || isOptionActive || isControlActive
            if injectionChar.isLetter || hasActionModifier {
                let charKey = String(injectionChar).lowercased()
                if let keyCode = KeystrokeEngine.keyCodes[charKey] {
                    KeystrokeEngine.sendKeystroke(keyCode: keyCode, flags: flags)
                } else {
                    let output = shouldUpper ? Character(injectionChar.uppercased()) : injectionChar
                    KeystrokeEngine.typeString(String(output))
                }
            } else {
                // Use the already-resolved character (char) — it accounts for
                // shift state via shiftedLabel resolution in handleKeyTap.
                KeystrokeEngine.typeString(String(char))
            }
        }

        // Punctuation after a word commits and resets, doesn't extend the buffer
        if isPunctuation {
            commitCurrentWord()
            // Sentence-ending punctuation: insert a trailing space and capitalize next
            if Self.sentenceEndingChars.contains(char) && permissions.isAccessibilityGranted {
                KeystrokeEngine.typeString(" ")
                lastActionInsertedTrailingSpace = true
            }
            // Set capitalization AFTER commit — commit clears it when flushing the buffer
            shouldCapitalizeNext = Self.sentenceEndingChars.contains(char)
            showNextWordPredictions()
            releaseOneShot()
            return
        }

        // Only append letters to the word buffer. Non-letter, non-punctuation
        // characters (apostrophe, quotes, @, #, etc.) act as word boundaries:
        // commit the current word and reset the buffer.
        if !isCommandActive && !isControlActive {
            if char.isLetter {
                let output = shouldUpper ? Character(char.uppercased()) : char
                currentWordBuffer.append(output)
                // Auto-capitalize consumed — clear so shift releases normally
                shouldCapitalizeNext = false
                updatePredictions()
            } else {
                commitCurrentWord()
                showNextWordPredictions()
            }
        }

        releaseOneShot()
    }

    /// Send a named key from the key code map. Only injects if permission is granted.
    /// Auto-capitalize shift (`shouldCapitalizeNext`) is excluded from the flags
    /// so that action keys like delete/return aren't sent as Shift+key.
    private func sendKey(_ name: String) {
        guard permissions.isAccessibilityGranted,
              let keyCode = KeystrokeEngine.keyCodes[name] else { return }

        var flags: CGEventFlags = []
        // Only include shift when the user explicitly activated it (not auto-capitalize)
        if isShiftActive && !shouldCapitalizeNext { flags.insert(.maskShift) }
        if isCapsLockActive { flags.insert(.maskShift) }
        if isCommandActive { flags.insert(.maskCommand) }
        if isOptionActive { flags.insert(.maskAlternate) }
        if isControlActive { flags.insert(.maskControl) }

        KeystrokeEngine.sendKeystroke(keyCode: keyCode, flags: flags)
    }

    private func releaseOneShot() {
        if isShiftActive && !isCapsLockActive && !shouldCapitalizeNext {
            isShiftActive = false
        }
        isCommandActive = false
        isOptionActive = false
        isControlActive = false
    }

    /// Commit the current word buffer: record for learning and update context.
    private func commitCurrentWord() {
        if !currentWordBuffer.isEmpty {
            if settings.learnFromTyping {
                predictionEngine.recordWordInContext(currentWordBuffer.lowercased(), after: previousWord)
            }
            previousWord = currentWordBuffer.lowercased()
            // A word was committed — clear auto-capitalization
            shouldCapitalizeNext = false
        }
        currentWordBuffer = ""
        predictions = []
    }

    /// Show next-word predictions based on the previous word.
    /// Called after a word is committed (typed, swiped, or prediction-inserted).
    private func showNextWordPredictions() {
        guard settings.predictionsEnabled, let prev = previousWord else {
            predictions = []
            return
        }
        syncLanguage()
        let count = settings.predictionCount
        var results = predictionEngine.predictNextWord(after: prev)

        // Pad with top unigram words if we don't have enough predictions
        if results.count < count {
            var seen = Set(results.map { $0.lowercased() })
            // Use a common first letter to broaden the pool
            for letter in "esacdptml" {
                guard results.count < count else { break }
                let extras = predictionEngine.predict(
                    prefix: String(letter),
                    previousWord: prev
                )
                for word in extras where results.count < count {
                    if seen.insert(word.lowercased()).inserted {
                        results.append(word)
                    }
                }
            }
        }

        guard !results.isEmpty else {
            predictions = []
            debugLog("[NextWord] after=\"\(prev)\" → (none)")
            return
        }
        // Capitalize predictions after sentence-ending punctuation (. ? !)
        let capped = shouldCapitalizeNext
            ? results.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            : results
        let displayed = centerBestPrediction(Array(capped.prefix(count)))
        predictions = displayed
        isShowingNextWordPredictions = true
        debugLog("[NextWord] after=\"\(prev)\" → \(capped)")
    }

    /// Keep language and settings in sync across engines.
    private func syncLanguage() {
        let lang = settings.selectedLanguage
        swipeEngine.language = lang
        predictionEngine.loadLanguage(lang)
        predictionEngine.maxResults = settings.predictionCount
    }

    private func updatePredictions() {
        guard settings.predictionsEnabled, !currentWordBuffer.isEmpty else {
            predictions = []
            return
        }

        // Ensure engine is loaded for current language
        syncLanguage()
        predictionEngine.maxResults = settings.predictionCount

        // Use the new PredictionEngine (trie + bigrams + user learning)
        var results = predictionEngine.predict(
            prefix: currentWordBuffer.lowercased(),
            previousWord: previousWord
        )

        // Pad with NSSpellChecker when the engine returns fewer than predictionCount
        let count = settings.predictionCount
        if results.count < count {
            let lang = LanguageManager.spellCheckerCode(for: settings.selectedLanguage)
            let checker = NSSpellChecker.shared
            var seen = Set(results.map { $0.lowercased() })

            let completions = checker.completions(
                forPartialWordRange: NSRange(location: 0, length: currentWordBuffer.utf16.count),
                in: currentWordBuffer,
                language: lang,
                inSpellDocumentWithTag: 0
            ) ?? []
            for word in completions where results.count < count {
                if seen.insert(word.lowercased()).inserted {
                    results.append(word)
                }
            }

            // Still short — try spell checker guesses
            if results.count < count {
                let guesses = checker.guesses(
                    forWordRange: NSRange(location: 0, length: currentWordBuffer.utf16.count),
                    in: currentWordBuffer,
                    language: lang,
                    inSpellDocumentWithTag: 0
                ) ?? []
                for word in guesses where results.count < count {
                    if seen.insert(word.lowercased()).inserted {
                        results.append(word)
                    }
                }
            }

            // Still short — pad with top frequency words starting with the same letter
            if results.count < count, let first = currentWordBuffer.first {
                let topWords = predictionEngine.predict(
                    prefix: String(first).lowercased(),
                    previousWord: previousWord
                )
                for word in topWords where results.count < count {
                    if seen.insert(word.lowercased()).inserted {
                        results.append(word)
                    }
                }
            }
        }

        // Capitalize predictions after sentence-ending punctuation (. ? !)
        if shouldCapitalizeNext {
            results = results.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        }

        // Reorder so the best prediction sits in the center slot
        predictions = centerBestPrediction(results)

        // Debug: log prefix query and results
        let prev = previousWord ?? "nil"
        debugLog("[Typing] prefix=\"\(currentWordBuffer.lowercased())\" prev=\(prev) → \(results)")
    }
}

import Foundation
import AppKit

// MARK: - Trie Node

/// A node in the frequency-weighted trie.
/// Each node stores its children keyed by character, an optional word
/// entry (non-nil if a valid word ends here), and the top-k completions
/// reachable from this prefix for fast prefix lookup.
final class TrieNode {
    var children: [Character: TrieNode] = [:]
    /// Non-nil if a complete word ends at this node.
    var wordEntry: WordEntry?
    /// Pre-computed top completions from this prefix, sorted by frequency descending.
    /// Populated during trie construction for O(1) prefix lookup.
    var topCompletions: [WordEntry] = []
}

/// A word with its unigram frequency.
struct WordEntry: Comparable {
    let word: String
    let frequency: Double

    static func < (lhs: WordEntry, rhs: WordEntry) -> Bool {
        lhs.frequency < rhs.frequency
    }
}

// MARK: - Bigram Entry

/// A bigram: previous word → next word with transition probability.
struct BigramEntry {
    let nextWord: String
    let logProbability: Double
}

// MARK: - User Word Entry

/// A word the user has typed, with usage tracking for personalization.
struct UserWordEntry: Codable {
    let word: String
    var count: Int
    var lastUsed: Date

    /// Compute a decayed score. Half-life of ~21 days.
    func decayedScore(now: Date = Date()) -> Double {
        let halfLife: TimeInterval = 21 * 24 * 3600 // 21 days in seconds
        let elapsed = now.timeIntervalSince(lastUsed)
        let decay = pow(0.5, elapsed / halfLife)
        return Double(count) * decay
    }
}

// MARK: - Prediction Engine

/// Offline, local-only word prediction engine.
///
/// Architecture:
/// 1. **Trie + Unigram**: 50k-word frequency dictionary in a trie for O(prefix) lookup
/// 2. **Bigram context**: P(word | previous_word) with Stupid Backoff to unigrams
/// 3. **User learning**: Tracks typed words with exponential decay, persisted to disk
/// 4. **Score combiner**: final_score = α·P_context + β·P_prefix + γ·user_boost
///
/// All data stays on device. No network calls.
@Observable
final class PredictionEngine {

    // MARK: - Configuration

    /// Backoff factor for bigram → unigram fallback (Stupid Backoff).
    private let backoffAlpha: Double = 0.4

    /// Weight for context (bigram) probability in final score.
    private let contextWeight: Double = 0.35

    /// Weight for prefix (unigram) probability in final score.
    private let prefixWeight: Double = 0.40

    /// Weight for user learning boost in final score.
    private let userWeight: Double = 0.25

    /// Maximum completions to return. Configurable via settings.
    var maxResults = 5

    /// How many top completions to store per trie node.
    private let topKPerNode = 15

    // MARK: - State

    private var root = TrieNode()

    /// Unigram log-probabilities keyed by word.
    private var unigramLogProbs: [String: Double] = [:]

    /// Bigram model: previous_word → [BigramEntry].
    private var bigramModel: [String: [BigramEntry]] = [:]

    /// User-learned words, persisted to disk.
    private var userDictionary: [String: UserWordEntry] = [:]

    /// The file URL for persisting the user dictionary.
    private let userDictionaryURL: URL

    /// Whether the engine has been loaded for a specific language.
    private(set) var loadedLanguage: String = ""

    /// The NSSpellChecker language code for the loaded language (e.g. "en", "es", "de").
    private var spellCheckerLanguage: String = "en"

    /// Public accessor for the spell checker language code.
    var spellCheckerLanguageCode: String { spellCheckerLanguage }

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let teklaDir = appSupport.appendingPathComponent("Tekla", isDirectory: true)
        try? FileManager.default.createDirectory(at: teklaDir, withIntermediateDirectories: true)
        userDictionaryURL = teklaDir.appendingPathComponent("user_dictionary.json")
        loadUserDictionary()
    }

    // MARK: - Accent Stripping

    /// Strip diacritics/accents from a string for fuzzy matching.
    /// "holandés" → "holandes", "café" → "cafe", "naïve" → "naive"
    /// Nonisolated so it can be called from background tasks.
    nonisolated private func stripAccents(_ string: String) -> String {
        string.folding(options: .diacriticInsensitive, locale: .current)
    }

    // MARK: - Loading Language Data

    /// Whether the trie has been populated (may still be loading in background).
    private(set) var isTrieReady = false

    /// Load the frequency dictionary and bigram data for a language.
    /// Call this when the language changes.
    func loadLanguage(_ languageCode: String) {
        guard languageCode != loadedLanguage else { return }
        loadedLanguage = languageCode
        spellCheckerLanguage = LanguageManager.spellCheckerCode(for: languageCode)
        isTrieReady = false

        root = TrieNode()
        unigramLogProbs = [:]
        bigramModel = [:]

        // Load unigram frequency data (fast phase: 1-2 letter prefixes)
        loadUnigrams(for: languageCode)

        // Load bigram data
        loadBigrams(for: languageCode)

        isTrieReady = true

        // Start deep harvest in background (3-5 letter prefix cascade)
        // This discovers words the shallow harvest missed (e.g. "estante").
        deepenHarvestInBackground()
    }

    /// Load unigram frequencies from bundled file or generate from NSSpellChecker.
    /// Format for bundled files: one line per word, "word<TAB>frequency".
    private func loadUnigrams(for languageCode: String) {
        // Try language-specific bundled file first
        if let entries = loadFrequencyFile(named: "freq_\(languageCode)") {
            populateTrieFromEntries(entries)
            return
        }

        // No bundled file — seed the trie from NSSpellChecker for this language.
        // Query common prefixes to build a frequency-ranked word list.
        let spellEntries = harvestWordsFromSpellChecker(language: spellCheckerLanguage)

        if !spellEntries.isEmpty {
            populateTrieFromEntries(spellEntries)
        } else {
            // Final fallback: built-in English frequencies (only useful for English)
            populateTrieFromEntries(builtInFrequencies())
        }
    }

    /// Insert a dictionary of word→frequency into the trie and unigram table.
    private func populateTrieFromEntries(_ entries: [String: Double]) {
        let maxFreq = entries.values.max() ?? 1.0

        for (word, freq) in entries {
            let normalizedFreq = freq / maxFreq
            let logProb = log(max(normalizedFreq, 1e-10))
            unigramLogProbs[word] = logProb

            // Also store accent-stripped version so swipe candidates
            // (which may lack diacritics) can look up their frequency.
            // Use a blend of accented and unaccented logProbs rather than
            // the max, so "estare" (from "estaré") doesn't completely
            // overshadow words like "estante" that have no accented form.
            // Blend = average of logProbs ≈ geometric mean of probabilities.
            let stripped = stripAccents(word)
            if stripped != word {
                if let existing = unigramLogProbs[stripped] {
                    unigramLogProbs[stripped] = (existing + logProb) / 2.0
                } else {
                    unigramLogProbs[stripped] = logProb
                }
            }

            insertIntoTrie(word: word, frequency: normalizedFreq)
        }

        // Build top-k completions for each trie node
        buildTopCompletions(node: root)
    }

    /// Harvest words from NSSpellChecker using a cascading prefix strategy.
    /// Phase 1+2 (1-letter + 2-letter prefixes) runs synchronously (~1.7s).
    /// Returns the initial entries and a set of 3-letter prefixes for deep harvest.
    private func harvestWordsFromSpellChecker(language: String) -> [String: Double] {
        let checker = NSSpellChecker.shared
        var entries: [String: Double] = [:]
        var threeLetterPrefixes = Set<String>()

        let letters = "abcdefghijklmnopqrstuvwxyz"

        // Phase 1: Single-letter prefixes
        for ch in letters {
            let prefix = String(ch)
            if let completions = checker.completions(
                forPartialWordRange: NSRange(location: 0, length: prefix.utf16.count),
                in: prefix,
                language: language,
                inSpellDocumentWithTag: 0
            ) {
                for (i, word) in completions.prefix(50).enumerated() {
                    let lower = word.lowercased()
                    guard lower.allSatisfy({ $0.isLetter }) else { continue }
                    let score = Double(50 - i) * 10.0
                    entries[lower] = max(entries[lower] ?? 0, score)
                }
            }
        }

        // Phase 2: Two-letter prefixes — also collect 3-letter prefix candidates
        for ch1 in letters {
            for ch2 in letters {
                let prefix = String(ch1) + String(ch2)
                if let completions = checker.completions(
                    forPartialWordRange: NSRange(location: 0, length: prefix.utf16.count),
                    in: prefix,
                    language: language,
                    inSpellDocumentWithTag: 0
                ) {
                    for (i, word) in completions.prefix(20).enumerated() {
                        let lower = word.lowercased()
                        guard lower.count >= 2, lower.allSatisfy({ $0.isLetter }) else { continue }
                        let score = Double(20 - i) * 8.0
                        entries[lower] = max(entries[lower] ?? 0, score)
                        // Collect 3-letter prefix from each discovered word
                        if lower.count >= 3 {
                            let pfx3 = String(lower.prefix(3))
                            threeLetterPrefixes.insert(pfx3)
                            let stripped3 = stripAccents(pfx3)
                            if stripped3 != pfx3 { threeLetterPrefixes.insert(stripped3) }
                        }
                    }
                }
            }
        }

        threeLetterPrefixes = threeLetterPrefixes.filter { $0.count == 3 && $0.allSatisfy { $0.isLetter } }

        // Store prefix candidates for background deep harvest
        pendingDeepHarvestPrefixes = threeLetterPrefixes
        pendingDeepHarvestLanguage = language

        return entries
    }

    /// Prefixes discovered during initial harvest, pending deep follow-up.
    private var pendingDeepHarvestPrefixes = Set<String>()
    private var pendingDeepHarvestLanguage = ""

    /// Run the deep cascade harvest in the background.
    /// Phases 3-5: query 3→4→5 letter prefixes to discover words
    /// that the shallow 2-letter harvest missed (e.g. "estante").
    func deepenHarvestInBackground() {
        let language = pendingDeepHarvestLanguage
        let initialPrefixes = pendingDeepHarvestPrefixes
        guard !initialPrefixes.isEmpty, !language.isEmpty else { return }
        pendingDeepHarvestPrefixes = [] // prevent re-entry

        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = self.runCascadeHarvest(initialPrefixes: initialPrefixes, language: language)
            self.mergeEntries(result)
        }
    }

    /// Run the deep cascade harvest on the main thread (NSSpellChecker requires main thread).
    /// Phases 3-5: query 3→4→5 letter prefixes to discover words
    /// that the shallow 2-letter harvest missed (e.g. "estante").
    private func runCascadeHarvest(initialPrefixes: Set<String>, language: String) -> [String: Double] {
        let checker = NSSpellChecker.shared
        var allEntries: [String: Double] = [:]

        func cascadePhase(prefixes: Set<String>, limit: Int, scoreMultiplier: Double) -> Set<String> {
            var nextPrefixes = Set<String>()
            for prefix in prefixes {
                if let completions = checker.completions(
                    forPartialWordRange: NSRange(location: 0, length: prefix.utf16.count),
                    in: prefix,
                    language: language,
                    inSpellDocumentWithTag: 0
                ) {
                    for (i, word) in completions.prefix(limit).enumerated() {
                        let lower = word.lowercased()
                        guard lower.count >= 2, lower.allSatisfy({ $0.isLetter }) else { continue }
                        let score = Double(limit - i) * scoreMultiplier
                        allEntries[lower] = max(allEntries[lower] ?? 0, score)
                        if lower.count >= prefix.count + 1 {
                            let nextPfx = String(lower.prefix(prefix.count + 1))
                            nextPrefixes.insert(nextPfx)
                            let stripped = self.stripAccents(nextPfx)
                            if stripped != nextPfx { nextPrefixes.insert(stripped) }
                        }
                    }
                }
            }
            return nextPrefixes
        }

        // Phase 3: 3-letter prefixes → discover 4-letter prefixes
        let pfx4 = cascadePhase(prefixes: initialPrefixes, limit: 10, scoreMultiplier: 7.0)
        // Phase 4: 4-letter prefixes → discover 5-letter prefixes
        let pfx5 = cascadePhase(prefixes: pfx4, limit: 10, scoreMultiplier: 6.0)
        // Phase 5: 5-letter prefixes → final words
        let _ = cascadePhase(prefixes: pfx5, limit: 10, scoreMultiplier: 5.0)

        return allEntries
    }

    /// Merge new word entries into the existing trie and unigram table.
    /// Called after background deep harvest completes.
    private func mergeEntries(_ entries: [String: Double]) {
        let maxFreq = entries.values.max() ?? 1.0

        var addedCount = 0
        for (word, freq) in entries {
            // Skip words already in the trie (they have better frequency scores from phase 1-2)
            if unigramLogProbs[word] != nil { continue }

            let normalizedFreq = freq / maxFreq
            let logProb = log(max(normalizedFreq, 1e-10))
            unigramLogProbs[word] = logProb

            let stripped = stripAccents(word)
            if stripped != word {
                if let existing = unigramLogProbs[stripped] {
                    unigramLogProbs[stripped] = (existing + logProb) / 2.0
                } else {
                    unigramLogProbs[stripped] = logProb
                }
            }

            insertIntoTrie(word: word, frequency: normalizedFreq)
            addedCount += 1
        }

        if addedCount > 0 {
            // Rebuild top-k completions to include new words
            buildTopCompletions(node: root)
        }
    }

    /// Load a frequency file from the bundle.
    private func loadFrequencyFile(named name: String) -> [String: Double]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var entries: [String: Double] = [:]
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let freq = Double(parts[1]) else { continue }
            let word = String(parts[0]).lowercased()
            guard word.count >= 1, word.allSatisfy({ $0.isLetter }) else { continue }
            entries[word] = freq
        }
        return entries.isEmpty ? nil : entries
    }

    /// Load bigram data from bundled file.
    /// Format: "prev_word<TAB>next_word<TAB>log_probability"
    private func loadBigrams(for languageCode: String) {
        let data = loadBigramFile(named: "bigrams_\(languageCode)")
            ?? loadBigramFile(named: "bigrams_en")
            ?? [:]
        bigramModel = data
    }

    private func loadBigramFile(named name: String) -> [String: [BigramEntry]]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        var model: [String: [BigramEntry]] = [:]
        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3,
                  let logProb = Double(parts[2]) else { continue }
            let prev = String(parts[0]).lowercased()
            let next = String(parts[1]).lowercased()
            model[prev, default: []].append(BigramEntry(nextWord: next, logProbability: logProb))
        }
        return model.isEmpty ? nil : model
    }

    // MARK: - Trie Operations

    /// Insert a word into the trie with its frequency.
    private func insertIntoTrie(word: String, frequency: Double) {
        var node = root
        for char in word {
            if node.children[char] == nil {
                node.children[char] = TrieNode()
            }
            node = node.children[char]!
        }
        node.wordEntry = WordEntry(word: word, frequency: frequency)
    }

    /// Recursively build top-k completions for each node.
    @discardableResult
    private func buildTopCompletions(node: TrieNode) -> [WordEntry] {
        var completions: [WordEntry] = []

        // Add this node's own word if it has one
        if let entry = node.wordEntry {
            completions.append(entry)
        }

        // Gather completions from all children
        for (_, child) in node.children {
            completions.append(contentsOf: buildTopCompletions(node: child))
        }

        // Keep only top-k by frequency
        completions.sort(by: >)
        if completions.count > topKPerNode {
            completions = Array(completions.prefix(topKPerNode))
        }

        node.topCompletions = completions
        return completions
    }

    /// Find the trie node for a given prefix.
    private func findNode(prefix: String) -> TrieNode? {
        var node = root
        for char in prefix {
            guard let next = node.children[char] else { return nil }
            node = next
        }
        return node
    }

    /// Get candidate words for swipe-to-type: words starting with `firstLetter`
    /// and ending with `lastLetter`, ranked by frequency.
    /// Returns up to 50 candidates for geometric matching.
    ///
    /// Unlike `predict()`, this does a full DFS through the subtree to find all
    /// words matching the first/last letter constraint, not just the top-k.
    func completionsForSwipe(firstLetter: Character, lastLetter: Character, minLength: Int = 2, maxLength: Int = 20) -> [String] {
        guard let startNode = findNode(prefix: String(firstLetter)) else { return [] }

        var matches: [WordEntry] = []
        collectWords(from: startNode, endingWith: lastLetter, minLength: minLength, maxLength: maxLength, into: &matches)

        // Sort by frequency descending, return top 50
        matches.sort(by: >)
        return Array(matches.prefix(50).map(\.word))
    }

    /// Recursively collect all words from a trie subtree that end with a specific letter
    /// and within the given length range.
    private func collectWords(from node: TrieNode, endingWith lastLetter: Character, minLength: Int, maxLength: Int, into results: inout [WordEntry]) {
        if let entry = node.wordEntry,
           entry.word.last == lastLetter,
           entry.word.count >= minLength,
           entry.word.count <= maxLength {
            results.append(entry)
        }
        // Early exit if we already have enough candidates
        guard results.count < 500 else { return }
        for (_, child) in node.children {
            collectWords(from: child, endingWith: lastLetter, minLength: minLength, maxLength: maxLength, into: &results)
        }
    }

    // MARK: - Spatially-Pruned Trie Walk

    /// Walk the trie with spatial pruning: at each depth level, only explore
    /// child branches whose letter has non-trivial probability of being near
    /// the swipe path. This is the core SHARK2-style optimization that avoids
    /// blind DFS through thousands of irrelevant branches.
    ///
    /// - Parameters:
    ///   - firstLetters: Possible first letters (from swipe start proximity)
    ///   - lastLetters: Possible last letters (from swipe end proximity)
    ///   - minLength: Minimum word length to include
    ///   - maxLength: Maximum word length to include
    ///   - spatialMap: For each letter a-z, the maximum Gaussian probability it had
    ///     at any point along the swipe path. Letters with prob < threshold are pruned.
    /// - Returns: Set of candidate words matching the constraints.
    func swipeCandidatesFromTrie(
        firstLetters: [Character],
        lastLetters: [Character],
        minLength: Int,
        maxLength: Int,
        spatialMap: [Character: Double]
    ) -> Set<String> {
        let lastLetterSet = Set(lastLetters)
        var candidates = Set<String>()
        // Letters the path came near — used for pruning entire subtrees.
        // Threshold lowered to 0.005 (~3σ away) to avoid over-pruning letters
        // that the finger passed near but not directly over.
        let reachableLetters = Set(spatialMap.filter { $0.value >= 0.005 }.keys)

        for firstLetter in firstLetters {
            guard let startNode = findNode(prefix: String(firstLetter)) else { continue }
            spatialCollect(
                from: startNode,
                depth: 1,
                lastLetterSet: lastLetterSet,
                minLength: minLength,
                maxLength: maxLength,
                reachableLetters: reachableLetters,
                into: &candidates
            )
        }
        return candidates
    }

    /// Spatially-pruned DFS: only explore children whose letter is spatially
    /// reachable from the swipe path (probability >= threshold).
    private func spatialCollect(
        from node: TrieNode,
        depth: Int,
        lastLetterSet: Set<Character>,
        minLength: Int,
        maxLength: Int,
        reachableLetters: Set<Character>,
        into results: inout Set<String>
    ) {
        // Check if this node has a complete word matching our constraints
        if let entry = node.wordEntry {
            let len = entry.word.count
            if len >= minLength,
               len <= maxLength,
               let lastChar = entry.word.last,
               lastLetterSet.contains(lastChar) {
                results.insert(entry.word)
            }
        }
        // Stop descending if we've hit max depth
        guard depth < maxLength else { return }
        // Cap at 2000 to prevent pathological cases
        guard results.count < 2000 else { return }
        for (char, child) in node.children {
            // Spatial pruning: skip branches for letters the path never came near
            if depth >= 2, !reachableLetters.contains(char) { continue }
            spatialCollect(from: child, depth: depth + 1,
                         lastLetterSet: lastLetterSet,
                         minLength: minLength, maxLength: maxLength,
                         reachableLetters: reachableLetters, into: &results)
        }
    }

    // MARK: - Frequency Lookup for Swipe Scoring

    /// Look up the unigram log-probability for a word.
    /// Returns a value in approximately [-15, 0] where 0 = most common word.
    /// Returns nil if the word is not in the frequency table.
    func wordFrequency(_ word: String) -> Double? {
        let lower = word.lowercased()
        return unigramLogProbs[lower] ?? unigramLogProbs[stripAccents(lower)]
    }

    /// Check if a word is recognized by NSSpellChecker for the current language.
    /// This is a fast way to verify a candidate is a real word in the target
    /// language without needing it to be in our trie.
    func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(of: word, startingAt: 0, language: spellCheckerLanguage, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound // no misspelling found = word is valid
    }

    // MARK: - Prediction API

    /// Get word predictions given a prefix and optional previous word for context.
    ///
    /// - Parameters:
    ///   - prefix: The partially typed word (lowercased).
    ///   - previousWord: The word before the cursor (for bigram context). Nil if start of sentence.
    /// - Returns: Up to `maxResults` predicted words, best first.
    func predict(prefix: String, previousWord: String? = nil) -> [String] {
        let lowPrefix = prefix.lowercased()
        guard !lowPrefix.isEmpty else { return [] }

        // 1. Get prefix completions from trie
        var candidates: [String: Double] = [:]

        if let node = findNode(prefix: lowPrefix) {
            for entry in node.topCompletions {
                candidates[entry.word] = prefixScore(entry)
            }
        }

        // 2. Merge live NSSpellChecker results for the current language.
        //    This ensures words not in the pre-seeded trie still appear,
        //    and that predictions are always language-appropriate.
        //    Use the BETTER of the trie score and the live score so words
        //    that were inserted into the trie with artificially low frequency
        //    (via user learning) don't get penalized.
        let liveCompletions = NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(location: 0, length: lowPrefix.utf16.count),
            in: lowPrefix,
            language: spellCheckerLanguage,
            inSpellDocumentWithTag: 0
        ) ?? []

        for (i, word) in liveCompletions.prefix(10).enumerated() {
            let lower = word.lowercased()
            guard lower.hasPrefix(lowPrefix) else { continue }
            // Score based on rank from spell checker (higher rank = higher score).
            // Use a moderate base so these compete fairly with trie entries.
            let liveScore = prefixWeight * log(max(Double(10 - i) / 10.0, 0.05))
            // Take the better of the existing trie score or the live score
            candidates[lower] = max(candidates[lower] ?? -Double.infinity, liveScore)
        }

        // 3. If we have a previous word, add bigram candidates that match the prefix
        if let prev = previousWord?.lowercased(), let bigrams = bigramModel[prev] {
            for bigram in bigrams {
                if bigram.nextWord.hasPrefix(lowPrefix) {
                    let existing = candidates[bigram.nextWord] ?? -Double.infinity
                    let bigramScore = contextScore(bigram)
                    candidates[bigram.nextWord] = max(existing, bigramScore)
                }
            }
        }

        // 4. Add exact prefix match if it exists in unigrams (ensure the typed word is a candidate)
        if unigramLogProbs[lowPrefix] != nil, candidates[lowPrefix] == nil {
            if let node = findNode(prefix: lowPrefix), let entry = node.wordEntry {
                candidates[lowPrefix] = prefixScore(entry)
            }
        }

        // 5. Boost candidates from user dictionary.
        //    The boost reorders candidates but is capped to avoid a single
        //    heavily-used word from crushing all alternatives out of the list.
        let now = Date()
        for (word, userEntry) in userDictionary {
            if word.hasPrefix(lowPrefix) {
                let boost = userBoost(userEntry, now: now)
                if candidates[word] != nil {
                    // Word already in candidates — just boost it
                    candidates[word]! += boost
                } else {
                    // Word only in user dict — give it a modest base so it
                    // appears in the list but doesn't dominate
                    candidates[word] = -1.0 + boost
                }
            }
        }

        // 6. Score and rank
        var scored: [(String, Double)] = candidates.map { ($0.key, $0.value) }
        scored.sort { $0.1 > $1.1 }

        return Array(scored.prefix(maxResults).map(\.0))
    }

    /// Compute the prefix score for a trie word entry.
    private func prefixScore(_ entry: WordEntry) -> Double {
        // log(frequency) serves as the base score
        let logFreq = log(max(entry.frequency, 1e-10))
        return prefixWeight * logFreq
    }

    /// Compute the context score for a bigram entry.
    private func contextScore(_ bigram: BigramEntry) -> Double {
        // Bigram log-probability already encodes context
        return contextWeight * bigram.logProbability
    }

    /// Compute the user boost for a learned word.
    private func userBoost(_ entry: UserWordEntry, now: Date) -> Double {
        let decayed = entry.decayedScore(now: now)
        // Normalize: log(1 + decayed) to avoid huge boosts
        return userWeight * log(1.0 + decayed)
    }

    /// Predict the next word given the previous word, without any prefix.
    ///
    /// Uses bigram context when available, falling back to the most frequent
    /// unigram words if no bigrams are found for the given word.
    ///
    /// - Parameter word: The word that was just completed.
    /// - Returns: Up to `maxResults` predicted next words, best first.
    func predictNextWord(after word: String) -> [String] {
        let lowWord = word.lowercased()
        var candidates: [String: Double] = [:]

        // 1. Bigram candidates from the model
        if let bigrams = bigramModel[lowWord] {
            for bigram in bigrams {
                candidates[bigram.nextWord] = bigram.logProbability
            }
        }

        // 2. If no bigrams, fall back to top unigram words
        if candidates.isEmpty {
            let topUnigrams = unigramLogProbs.sorted { $0.value > $1.value }.prefix(maxResults)
            for (unigramWord, logProb) in topUnigrams {
                candidates[unigramWord] = logProb
            }
        }

        // 3. Sort by score, return top N
        return candidates.sorted { $0.value > $1.value }
            .prefix(maxResults)
            .map(\.key)
    }

    /// Returns top bigram-predicted words after `previousWord` that start with
    /// `firstLetter`. Used to inject contextually likely words into swipe alternatives.
    ///
    /// For example, after "hola" with firstLetter "c", returns ["como", "cariño", ...]
    func bigramCompletions(after previousWord: String, startingWith firstLetter: Character, limit: Int = 3) -> [String] {
        let prev = previousWord.lowercased()
        guard let bigrams = bigramModel[prev] else { return [] }

        let lower = Character(firstLetter.lowercased())
        return bigrams
            .filter { $0.nextWord.first == lower }
            .sorted { $0.logProbability > $1.logProbability }
            .prefix(limit)
            .map(\.nextWord)
    }

    // MARK: - User Learning

    /// Record that the user typed or selected a word.
    /// - Parameter weight: How many "uses" to count. Defaults to 1.
    ///   Use a higher weight for corrections (user explicitly chose this word over alternatives).
    func recordWord(_ word: String, weight: Int = 1) {
        let lower = word.lowercased()
        guard lower.count >= 2, lower.allSatisfy({ $0.isLetter }) else { return }

        // Store under both the original and accent-stripped key so that
        // swipe candidates (which may lack diacritics) find the entry.
        let keys = Set([lower, stripAccents(lower)])
        for key in keys {
            if var entry = userDictionary[key] {
                entry.count += weight
                entry.lastUsed = Date()
                userDictionary[key] = entry
            } else {
                userDictionary[key] = UserWordEntry(word: key, count: weight, lastUsed: Date())
            }
        }

        // Also insert into trie if not already present.
        // Use a moderate frequency (median level) so user-learned words
        // compete fairly with harvested words rather than sinking to the bottom.
        if findNode(prefix: lower)?.wordEntry == nil {
            insertIntoTrie(word: lower, frequency: 0.3)
            rebuildTopCompletionsForPath(lower)
        }

        saveUserDictionary()
    }

    /// Record that the user completed a word after a previous word (for potential future trigram learning).
    func recordWordInContext(_ word: String, after previousWord: String?) {
        recordWord(word)
        // Future: could learn user-specific bigrams here
    }

    /// Rebuild top completions along the path of a word (after inserting a new word).
    private func rebuildTopCompletionsForPath(_ word: String) {
        // Simple approach: rebuild from root. For a trie of 50k words this is fast.
        buildTopCompletions(node: root)
    }

    // MARK: - Swipe Re-ranking

    /// Re-rank swipe candidates using the language model.
    ///
    /// The swipe engine produces candidates based on geometric matching.
    /// This method re-scores them using:
    /// - Unigram frequency (common words rank higher)
    /// - Bigram context (if previous word is known)
    /// - User learning boost (dominates after even one correction)
    ///
    /// - Parameters:
    ///   - candidates: Swipe candidates with their Bayesian scores (higher = better match).
    ///   - previousWord: The word before the swipe.
    /// - Returns: Re-ranked candidates, best first.
    func rerankSwipeCandidates(_ candidates: [(word: String, geometricScore: Double)],
                                previousWord: String? = nil) -> [String] {
        guard !candidates.isEmpty else { return [] }

        // Normalize Bayesian scores to 0..1 range (higher = better, no inversion needed).
        // Use a minimum range to prevent tiny absolute differences from creating
        // huge normalized gaps.
        let maxGeo = candidates.map(\.geometricScore).max() ?? 1.0
        let minGeo = candidates.map(\.geometricScore).min() ?? 0.0
        let geoRange = max(maxGeo - minGeo, maxGeo * 0.5)  // relative minimum range

        let now = Date()
        var scored: [(String, Double)] = []

        for candidate in candidates {
            let word = candidate.word.lowercased()
            let wordStripped = stripAccents(word)

            // Geometric similarity (already higher = better, just normalize to 0..1)
            let geoSim = geoRange > 0 ? (candidate.geometricScore - minGeo) / geoRange : 1.0

            // Unigram probability — try exact match first, then accent-stripped
            let unigramScore = unigramLogProbs[word]
                ?? unigramLogProbs[wordStripped]
                ?? -15.0

            // Bigram context: check if a real bigram exists for this candidate.
            // A direct bigram hit is a strong signal that this word naturally follows
            // the previous word (e.g., "hola" → "como"). Backoff to unigram is much
            // weaker and should not compete with real bigram matches.
            var hasBigramHit = false
            var bigramLogProb = 0.0
            if let prev = previousWord?.lowercased(),
               let bigrams = bigramModel[prev] {
                if let match = bigrams.first(where: { $0.nextWord == word || $0.nextWord == wordStripped }) {
                    hasBigramHit = true
                    bigramLogProb = match.logProbability
                }
            }

            // User learning boost.
            // Capped to prevent feedback loops where a wrong auto-typed prediction
            // accumulates a huge bonus and becomes permanently stuck at #1.
            // The boost is a light tiebreaker, not a ranking override.
            var userBonus = 0.0
            if let userEntry = userDictionary[word] ?? userDictionary[wordStripped] {
                let decayed = userEntry.decayedScore(now: now)
                // log1p grows slowly: 1 use → 0.05, 5 uses → 0.07, 20 uses → 0.08
                // Cap at 0.10 so it can break ties but never override geometry.
                userBonus = min(0.10, 0.03 * log1p(decayed))
            }

            // Combined score: geometric + language model + user learning.
            let normalizedUnigram = max(0, 1.0 + unigramScore / 15.0)

            // Bigram bonus: when a real bigram exists, give an additive bonus
            // proportional to the bigram probability.
            // Bigram log probs range from ~-6 (very common) to ~-12 (rare).
            // Map to a bonus of ~0.05 to ~0.25.
            let bigramBonus = hasBigramHit ? max(0.05, 0.25 * (1.0 + bigramLogProb / 12.0)) : 0.0

            // Base score: geometry dominates, unigram is a tiebreaker.
            // The geometric score already incorporates frequency via its pFrequency
            // channel, so we give it dominant weight here.
            let baseScore = 0.80 * geoSim
                          + 0.20 * normalizedUnigram

            // Bigram and user bonuses are additive — they lift candidates above
            // their geometric ranking when strong contextual evidence exists.
            let finalScore = baseScore + bigramBonus + userBonus

            scored.append((word, finalScore))
        }

        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(maxResults).map(\.0))
    }

    // MARK: - Persistence

    private func loadUserDictionary() {
        guard FileManager.default.fileExists(atPath: userDictionaryURL.path) else { return }
        do {
            let data = try Data(contentsOf: userDictionaryURL)
            let entries = try JSONDecoder().decode([String: UserWordEntry].self, from: data)
            userDictionary = entries
        } catch {
            // Non-critical: start with empty user dictionary
            userDictionary = [:]
        }
    }

    private func saveUserDictionary() {
        do {
            let data = try JSONEncoder().encode(userDictionary)
            try data.write(to: userDictionaryURL, options: .atomic)
        } catch {
            // Non-critical: user learning just won't persist this session
        }
    }

    /// Clear all learned words from the user dictionary.
    func clearUserDictionary() {
        userDictionary = [:]
        saveUserDictionary()
    }

    /// The number of words the user dictionary has learned.
    var learnedWordCount: Int { userDictionary.count }

    /// Prune old/low-value entries from the user dictionary.
    /// Call periodically (e.g., on app launch).
    func pruneUserDictionary(maxEntries: Int = 10000) {
        let now = Date()
        // Remove entries with very low decayed scores
        userDictionary = userDictionary.filter { _, entry in
            entry.decayedScore(now: now) > 0.01
        }
        // If still too many, keep the top entries by score
        if userDictionary.count > maxEntries {
            let sorted = userDictionary.sorted { $0.value.decayedScore(now: now) > $1.value.decayedScore(now: now) }
            userDictionary = Dictionary(uniqueKeysWithValues: sorted.prefix(maxEntries).map { ($0.key, $0.value) })
        }
        saveUserDictionary()
    }

    // MARK: - Built-in Frequency Data

    /// Fallback frequency data when no bundled file is available.
    /// Top ~2000 English words with approximate relative frequencies.
    private func builtInFrequencies() -> [String: Double] {
        // These are approximate word frequencies from common English corpora.
        // The frequency values are relative counts (higher = more common).
        let words: [(String, Double)] = [
            ("the", 69971), ("be", 37919), ("of", 36412), ("and", 28946),
            ("a", 21718), ("to", 26145), ("in", 21343), ("he", 12406),
            ("have", 12324), ("it", 12108), ("that", 11454), ("for", 9543),
            ("they", 8940), ("i", 8855), ("with", 7739), ("as", 7328),
            ("not", 7243), ("on", 6741), ("she", 6360), ("at", 6128),
            ("by", 5580), ("this", 5353), ("we", 4955), ("you", 4836),
            ("do", 4637), ("but", 4505), ("from", 4355), ("or", 3879),
            ("which", 3395), ("one", 3352), ("would", 3282), ("all", 3159),
            ("will", 3112), ("there", 2902), ("say", 2794), ("who", 2741),
            ("make", 2563), ("when", 2533), ("can", 2435), ("more", 2328),
            ("if", 2262), ("no", 2168), ("man", 2082), ("out", 2065),
            ("other", 1977), ("so", 1966), ("what", 1918), ("time", 1903),
            ("up", 1861), ("go", 1842), ("about", 1764), ("than", 1746),
            ("into", 1594), ("could", 1569), ("state", 1559), ("only", 1520),
            ("new", 1479), ("year", 1463), ("some", 1459), ("take", 1440),
            ("come", 1403), ("these", 1373), ("know", 1367), ("see", 1339),
            ("use", 1300), ("get", 1294), ("like", 1247), ("then", 1235),
            ("first", 1200), ("any", 1172), ("work", 1146), ("now", 1123),
            ("may", 1097), ("such", 1093), ("give", 1080), ("over", 1063),
            ("think", 1042), ("most", 1024), ("even", 1012), ("find", 993),
            ("day", 979), ("also", 975), ("after", 968), ("way", 951),
            ("many", 937), ("must", 920), ("look", 909), ("before", 895),
            ("great", 883), ("back", 876), ("through", 862), ("long", 848),
            ("where", 841), ("much", 834), ("should", 827), ("well", 820),
            ("people", 812), ("down", 805), ("own", 798), ("just", 791),
            ("because", 784), ("good", 777), ("each", 770), ("those", 763),
            ("feel", 756), ("seem", 749), ("how", 742), ("high", 735),
            ("too", 728), ("place", 721), ("little", 714), ("world", 707),
            ("very", 700), ("still", 693), ("nation", 686), ("hand", 679),
            ("old", 672), ("life", 665), ("tell", 658), ("write", 651),
            ("become", 644), ("here", 637), ("show", 630), ("house", 623),
            ("both", 616), ("between", 609), ("need", 602), ("mean", 595),
            ("call", 588), ("develop", 581), ("under", 574), ("last", 567),
            ("right", 560), ("move", 553), ("thing", 546), ("general", 539),
            ("school", 532), ("never", 525), ("same", 518), ("another", 511),
            ("begin", 504), ("while", 497), ("number", 490), ("part", 483),
            ("turn", 476), ("real", 469), ("leave", 462), ("might", 455),
            ("want", 448), ("point", 441), ("form", 434), ("off", 427),
            ("child", 420), ("few", 413), ("small", 406), ("since", 399),
            ("against", 392), ("ask", 385), ("late", 378), ("home", 371),
            ("interest", 364), ("large", 357), ("person", 350), ("end", 343),
            ("open", 336), ("public", 329), ("follow", 322), ("during", 315),
            ("present", 308), ("without", 301), ("again", 294), ("hold", 287),
            ("govern", 280), ("around", 273), ("possible", 266), ("head", 259),
            ("consider", 252), ("word", 245), ("program", 238), ("problem", 231),
            ("however", 224), ("lead", 217), ("system", 210), ("set", 203),
            ("order", 196), ("eye", 189), ("plan", 182), ("run", 175),
            ("keep", 168), ("face", 161), ("fact", 154), ("group", 147),
            ("play", 140), ("stand", 133), ("increase", 126), ("early", 119),
            ("course", 112), ("change", 105), ("help", 98), ("line", 91),
            // Common everyday words for better coverage
            ("hello", 85), ("thanks", 82), ("please", 80), ("sorry", 78),
            ("sure", 76), ("okay", 74), ("yeah", 72), ("yes", 70),
            ("maybe", 68), ("really", 66), ("actually", 64), ("probably", 62),
            ("always", 60), ("never", 58), ("today", 56), ("tomorrow", 54),
            ("yesterday", 52), ("morning", 50), ("night", 48), ("evening", 46),
            ("week", 44), ("month", 42), ("happy", 40), ("love", 38),
            ("want", 36), ("need", 34), ("going", 32), ("doing", 30),
            ("having", 28), ("being", 26), ("getting", 24), ("making", 22),
            ("taking", 20), ("coming", 18), ("looking", 16), ("working", 14),
            ("something", 85), ("nothing", 70), ("everything", 65),
            ("everyone", 55), ("someone", 50), ("anything", 45),
            ("already", 60), ("enough", 55), ("different", 50),
            ("important", 65), ("possible", 45), ("probably", 55),
            ("together", 50), ("another", 60), ("without", 55),
            ("between", 50), ("through", 45), ("before", 55),
            ("after", 50), ("again", 45), ("never", 40),
            ("always", 55), ("often", 40), ("sometimes", 35),
            ("usually", 30), ("perhaps", 25), ("quite", 20),
            ("rather", 18), ("almost", 35), ("already", 30),
            ("message", 40), ("phone", 38), ("email", 36), ("meeting", 34),
            ("project", 32), ("company", 30), ("money", 28), ("friend", 26),
            ("family", 24), ("question", 22), ("answer", 20), ("problem", 18),
            ("thank", 80), ("thought", 60), ("thing", 55), ("things", 50),
            ("think", 65), ("right", 60), ("going", 55), ("know", 75),
            ("about", 70), ("would", 65), ("could", 60), ("should", 55),
            ("their", 70), ("there", 65), ("where", 55), ("which", 50),
            ("these", 45), ("those", 40), ("other", 55), ("every", 35),
            ("because", 60), ("before", 45), ("after", 40), ("while", 35),
            ("since", 30), ("until", 25), ("though", 20), ("although", 15),
            ("weather", 20), ("water", 25), ("dinner", 20), ("lunch", 18),
            ("breakfast", 16), ("coffee", 22), ("food", 20), ("music", 18),
            ("movie", 16), ("book", 22), ("read", 20), ("write", 18),
            ("watch", 16), ("listen", 14), ("talk", 22), ("speak", 18),
            ("learn", 16), ("study", 14), ("teach", 12), ("understand", 20),
            ("remember", 18), ("forget", 16), ("believe", 20), ("wonder", 14),
            ("guess", 12), ("suppose", 10), ("imagine", 14), ("happen", 16),
            ("start", 25), ("stop", 20), ("finish", 18), ("continue", 16),
            ("try", 30), ("keep", 25), ("let", 28), ("put", 22),
            ("bring", 18), ("send", 20), ("receive", 14), ("buy", 16),
            ("sell", 12), ("pay", 18), ("spend", 14), ("save", 16),
            ("sleep", 14), ("wake", 12), ("eat", 16), ("drink", 14),
            ("drive", 12), ("walk", 14), ("travel", 12), ("visit", 10),
            ("pretty", 14), ("beautiful", 12), ("nice", 18), ("great", 25),
            ("good", 30), ("bad", 18), ("better", 20), ("best", 18),
            ("worse", 10), ("worst", 8), ("easy", 14), ("hard", 16),
            ("fast", 12), ("slow", 10), ("strong", 12), ("weak", 8),
            ("new", 25), ("young", 12), ("old", 14), ("big", 16),
            ("small", 14), ("long", 16), ("short", 12), ("hot", 10),
            ("cold", 12), ("warm", 10), ("cool", 12),
        ]
        var dict: [String: Double] = [:]
        for (word, freq) in words {
            // Use max in case of duplicates
            dict[word] = max(dict[word] ?? 0, freq)
        }
        return dict
    }
}

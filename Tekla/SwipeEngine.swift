import Foundation
import AppKit
import CoreGraphics

/// A key with its Gaussian proximity probability to a point on the swipe path.
struct KeyProximity {
    let character: Character
    /// Gaussian probability 0.0...1.0 — higher means the point was closer to this key.
    let probability: Double
    /// Raw Euclidean distance in points from the swipe point to the key center.
    let distance: CGFloat
}

/// Matches a mouse-drag path over the keyboard to dictionary words
/// using the SHARK2 template-matching algorithm.
/// Uses NSSpellChecker to generate language-aware candidates.
@Observable
final class SwipeEngine {

    /// Whether a swipe gesture is currently in progress.
    private(set) var isSwiping = false

    /// Raw points collected during the current swipe.
    private(set) var swipePath: [CGPoint] = []

    /// Characters the swipe path has passed through (for visual trail).
    private(set) var swipedLetters: [Character] = []

    /// Key center positions mapped by lowercase character.
    /// Must be set by the keyboard layout view after layout.
    var keyCenters: [Character: CGPoint] = [:]

    /// Key bounding rects for hit testing.
    var keyRects: [Character: CGRect] = [:] {
        didSet { _cachedKeyWidth = nil }
    }

    /// For each point in the swipe, the top nearby keys with Gaussian probabilities.
    /// Used for near-path letter collection and relaxed first/last matching.
    private(set) var swipeProximities: [[KeyProximity]] = []

    /// The current language code for NSSpellChecker (e.g. "en", "es", "de").
    var language: String = "en"

    /// Reference to the prediction engine for trie-based candidate lookup.
    weak var predictionEngine: PredictionEngine?

    init() {
        Self.clearDebugLog()
    }

    // MARK: - Gesture Lifecycle

    func beginSwipe(at point: CGPoint) {
        isSwiping = true
        swipePath = [point]
        swipedLetters = []
        swipeProximities = []
        debugLines = []

        let proxies = nearestKeys(to: point)
        swipeProximities.append(proxies)
        if let letter = proxies.first?.character {
            swipedLetters.append(letter)
        }
    }

    func continueSwipe(at point: CGPoint) {
        guard isSwiping else { return }

        // Skip near-duplicate points (< 3pt apart)
        if let last = swipePath.last, hypot(point.x - last.x, point.y - last.y) < 3 {
            return
        }
        swipePath.append(point)

        let proxies = nearestKeys(to: point)
        swipeProximities.append(proxies)

        // Track the primary (most likely) key for the swiped letters sequence
        if let letter = proxies.first?.character, letter != swipedLetters.last {
            swipedLetters.append(letter)
        }
    }

    /// End the swipe and return scored candidates (word + geometric score).
    /// The geometric scores allow the prediction engine to re-rank with LM context.
    func endSwipe() -> [(word: String, geometricScore: Double)] {
        guard isSwiping else { return [] }
        isSwiping = false

        let results = matchSwipeWithScores()

        // Log debug trace before clearing state (full results for visibility)
        logSwipeDebugTrace(results: results)

        swipePath = []
        swipedLetters = []
        swipeProximities = []
        // Only return top 10 to the caller
        return Array(results.prefix(10))
    }



    // MARK: - Intentional Key Extraction

    /// Extract keys the user **intended** to swipe through by detecting
    /// direction changes in the swipe path.
    ///
    /// When swiping a word, the user moves toward each letter's key in
    /// sequence. At each intended key the path changes direction to head
    /// toward the next letter. Keys crossed in a straight line between
    /// two direction changes are transit noise and get filtered out.
    ///
    /// Algorithm:
    /// 1. Smooth the path to reduce jitter.
    /// 2. Find all points where the path direction changes significantly.
    /// 3. For each turn point, record the nearest key.
    /// 4. Always include the first and last keys.
    func extractIntentionalKeys() -> [Character] {
        guard swipePath.count >= 3, !swipeProximities.isEmpty else {
            return swipedLetters.reduce(into: [Character]()) { r, c in
                if r.last != c { r.append(c) }
            }
        }

        // Smooth the path to reduce jitter before detecting turns.
        let smoothed: [CGPoint] = {
            let window = 5
            let half = window / 2
            return swipePath.indices.map { i in
                let lo = max(0, i - half)
                let hi = min(swipePath.count - 1, i + half)
                let count = CGFloat(hi - lo + 1)
                var sx: CGFloat = 0, sy: CGFloat = 0
                for j in lo...hi {
                    sx += swipePath[j].x
                    sy += swipePath[j].y
                }
                return CGPoint(x: sx / count, y: sy / count)
            }
        }()

        // Detect direction changes: compute the angle between consecutive
        // direction vectors. A significant change (> threshold) marks a
        // turn toward a new letter target.
        let angleThreshold: Double = 40.0 * .pi / 180.0
        let minTurnDist = averageKeyWidth * 0.5

        var turnIndices: [Int] = [0] // always include start

        for i in 1..<(smoothed.count - 1) {
            let dx1 = Double(smoothed[i].x - smoothed[i - 1].x)
            let dy1 = Double(smoothed[i].y - smoothed[i - 1].y)
            let dx2 = Double(smoothed[i + 1].x - smoothed[i].x)
            let dy2 = Double(smoothed[i + 1].y - smoothed[i].y)

            let len1 = hypot(dx1, dy1)
            let len2 = hypot(dx2, dy2)
            guard len1 > 1 && len2 > 1 else { continue }

            let dot = dx1 * dx2 + dy1 * dy2
            let cosAngle = dot / (len1 * len2)
            let angle = acos(min(max(cosAngle, -1.0), 1.0))

            if angle > angleThreshold {
                // Avoid adding turns too close together
                if let lastTurn = turnIndices.last {
                    let dist = hypot(smoothed[i].x - smoothed[lastTurn].x,
                                     smoothed[i].y - smoothed[lastTurn].y)
                    if dist < minTurnDist { continue }
                }
                turnIndices.append(i)
            }
        }

        turnIndices.append(smoothed.count - 1) // always include end

        // Map each turn point to its nearest key
        var intentional: [Character] = []
        for idx in turnIndices {
            let key: Character?
            if idx < swipeProximities.count, let primary = swipeProximities[idx].first {
                key = primary.character
            } else {
                key = nearestLetter(to: smoothed[idx])
            }

            if let k = key, intentional.last != k {
                intentional.append(k)
            }
        }

        // Must have at least 2 keys
        if intentional.count < 2 {
            let fallback = swipedLetters.reduce(into: [Character]()) { r, c in
                if r.last != c { r.append(c) }
            }
            if fallback.count >= 2 { return fallback }
            if let first = swipedLetters.first, let last = swipedLetters.last, first != last {
                return [first, last]
            }
        }

        return intentional
    }

    // MARK: - Template Matching (SHARK2 with proximity scoring)

    /// Match the swipe path to candidate words and return scored results.
    /// Returns tuples of (word, geometricScore) where higher score = better match (Bayesian).
    ///
    /// Uses proximity-based relaxation: the top-2 keys at the start and end
    /// of the swipe are considered as possible first/last letters, broadening
    /// candidate generation to handle near-miss touches.
    func matchSwipeWithScores() -> [(word: String, geometricScore: Double)] {
        guard swipedLetters.count >= 2 else { return [] }

        let intentional = extractIntentionalKeys()
        debugLog("[SwipeDebug] Intentional keys: \(String(intentional)) (\(intentional.count) keys)")

        guard intentional.count >= 2 else { return [] }

        let startProxies = swipeProximities.first ?? []
        let endProxies = swipeProximities.last ?? []

        // Include secondary start/end keys only if they have significant
        // probability relative to the primary key. This avoids flooding
        // candidates with words starting from distant keys (e.g., 'r' when
        // the user clearly started on 'e'). A secondary key at 20% of the
        // primary's probability is a genuine near-miss; at 5% it's noise.
        let firstLetters: [Character] = {
            guard let primary = startProxies.first else {
                return [intentional.first!]
            }
            let minRelativeProb = 0.40 // secondary must be >= 40% of primary
            var letters = [primary.character]
            for proxy in startProxies.dropFirst().prefix(2) {
                if proxy.probability >= primary.probability * minRelativeProb {
                    letters.append(proxy.character)
                }
            }
            return letters
        }()
        let lastLetters: [Character] = {
            guard let primary = endProxies.first else {
                return [intentional.last!]
            }
            let minRelativeProb = 0.40
            var letters = [primary.character]
            for proxy in endProxies.dropFirst().prefix(2) {
                if proxy.probability >= primary.probability * minRelativeProb {
                    letters.append(proxy.character)
                }
            }
            return letters
        }()

        // Gather candidates using intentional keys for prefix generation
        var candidates = gatherCandidates(firstLetters: firstLetters, lastLetters: lastLetters, intentionalKeys: intentional)

        // Retry with all top-3 end keys if 0 candidates found.
        // This handles cases where the swipe ends near a key that starts
        // no words in the target language (e.g., 'w' in Spanish).
        if candidates.isEmpty {
            let allEndKeys = endProxies.prefix(3).map(\.character)
            let allStartKeys = startProxies.prefix(3).map(\.character)
            let retryFirst = Array(Set(firstLetters + allStartKeys))
            let retryLast = Array(Set(lastLetters + allEndKeys))
            debugLog("[SwipeDebug] Retry with expanded keys: first=\(retryFirst), last=\(retryLast)")
            candidates = gatherCandidates(firstLetters: retryFirst, lastLetters: retryLast, intentionalKeys: intentional)
        }

        return scoreAndRank(candidates: candidates)
    }

    /// Score candidates using multiplicative (Bayesian) scoring inspired by SHARK2.
    ///
    /// Each channel produces a probability in (0, 1]:
    ///   - Shape:     exp(-k_shape * shapeDist)          — normalized shape distance
    ///   - Location:  exp(-k_loc * locDist)              — absolute location distance
    ///   - Proximity: pathProximityScore (already 0..1)  — Gaussian coverage of letters
    ///   - Order:     pathOrderScore (already 0..1)      — sequential order match
    ///   - Frequency: normalized unigram probability      — language model prior
    ///   - Length:    Gaussian penalty for length mismatch
    ///
    /// Final score = ∏ P_channel^exponent  (higher is better).
    /// Using multiplication means a word that fails *any* channel gets heavily
    /// penalized, while linear sums allow a strong channel to mask a weak one.
    private func scoreAndRank(candidates: Set<String>) -> [(word: String, geometricScore: Double)] {
        let userSampled = resample(swipePath, count: templatePointCount)
        guard userSampled.count == templatePointCount else { return [] }
        let userNormalized = normalize(userSampled)

        // User's raw arc length (total finger travel distance in points).
        let userArcLength = pathLength(swipePath)

        // Estimate intended word length from intentional key count.
        // Intentional keys undercount (some letters along straight segments
        // are missed), so the center estimate is intentionalCount + 2.
        // Allow ±3 around the center with sigma=2.0 for a moderate penalty.
        let intentional = extractIntentionalKeys()
        let intentionalCount = Double(intentional.count)
        let centerEstimate = intentionalCount + 2.0
        let estLengthLow = max(2.0, centerEstimate - 3.0)
        let estLengthHigh = centerEstimate + 1.0
        let lengthSigma = 1.5

        // Normalization factor for location distance: the keyboard diagonal.
        let locNorm: Double = {
            guard !keyRects.isEmpty else { return 1.0 }
            var minX = CGFloat.infinity, maxX = -CGFloat.infinity
            var minY = CGFloat.infinity, maxY = -CGFloat.infinity
            for rect in keyRects.values {
                minX = min(minX, rect.minX); maxX = max(maxX, rect.maxX)
                minY = min(minY, rect.minY); maxY = max(maxY, rect.maxY)
            }
            let diag = hypot(maxX - minX, maxY - minY)
            return max(diag, 1.0)
        }()

        // Distance-to-probability conversion constants.
        let kShape = 12.0
        let kLoc   = 10.0

        // Frequency normalization.
        // Lower temperature = more discriminative. Raised from 5.0 to let
        // frequency help filter bogus words that NSSpellChecker returns.
        let freqTemp = 3.0
        // Default frequency for spell-checker-known words without trie frequency
        // data. Must be worse than the bottom of the 50k frequency list (~-11.3)
        // so that words with real frequency data always rank above unknown words.
        // Completely unknown words (not even spell-checker valid) get -15.0.
        let defaultFreqLogProb = -12.0

        // Build spatial map once for distinct letter scoring.
        let spatialMap = buildSpatialMap()

        var scored: [(word: String, geometricScore: Double)] = []
        for word in candidates {
            let template = generateTemplate(for: word)
            guard template.count == templatePointCount else { continue }

            let templateNorm = normalize(template)

            // --- Channel probabilities (all in 0..1, higher = better) ---

            // Shape channel: exp(-k * shapeDist)
            let shapeDist = averageDistance(userNormalized, templateNorm)
            let pShape = exp(-kShape * shapeDist)

            // Location channel: exp(-k * locDist)
            let locDist = averageDistance(userSampled, template) / locNorm
            let pLocation = exp(-kLoc * locDist)

            // Arc-length ratio channel: compares user's actual finger travel
            // against the ideal template path length (straight lines between
            // key centers). Uses an ADAPTIVE ideal ratio that accounts for the
            // fact that user overshoot is additive, not multiplicative:
            //   expectedUserArc = templateArc + perLetterOvershoot * wordLen + constantOverhead
            // This means short words have higher expected ratios (~1.5-2.0×)
            // while long words have lower expected ratios (~1.1-1.3×).
            // A fixed idealRatio would systematically penalize long words.
            let templateKeyPath = word.compactMap { keyCenters[$0] }
            let templateArcLength = pathLength(templateKeyPath)
            let pArcLength: Double
            if templateArcLength > 0 {
                let ratio = userArcLength / templateArcLength
                // Adaptive ideal ratio: overshoot ≈ 15pt per letter + 50pt constant
                let expectedOvershoot = 15.0 * Double(word.count) + 50.0
                let adaptiveIdealRatio = (templateArcLength + expectedOvershoot) / templateArcLength
                let ratioSigma = 0.35
                let ratioDev = ratio - adaptiveIdealRatio
                pArcLength = exp(-0.5 * (ratioDev / ratioSigma) * (ratioDev / ratioSigma))
            } else {
                pArcLength = 0.01
            }

            // Proximity channel: already 0..1, but floor at small epsilon to avoid zero
            let pProximity = max(pathProximityScore(for: word), 0.01)

            // Distinct letter channel: rewards words that use more of the
            // high-probability spatial keys. "estante" (5 unique letters matching
            // the spatial map) scores higher than "estese" (3 unique letters).
            let pDistinct = distinctLetterMatchScore(for: word, spatialMap: spatialMap)

            // Frequency channel: normalized unigram probability.
            let rawLogProb = predictionEngine?.wordFrequency(word)
            let logProb: Double
            if let known = rawLogProb {
                logProb = known
            } else if predictionEngine?.isKnownWord(word) == true {
                logProb = defaultFreqLogProb
            } else {
                // Not even spell-checker valid — near-zero probability
                logProb = -15.0
            }
            let pFrequency = exp(logProb / freqTemp)

            // Length channel: Gaussian penalty for deviation from expected length
            let wordLen = Double(word.count)
            let lengthDev: Double
            if wordLen < estLengthLow {
                lengthDev = estLengthLow - wordLen
            } else if wordLen > estLengthHigh {
                lengthDev = wordLen - estLengthHigh
            } else {
                lengthDev = 0.0
            }
            let pLength = exp(-0.5 * (lengthDev / lengthSigma) * (lengthDev / lengthSigma))

            // Path order channel: fraction of consecutive letter pairs in
            // correct sequential order along the swipe path.
            let pOrder = max(pathOrderScore(for: word), 0.05)

            // --- Multiplicative combination with exponents ---
            // score = ∏ P_i^α_i  (higher is better)
            let score = pow(pShape, shapeExponent)
                      * pow(pLocation, locationExponent)
                      * pow(pArcLength, arcLengthExponent)
                      * pow(pProximity, proximityExponent)
                      * pow(pDistinct, distinctExponent)
                      * pow(pFrequency, frequencyExponent)
                      * pow(pLength, lengthExponent)
                      * pow(pOrder, orderExponent)

            scored.append((word: word, geometricScore: score))
        }

        // Sort descending — higher score = better match
        scored.sort { $0.geometricScore > $1.geometricScore }

        // Log candidate pool size and any notable words outside top 20
        debugLog("[SwipeDebug] Scored candidates: \(scored.count) total (Bayesian)")
        let debugRoots = ["prob", "hol", "human", "mund", "esta"]
        for (i, item) in scored.enumerated() where i >= 20 {
            if debugRoots.contains(where: { item.word.hasPrefix($0) }) {
                debugLog("[SwipeDebug]   Notable outside top 20: #\(i + 1) \"\(item.word)\" score=\(String(format: "%.6f", item.geometricScore))")
            }
        }

        return Array(scored.prefix(30))
    }

    /// Gather candidate words from multiple sources.
    ///
    /// Accepts arrays of possible first/last letters to handle near-miss
    /// touches at the swipe endpoints.
    ///
    /// Sources (in priority order):
    /// 1. PredictionEngine trie walk — fast DFS with first/last letter + length constraints
    /// 2. PredictionEngine completionsForSwipe — existing trie first/last lookup
    /// 3. Static fallback word list
    ///
    /// NSSpellChecker prefix queries have been removed entirely. The trie walk
    /// covers the same candidate space without the ~1ms-per-prefix latency.
    private func gatherCandidates(firstLetters: [Character], lastLetters: [Character], intentionalKeys: [Character]? = nil) -> Set<String> {
        var candidates = Set<String>()

        // Estimate word length from intentional key count.
        let intentional = intentionalKeys ?? swipedLetters.reduce(into: [Character]()) { result, char in
            if result.last != char { result.append(char) }
        }
        let intentionalCount = intentional.count
        // Allow very generous range: direction-change detection often undercounts
        // intended letters. For example, swiping "estante" (7 letters) may only
        // detect 4-5 intentional keys because some letters are along straight
        // segments. Use 2.5× upper bound and minLen = intentional - 3.
        let minLen = max(2, intentionalCount - 3)
        let maxLen = max(minLen + 4, Int(Double(intentionalCount) * 2.5))

        // Build spatial probability map: for each letter a-z, the maximum
        // Gaussian probability at any point along the swipe path.
        // This tells the trie walk which letters the user's finger came near.
        let spatialMap = buildSpatialMap()

        // 1. Spatially-pruned trie walk: DFS through the trie, pruning branches
        //    whose letter has no spatial proximity to the swipe path.
        //    Much faster and more accurate than blind DFS + cap.
        if let engine = predictionEngine {
            let trieCandidates = engine.swipeCandidatesFromTrie(
                firstLetters: firstLetters,
                lastLetters: lastLetters,
                minLength: minLen,
                maxLength: maxLen,
                spatialMap: spatialMap
            )
            candidates.formUnion(trieCandidates)
        }
        let afterTrieWalk = candidates.count

        // 2. Also query completionsForSwipe for each first/last combination.
        //    This uses the existing top-k completion cache and may find
        //    high-frequency words the spatial pruning filtered too aggressively.
        if let engine = predictionEngine {
            for firstLetter in firstLetters {
                for lastLetter in lastLetters {
                    let trieResults = engine.completionsForSwipe(
                        firstLetter: firstLetter,
                        lastLetter: lastLetter,
                        minLength: minLen,
                        maxLength: maxLen
                    )
                    candidates.formUnion(trieResults)
                }
            }
        }
        let afterTrieCompletions = candidates.count

        // 3. Swipe-time NSSpellChecker queries using intentional keys as prefixes.
        //    This catches words the trie missed (e.g. because the deep harvest
        //    hasn't completed yet, or the word requires a deep prefix chain).
        let checker = NSSpellChecker.shared
        let spellLang = predictionEngine?.spellCheckerLanguageCode ?? "es"
        let afterSpellCheck: Int
        do {
            let firstLetterSet = Set(firstLetters)
            let lastLetterSet = Set(lastLetters)
            var spellPrefixes = Set<String>()

            // Strategy A: Growing prefixes from intentional keys
            for len in 2...min(intentional.count, 7) {
                spellPrefixes.insert(String(intentional.prefix(len)))
            }
            // Also: first letter + each subsequent intentional key as 2-char prefix
            if let first = intentional.first {
                for i in 1..<intentional.count {
                    spellPrefixes.insert(String(first) + String(intentional[i]))
                }
            }

            // Strategy B: Use high-probability spatial map letters in swipe order.
            //   Filter swipedLetters to only those with spatial prob ≥ 0.5,
            //   deduplicate consecutive, and build growing prefixes.
            //   This often produces better prefixes than intentional keys alone
            //   because it follows the actual finger path more closely.
            let highProbLetters = Set(spatialMap.filter { $0.value >= 0.5 }.keys)
            var spatialFiltered = [Character]()
            for ch in swipedLetters {
                guard highProbLetters.contains(ch) else { continue }
                if spatialFiltered.last != ch { spatialFiltered.append(ch) }
            }
            for len in 2...min(spatialFiltered.count, 7) {
                spellPrefixes.insert(String(spatialFiltered.prefix(len)))
            }

            // Strategy C: Mini cascade from spatial prefix pairs.
            //   The trie may not have deep-harvest words yet (e.g. "estante").
            //   Build 2-letter prefixes from first letter + each high-prob key,
            //   then cascade: take the top completions' prefixes and query
            //   one level deeper. This finds words needing 4-5 letter prefixes
            //   (like "estan" → "estante") without the full deep harvest.
            if let firstLetter = firstLetters.first {
                let topSpatialKeys = spatialMap
                    .filter { $0.key != firstLetter && $0.value >= 0.5 }
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map(\.key)

                var cascadePrefixes = Set<String>()
                for secondKey in topSpatialKeys {
                    cascadePrefixes.insert(String(firstLetter) + String(secondKey))
                }

                // Cascade: query each prefix, collect longer prefixes from results.
                // Limited to 4 depths and 12 prefixes per depth to bound latency.
                // Prefixes are sorted by average spatial probability of their letters
                // so the most spatially relevant prefixes get queried first.
                for depth in 0..<4 {
                    var nextPrefixes = Set<String>()
                    let maxPrefixesPerDepth = 12
                    let sortedPrefixes = cascadePrefixes.sorted { a, b in
                        let aAvg = a.reduce(0.0) { $0 + (spatialMap[$1] ?? 0) } / Double(a.count)
                        let bAvg = b.reduce(0.0) { $0 + (spatialMap[$1] ?? 0) } / Double(b.count)
                        return aAvg > bAvg
                    }
                    for prefix in sortedPrefixes.prefix(maxPrefixesPerDepth) {
                        if let completions = checker.completions(
                            forPartialWordRange: NSRange(location: 0, length: prefix.utf16.count),
                            in: prefix,
                            language: spellLang,
                            inSpellDocumentWithTag: 0
                        ) {
                            for word in completions.prefix(depth == 0 ? 10 : 15) {
                                let lower = word.lowercased()
                                // Strip accents for matching (swipe keys have no accents)
                                let stripped = lower.folding(options: .diacriticInsensitive, locale: .current)
                                guard stripped.count >= minLen,
                                      stripped.count <= maxLen,
                                      let wFirst = stripped.first,
                                      let wLast = stripped.last,
                                      firstLetterSet.contains(wFirst),
                                      lastLetterSet.contains(wLast),
                                      stripped.allSatisfy({ $0.isLetter }) else {
                                    // Even if this word doesn't match, collect its prefix for deeper cascade
                                    if stripped.count >= prefix.count + 1 {
                                        let nextPfx = String(stripped.prefix(prefix.count + 1))
                                        if nextPfx.allSatisfy({ $0.isLetter }) {
                                            nextPrefixes.insert(nextPfx)
                                        }
                                    }
                                    continue
                                }
                                candidates.insert(stripped)
                                // Also collect deeper prefix for next cascade
                                if stripped.count >= prefix.count + 1 {
                                    let nextPfx = String(stripped.prefix(prefix.count + 1))
                                    nextPrefixes.insert(nextPfx)
                                }
                            }
                        }
                    }
                    // Filter next-level prefixes to only those whose letters are
                    // all spatially reachable (prevents exploring "exo..." when the
                    // path never went near 'x' and 'o').
                    // Prefixes are already accent-stripped so they match keyboard keys.
                    let reachable = Set(spatialMap.filter { $0.value >= 0.1 }.keys)
                    cascadePrefixes = nextPrefixes.filter { pfx in
                        pfx.allSatisfy { ch in
                            reachable.contains(ch)
                        }
                    }
                }
            }

            for prefix in spellPrefixes {
                if let completions = checker.completions(
                    forPartialWordRange: NSRange(location: 0, length: prefix.utf16.count),
                    in: prefix,
                    language: spellLang,
                    inSpellDocumentWithTag: 0
                ) {
                    for word in completions.prefix(30) {
                        let lower = word.lowercased()
                        guard lower.count >= minLen,
                              lower.count <= maxLen,
                              let wFirst = lower.first,
                              let wLast = lower.last,
                              firstLetterSet.contains(wFirst),
                              lastLetterSet.contains(wLast),
                              lower.allSatisfy({ $0.isLetter }) else { continue }
                        candidates.insert(lower)
                    }
                }
            }
            afterSpellCheck = candidates.count
        }

        // 4. Static fallback word list — only used for English.
        //    The built-in commonWords list is English-only and would pollute
        //    Spanish/other language results with words like "example", "range",
        //    "remember" that have no business competing with native candidates.
        if language.hasPrefix("en") {
            let firstLetterSetFinal = Set(firstLetters)
            let lastLetterSetFinal = Set(lastLetters)
            for word in wordList {
                guard word.count >= minLen,
                      word.count <= maxLen,
                      let firstChar = word.first,
                      let lastChar = word.last,
                      firstLetterSetFinal.contains(firstChar),
                      lastLetterSetFinal.contains(lastChar) else { continue }
                candidates.insert(word)
            }
        }

        let reachableCount = spatialMap.filter { $0.value >= 0.005 }.count
        let prunedLetters = spatialMap.filter { $0.value < 0.005 }.sorted(by: { $0.value > $1.value })
        let prunedStr = prunedLetters.map { "\($0.key)(\(String(format: "%.4f", $0.value)))" }.joined(separator: " ")
        debugLog("[SwipeDebug] Candidates: \(afterTrieWalk) trieWalk + \(afterTrieCompletions - afterTrieWalk) trieCompletions + \(afterSpellCheck - afterTrieCompletions) spellCheck + \(candidates.count - afterSpellCheck) static = \(candidates.count) total")
        debugLog("[SwipeDebug] First letters: \(firstLetters), Last letters: \(lastLetters), Length range: \(minLen)-\(maxLen), Reachable keys: \(reachableCount)/26")
        if !prunedLetters.isEmpty {
            debugLog("[SwipeDebug] Pruned letters: \(prunedStr)")
        }
        // Log spatial map for letters in "estante" for debugging
        let targetLetters: [Character] = ["e", "s", "t", "a", "n"]
        let targetProbs = targetLetters.map { "\($0)=\(String(format: "%.4f", spatialMap[$0] ?? 0.0))" }.joined(separator: " ")
        debugLog("[SwipeDebug] Spatial[estante]: \(targetProbs)")

        return candidates
    }

    /// Build a spatial probability map: for each letter key a-z, compute the maximum
    /// Gaussian probability it had at any point along the swipe path.
    /// Uses velocity weighting — slow points (targeting a key) boost probability.
    /// This powers the spatially-pruned trie walk — letters the path never came near
    /// get probability ~0 and their trie branches are pruned.
    private func buildSpatialMap() -> [Character: Double] {
        let sigma = keySigma
        let velocityWeights = computeVelocityWeights()
        var map: [Character: Double] = [:]
        for (char, center) in keyCenters {
            var maxProb = 0.0
            for (i, point) in swipePath.enumerated() {
                let prob = gaussianProbability(point: point, keyCenter: center, sigma: sigma)
                let weight = i < velocityWeights.count ? velocityWeights[i] : 1.0
                let weighted = min(prob * weight, 1.0)
                if weighted > maxProb { maxProb = weighted }
            }
            map[char] = maxProb
        }
        return map
    }

    // MARK: - Path Processing

    private let templatePointCount = 100

    // Bayesian scoring exponents: each channel is raised to this power
    // before multiplication. Higher exponent = more influence on final rank.
    //
    // SHARK2 research shows shape + location are the primary channels.
    // Location uses absolute coordinates and naturally encodes word length
    // (longer words span more of the keyboard). Arc-length is a gentle
    // secondary signal — its adaptive ratio prevents gross length mismatches
    // but doesn't need to be the primary discriminator.
    private let shapeExponent: Double = 1.0    // Normalized shape — gross discrimination
    private let locationExponent: Double = 2.0 // Absolute location — THE primary discriminator for similar shapes and word lengths
    private let arcLengthExponent: Double = 1.5 // Arc-length ratio — strong filter for wrong-length words (adaptive, not fixed)
    private let proximityExponent: Double = 1.0 // Quality filter — reward path coverage of each letter
    private let distinctExponent: Double = 1.0  // Distinct letter match — discriminates words with same shape but different letters
    private let frequencyExponent: Double = 0.5 // LM prior — reduced to avoid accent-inflated words dominating geometric evidence
    private let lengthExponent: Double = 1.5   // Length penalty — penalizes words outside the adaptive estimate range
    private let orderExponent: Double = 1.5    // Path order — letters should appear sequentially along swipe

    /// Resample a path into `count` equidistant points.
    private func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count >= 2 else { return points }

        let totalLen = pathLength(points)
        guard totalLen > 0 else { return points }

        let interval = totalLen / Double(count - 1)
        var resampled: [CGPoint] = [points[0]]
        var accumulated: Double = 0
        var i = 1

        while i < points.count && resampled.count < count {
            let d = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            if accumulated + d >= interval {
                let ratio = (interval - accumulated) / d
                let newX = points[i - 1].x + CGFloat(ratio) * (points[i].x - points[i - 1].x)
                let newY = points[i - 1].y + CGFloat(ratio) * (points[i].y - points[i - 1].y)
                resampled.append(CGPoint(x: newX, y: newY))
                accumulated = 0
                // Don't advance i — check again from the new point
            } else {
                accumulated += d
                i += 1
            }
        }

        // Pad with last point if needed
        while resampled.count < count {
            resampled.append(points.last!)
        }

        return resampled
    }

    /// Normalize points: scale bounding box to unit size, center at origin.
    private func normalize(_ points: [CGPoint]) -> [CGPoint] {
        guard !points.isEmpty else { return points }

        var minX = CGFloat.infinity, maxX = -CGFloat.infinity
        var minY = CGFloat.infinity, maxY = -CGFloat.infinity

        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        let w = maxX - minX
        let h = maxY - minY
        let scale = max(w, h)
        guard scale > 0 else { return points }

        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2

        return points.map { p in
            CGPoint(x: (p.x - cx) / scale, y: (p.y - cy) / scale)
        }
    }

    /// Total arc length of a polyline.
    private func pathLength(_ points: [CGPoint]) -> Double {
        var length: Double = 0
        for i in 1..<points.count {
            length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return length
    }

    /// Average Euclidean distance between corresponding points.
    private func averageDistance(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return .infinity }
        var total: Double = 0
        for i in 0..<a.count {
            total += hypot(a[i].x - b[i].x, a[i].y - b[i].y)
        }
        return total / Double(a.count)
    }

    /// Generate the ideal template path for a word (connecting key centers).
    private func generateTemplate(for word: String) -> [CGPoint] {
        let centers = word.compactMap { keyCenters[$0] }
        guard centers.count == word.count else { return [] }
        return resample(centers, count: templatePointCount)
    }

    /// Find the nearest letter key to a point using Gaussian proximity scoring.
    private func nearestLetter(to point: CGPoint) -> Character? {
        nearestKeys(to: point, topN: 1).first?.character
    }

    // MARK: - Debug Tracing

    /// Path to the swipe debug log file. Written after each swipe so it can
    /// be read by external tools (including Claude Code) without needing
    /// access to the Xcode console.
    /// Uses Application Support/Tekla/ inside the app's sandbox container.
    static let debugLogURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let teklaDir = appSupport.appendingPathComponent("Tekla", isDirectory: true)
        try? FileManager.default.createDirectory(at: teklaDir, withIntermediateDirectories: true)
        return teklaDir.appendingPathComponent("swipe_debug.log")
    }()

    /// Append a line to both the debug log file and the console.
    private func debugLog(_ line: String) {
        print(line)
        debugLines.append(line)
    }

    /// Buffer for the current debug trace, flushed to disk at the end.
    private var debugLines: [String] = []

    /// Clear the debug log file. Called once at init (i.e. each app launch).
    static func clearDebugLog() {
        try? "".write(to: debugLogURL, atomically: true, encoding: .utf8)
    }

    /// Flush buffered debug lines to the log file (appending to previous swipes).
    private func flushDebugLog() {
        let content = debugLines.joined(separator: "\n") + "\n"
        debugLines = []
        if let handle = try? FileHandle(forWritingTo: Self.debugLogURL) {
            handle.seekToEndOfFile()
            if let data = content.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            // File doesn't exist yet — create it
            try? content.write(to: Self.debugLogURL, atomically: true, encoding: .utf8)
        }
    }

    /// Logs a detailed scoring breakdown for the last swipe to both console
    /// and a file at `SwipeEngine.debugLogURL`.
    private func logSwipeDebugTrace(results: [(word: String, geometricScore: Double)]) {
        // debugLines may already contain candidate-gathering info from gatherCandidates.

        guard !results.isEmpty else {
            debugLog("[SwipeDebug] No results — swipedLetters: \(swipedLetters)")
            flushDebugLog()
            return
        }

        let unique = swipedLetters.reduce(into: [Character]()) { r, c in
            if r.last != c { r.append(c) }
        }

        // Reconstruct first/last letter candidates from proximity data
        let startProxies = swipeProximities.first ?? []
        let endProxies = swipeProximities.last ?? []
        let firstCandidates = startProxies.prefix(3).map { "\($0.character)(p=\(String(format: "%.3f", $0.probability)))" }
        let lastCandidates = endProxies.prefix(3).map { "\($0.character)(p=\(String(format: "%.3f", $0.probability)))" }

        let userArcLength = pathLength(swipePath)
        let intentional = extractIntentionalKeys()
        let intentionalCount = Double(intentional.count)
        let centerEstimate2 = intentionalCount + 2.0
        let estLengthLow = max(2.0, centerEstimate2 - 3.0)
        let estLengthHigh = centerEstimate2 + 1.0

        // Keyboard diagonal for location distance normalization
        let locNorm: Double = {
            guard !keyRects.isEmpty else { return 1.0 }
            var minX = CGFloat.infinity, maxX = -CGFloat.infinity
            var minY = CGFloat.infinity, maxY = -CGFloat.infinity
            for rect in keyRects.values {
                minX = min(minX, rect.minX); maxX = max(maxX, rect.maxX)
                minY = min(minY, rect.minY); maxY = max(maxY, rect.maxY)
            }
            return max(Double(hypot(maxX - minX, maxY - minY)), 1.0)
        }()

        debugLog("[SwipeDebug] ══════════════════════════════════════")
        debugLog("[SwipeDebug] Raw swiped:     \(String(swipedLetters)) (\(unique.count) unique)")
        debugLog("[SwipeDebug] Intentional:    \(String(intentional)) (\(intentional.count) keys)")
        debugLog("[SwipeDebug] Path points:    \(swipePath.count)")
        debugLog("[SwipeDebug] Arc length:     \(String(format: "%.1f", userArcLength))pt")
        debugLog("[SwipeDebug] Est word len:   \(String(format: "%.1f", centerEstimate2)) letters (adaptive model)")
        debugLog("[SwipeDebug] Avg key width:  \(String(format: "%.1f", averageKeyWidth))pt")
        debugLog("[SwipeDebug] Kbd diagonal:   \(String(format: "%.1f", locNorm))pt")
        debugLog("[SwipeDebug] Est. word len:  \(String(format: "%.1f", estLengthLow))-\(String(format: "%.1f", estLengthHigh)) chars")
        debugLog("[SwipeDebug] First keys:     \(firstCandidates.joined(separator: ", "))")
        debugLog("[SwipeDebug] Last keys:      \(lastCandidates.joined(separator: ", "))")
        debugLog("[SwipeDebug] ──────────────────────────────────────")

        // Recompute per-candidate Bayesian scoring details for the top results
        let userSampled = resample(swipePath, count: templatePointCount)
        let userNormalized = normalize(userSampled)

        let kShape = 12.0
        let kLoc = 10.0
        let freqTemp = 3.0
        let defaultFreqLogProb = -12.0
        let lengthSigma = 1.5
        let spatialMap = buildSpatialMap()

        for (rank, result) in results.enumerated() {
            let word = result.word
            let template = generateTemplate(for: word)
            guard template.count == templatePointCount else {
                debugLog("[SwipeDebug]  #\(rank + 1) \"\(word)\" — missing template (keys not found)")
                continue
            }
            let templateNorm = normalize(template)
            let shapeDist = averageDistance(userNormalized, templateNorm)
            let locDist = averageDistance(userSampled, template) / locNorm

            let pShape = exp(-kShape * shapeDist)
            let pLoc = exp(-kLoc * locDist)

            // Arc-length ratio (adaptive)
            let templateKeyPath = word.compactMap { keyCenters[$0] }
            let templateArcLength = pathLength(templateKeyPath)
            let pArc: Double
            if templateArcLength > 0 {
                let ratio = userArcLength / templateArcLength
                let expectedOvershoot2 = 15.0 * Double(word.count) + 50.0
                let adaptiveIdeal2 = (templateArcLength + expectedOvershoot2) / templateArcLength
                let ratioDev = ratio - adaptiveIdeal2
                pArc = exp(-0.5 * (ratioDev / 0.35) * (ratioDev / 0.35))
            } else {
                pArc = 0.01
            }

            let pProx = max(pathProximityScore(for: word), 0.01)
            let pDist = distinctLetterMatchScore(for: word, spatialMap: spatialMap)

            let rawLogProb2 = predictionEngine?.wordFrequency(word)
            let logProb2: Double
            if let known = rawLogProb2 {
                logProb2 = known
            } else if predictionEngine?.isKnownWord(word) == true {
                logProb2 = defaultFreqLogProb
            } else {
                logProb2 = -15.0
            }
            let pFreq = exp(logProb2 / freqTemp)

            let wordLen = Double(word.count)
            let lengthDev: Double
            if wordLen < estLengthLow {
                lengthDev = estLengthLow - wordLen
            } else if wordLen > estLengthHigh {
                lengthDev = wordLen - estLengthHigh
            } else {
                lengthDev = 0.0
            }
            let pLen = exp(-0.5 * (lengthDev / lengthSigma) * (lengthDev / lengthSigma))
            let pOrd = max(pathOrderScore(for: word), 0.05)
            let total = pow(pShape, shapeExponent) * pow(pLoc, locationExponent)
                      * pow(pArc, arcLengthExponent)
                      * pow(pProx, proximityExponent)
                      * pow(pDist, distinctExponent)
                      * pow(pFreq, frequencyExponent) * pow(pLen, lengthExponent)
                      * pow(pOrd, orderExponent)

            debugLog("[SwipeDebug]  #\(rank + 1) \"\(word)\" (len=\(word.count)) "
                + "pSh=\(String(format: "%.4f", pShape)) "
                + "pLo=\(String(format: "%.4f", pLoc)) "
                + "pAr=\(String(format: "%.4f", pArc)) "
                + "pPx=\(String(format: "%.4f", pProx)) "
                + "pDl=\(String(format: "%.4f", pDist)) "
                + "pFr=\(String(format: "%.4f", pFreq)) "
                + "pLn=\(String(format: "%.4f", pLen)) "
                + "pOr=\(String(format: "%.4f", pOrd)) "
                + "SCORE=\(String(format: "%.6f", total))")
        }
        debugLog("[SwipeDebug] ══════════════════════════════════════")
        flushDebugLog()
    }

    // MARK: - Gaussian Proximity Scoring

    /// Cached average key width, invalidated when `keyRects` changes.
    private var _cachedKeyWidth: CGFloat?

    /// Average width of registered letter keys, used to compute Gaussian sigma.
    private var averageKeyWidth: CGFloat {
        if let cached = _cachedKeyWidth { return cached }
        guard !keyRects.isEmpty else { return 38 }
        let avg = keyRects.values.reduce(CGFloat(0)) { $0 + $1.width } / CGFloat(keyRects.count)
        _cachedKeyWidth = avg
        return avg
    }

    /// Default sigma for Gaussian key proximity: half the average key width.
    /// A point on the key edge (~1σ away) gets ~0.61 probability.
    /// One full key-width away (~2σ) gets ~0.14.
    private var keySigma: CGFloat { averageKeyWidth * 0.5 }

    /// Gaussian probability: P(point | key) = exp(-d² / (2σ²)).
    private func gaussianProbability(point: CGPoint, keyCenter: CGPoint, sigma: CGFloat) -> Double {
        let dx = Double(point.x - keyCenter.x)
        let dy = Double(point.y - keyCenter.y)
        let distSq = dx * dx + dy * dy
        return exp(-distSq / (2.0 * Double(sigma * sigma)))
    }

    /// Get the top-N nearest keys to a point, ranked by Gaussian probability.
    /// Only returns keys above `minProbability` (defaults to 0.01).
    func nearestKeys(to point: CGPoint, topN: Int = 3, minProbability: Double = 0.01) -> [KeyProximity] {
        let sigma = keySigma
        var results: [KeyProximity] = []
        for (char, center) in keyCenters {
            let dist = hypot(point.x - center.x, point.y - center.y)
            let prob = gaussianProbability(point: point, keyCenter: center, sigma: sigma)
            guard prob >= minProbability else { continue }
            results.append(KeyProximity(character: char, probability: prob, distance: dist))
        }
        results.sort { $0.probability > $1.probability }
        return Array(results.prefix(topN))
    }

    /// Compute how well the swipe path covered each letter in a candidate word.
    ///
    /// Uses a velocity-weighted, coverage-based approach:
    /// - For each unique letter in the word, compute the max Gaussian probability
    ///   at any point along the swipe path, weighted by inverse velocity.
    ///   Points where the finger slows down (near target keys) count more.
    /// - The score blends two signals:
    ///   (a) Coverage ratio: what fraction of distinct letters had probability >= threshold
    ///   (b) Proximity quality: average of sqrt(maxProb) for covered letters
    ///
    /// Returns 0..1 where 1 means every letter was directly on the path.
    private func pathProximityScore(for word: String) -> Double {
        guard !swipePath.isEmpty, word.count >= 2 else { return 0 }

        let sigma = keySigma
        let coverageThreshold = 0.15 // ~1.4σ away — generous for near-miss detection

        // Pre-compute velocity weights for each swipe point.
        // Slow points (near target letters) get weight up to 2.0;
        // fast points (transit between letters) get weight down to 0.5.
        let velocityWeights = computeVelocityWeights()

        // Deduplicate letters: "probando" has two 'o's — only score each letter once.
        var seen = Set<Character>()
        var letterProbs: [Double] = []
        for char in word {
            guard !seen.contains(char), let center = keyCenters[char] else { continue }
            seen.insert(char)
            // Find the maximum velocity-weighted probability
            var maxProb = 0.0
            for (i, point) in swipePath.enumerated() {
                let prob = gaussianProbability(point: point, keyCenter: center, sigma: sigma)
                let weight = i < velocityWeights.count ? velocityWeights[i] : 1.0
                let weighted = min(prob * weight, 1.0)
                if weighted > maxProb { maxProb = weighted }
            }
            letterProbs.append(maxProb)
        }

        guard !letterProbs.isEmpty else { return 0 }

        let coveredCount = letterProbs.filter { $0 >= coverageThreshold }.count
        let coverageRatio = Double(coveredCount) / Double(letterProbs.count)

        // Quality: average of sqrt(prob) for all letters (covered or not)
        let qualitySum = letterProbs.reduce(0.0) { $0 + sqrt($1) }
        let quality = qualitySum / Double(letterProbs.count)

        // Blend: 60% coverage + 40% quality
        return 0.6 * coverageRatio + 0.4 * quality
    }

    /// Compute per-point velocity weights for proximity scoring.
    /// Points where the finger moves slowly get higher weight (the user is
    /// targeting a key), fast-moving points get lower weight (transit).
    ///
    /// Uses a normalized inverse velocity: weight = medianVelocity / velocity,
    /// clamped to [0.5, 2.0]. This means:
    /// - At median speed: weight = 1.0
    /// - At half speed (targeting): weight = 2.0
    /// - At double speed (transit): weight = 0.5
    private func computeVelocityWeights() -> [Double] {
        guard swipePath.count >= 3 else {
            return Array(repeating: 1.0, count: swipePath.count)
        }

        // Compute instantaneous speeds between consecutive points
        var speeds: [Double] = [0.0] // first point has no velocity
        for i in 1..<swipePath.count {
            let d = hypot(swipePath[i].x - swipePath[i - 1].x,
                         swipePath[i].y - swipePath[i - 1].y)
            speeds.append(Double(d))
        }

        // Smooth speeds with a 3-point window to reduce noise
        var smoothed = speeds
        for i in 1..<(speeds.count - 1) {
            smoothed[i] = (speeds[i - 1] + speeds[i] + speeds[i + 1]) / 3.0
        }

        // Find median speed for normalization
        let sorted = smoothed.filter { $0 > 0 }.sorted()
        let median = sorted.isEmpty ? 1.0 : sorted[sorted.count / 2]
        guard median > 0 else {
            return Array(repeating: 1.0, count: swipePath.count)
        }

        // Weight = median/speed, clamped to [0.5, 2.0]
        return smoothed.map { speed in
            guard speed > 0 else { return 2.0 } // stationary = targeting
            return min(max(median / speed, 0.5), 2.0)
        }
    }

    /// Measure how well the word's distinct letters match the strongest keys
    /// on the swipe path using bidirectional scoring:
    ///
    /// 1. **Coverage** (word→path): What fraction of the top spatial keys does
    ///    the word's letters cover? "estante" (5 unique: e,s,t,a,n) covers
    ///    more of the path's high-probability keys than "estense" (4 unique: e,s,t,n).
    ///
    /// 2. **Penalty** (path→word): For each high-probability key the path
    ///    crossed that the word does NOT contain, apply a penalty proportional
    ///    to how strongly the path hit that key. This penalizes "estense" for
    ///    not using 'a' when the user clearly swiped through 'a'.
    ///
    /// Final score = coverage × (1 - penalty), where penalty is scaled by
    /// the unused probability mass relative to the total.
    private func distinctLetterMatchScore(for word: String, spatialMap: [Character: Double]) -> Double {
        let wordLetters = Set(word)

        // Sort all keys by spatial probability, descending
        let sorted = spatialMap.sorted { $0.value > $1.value }
        guard !sorted.isEmpty else { return 0.5 }

        // Use a fixed top-K of 8 keys: covers the primary path letters plus
        // a few neighbors. This is wide enough to capture all relevant keys
        // but narrow enough to avoid dilution from distant keys.
        let k = 8
        let topK = sorted.prefix(k)

        // Split into covered (word uses this key) and uncovered (word doesn't)
        var coveredProb = 0.0
        var totalProb = 0.0
        for (char, prob) in topK {
            totalProb += prob
            if wordLetters.contains(char) {
                coveredProb += prob
            }
        }

        guard totalProb > 0 else { return 0.5 }

        // Coverage: fraction of top-K probability the word covers
        let coverage = coveredProb / totalProb

        // Penalty: for each top-K key with strong probability (>0.30) that the
        // word does NOT contain, apply a penalty. Threshold 0.30 means only keys
        // the path clearly targeted are considered — nearby-but-untargeted keys
        // (like 'r' next to 'e' with prob ~0.2) are ignored.
        var significantUncoveredProb = 0.0
        for (char, prob) in topK {
            if !wordLetters.contains(char) && prob > 0.30 {
                significantUncoveredProb += prob
            }
        }
        let uncoveredPenalty = significantUncoveredProb / totalProb

        // Precision: penalize words whose unique letters aren't supported by
        // the spatial map. For each unique letter in the word, look up its
        // spatial probability. Letters with low/zero probability are "extras"
        // the path never targeted. This prevents longer words from gaining
        // an advantage by simply having more letters that happen to coincide
        // with nearby keys.
        let spatialThreshold = 0.25  // minimum spatial prob to count as "supported"
        var supportedCount = 0
        for ch in wordLetters {
            if (spatialMap[ch] ?? 0.0) >= spatialThreshold {
                supportedCount += 1
            }
        }
        let precision = wordLetters.isEmpty ? 0.5 : Double(supportedCount) / Double(wordLetters.count)

        // Blend: geometric mean of coverage, precision, and uncovered penalty
        let score = coverage * precision * (1.0 - uncoveredPenalty)
        return max(score, 0.05)
    }

    /// Measure how well the word's letter order matches the swipe path direction.
    ///
    /// For each letter in the word, finds the path index where its Gaussian
    /// probability is highest. Then counts what fraction of consecutive letter
    /// pairs have their best-match indices in non-decreasing order.
    ///
    /// Returns 0..1 where 1.0 means every letter appears along the path in
    /// perfect sequential order, and 0.0 means the order is completely reversed.
    private func pathOrderScore(for word: String) -> Double {
        guard swipePath.count >= 2, word.count >= 2 else { return 0.5 }

        let sigma = keySigma
        // Find the path index with maximum probability for each letter
        var bestIndices: [Int] = []
        for char in word {
            guard let center = keyCenters[char] else { continue }
            var bestIdx = 0
            var bestProb = -1.0
            for (i, point) in swipePath.enumerated() {
                let prob = gaussianProbability(point: point, keyCenter: center, sigma: sigma)
                if prob > bestProb {
                    bestProb = prob
                    bestIdx = i
                }
            }
            bestIndices.append(bestIdx)
        }

        guard bestIndices.count >= 2 else { return 0.5 }

        // Count how many consecutive pairs are in order
        var inOrder = 0
        for i in 1..<bestIndices.count {
            if bestIndices[i] >= bestIndices[i - 1] {
                inOrder += 1
            }
        }
        return Double(inOrder) / Double(bestIndices.count - 1)
    }

    // MARK: - Dictionary

    /// Basic word list — loaded once at init.
    private let wordList: [String] = SwipeEngine.loadWordList()

    static func loadWordList() -> [String] {
        // Try loading from bundled dictionary file
        if let url = Bundle.main.url(forResource: "dictionary", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && $0.count >= 2 }
        }
        // Fallback: built-in common English words
        return Self.commonWords
    }

    /// Top ~500 most common English words as fallback.
    static let commonWords: [String] = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "it",
        "for", "not", "on", "with", "he", "as", "you", "do", "at", "this",
        "but", "his", "by", "from", "they", "we", "say", "her", "she", "or",
        "an", "will", "my", "one", "all", "would", "there", "their", "what",
        "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
        "when", "make", "can", "like", "time", "no", "just", "him", "know",
        "take", "people", "into", "year", "your", "good", "some", "could",
        "them", "see", "other", "than", "then", "now", "look", "only", "come",
        "its", "over", "think", "also", "back", "after", "use", "two", "how",
        "our", "work", "first", "well", "way", "even", "new", "want", "because",
        "any", "these", "give", "day", "most", "us", "great", "between", "need",
        "large", "often", "important", "always", "home", "each", "small", "before",
        "right", "big", "still", "high", "another", "last", "long", "same",
        "around", "left", "three", "world", "under", "while", "place", "keep",
        "never", "through", "much", "point", "help", "here", "more", "every",
        "where", "made", "after", "many", "should", "very", "hand", "been",
        "call", "find", "down", "life", "been", "part", "start", "might",
        "little", "head", "found", "school", "number", "again", "play", "turn",
        "real", "live", "house", "night", "open", "try", "both", "line",
        "tell", "old", "end", "run", "move", "own", "read", "face", "change",
        "close", "few", "put", "ask", "late", "hard", "thing", "without",
        "different", "away", "water", "young", "begin", "name", "example",
        "while", "next", "mean", "show", "still", "child", "follow", "learn",
        "stop", "write", "enough", "kind", "city", "group", "family", "country",
        "leave", "feel", "true", "power", "side", "against", "together",
        "love", "door", "word", "eye", "hold", "may", "than", "light",
        "able", "something", "mother", "state", "off", "set", "during", "bring",
        "everything", "possible", "nothing", "type", "within", "sure", "done",
        "really", "problem", "happen", "best", "quite", "full", "along",
        "system", "since", "until", "hear", "money", "idea", "already", "body",
        "table", "story", "less", "must", "far", "second", "later", "book",
        "company", "better", "why", "such", "clear", "believe", "today",
        "early", "game", "food", "answer", "room", "person", "question",
        "thank", "week", "moment", "though", "order", "level", "office",
        "become", "above", "girl", "class", "mind", "human", "reason",
        "result", "area", "several", "morning", "service", "study",
        "program", "market", "music", "white", "community", "build",
        "interest", "month", "social", "report", "maybe", "student",
        "near", "once", "care", "expect", "effect", "seem", "war",
        "often", "wait", "plan", "figure", "hour", "land", "short",
        "record", "issue", "paper", "information", "provide", "include",
        "whether", "value", "let", "local", "staff", "team", "party",
        "during", "meeting", "remember", "simple", "given", "however",
        "perhaps", "public", "computer", "actually", "position",
        "development", "experience", "government", "support",
        "health", "business", "course", "special", "list", "important",
        "data", "view", "control", "history", "picture", "size", "model",
        "available", "test", "general", "able", "half", "process", "return",
        "rate", "least", "total", "sense", "fact", "stand", "rest",
        "policy", "chance", "across", "share", "produce", "offer", "age",
        "window", "minute", "street", "strong", "case", "space", "ever",
        "event", "action", "price", "range", "drive", "form", "deal",
        "past", "bank", "center", "detail", "check", "single", "personal",
        "toward", "member", "accept", "apply", "bring", "break", "create",
        "decide", "easy", "enjoy", "consider", "likely", "force",
        "material", "situation", "continue", "building", "understand",
        "appear", "training", "similar", "concern", "increase", "spend",
        "current", "suggest", "allow", "major", "finally", "natural",
        "raise", "common", "itself", "across", "future", "account",
        "standard", "meeting", "discuss", "opportunity", "respond",
        "ability", "approach", "practice", "project", "design",
        "performance", "attention", "evidence", "function",
        "indicate", "message", "manager", "quality",
    ]
}

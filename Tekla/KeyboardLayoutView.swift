import SwiftUI

// MARK: - Full Desktop Keyboard Layout

/// Renders a full Mac desktop keyboard with swipe-to-type support on letter keys.
/// Uses a single unified gesture on the main section that handles both taps
/// and swipe-to-type, avoiding child/parent gesture conflicts.
struct KeyboardLayoutView: View {
    let isShiftActive: Bool
    let isCapsLockActive: Bool
    let activeModifiers: Set<KeyAction>
    let showFunctionRow: Bool
    let showNavigationCluster: Bool
    let visualFeedbackEnabled: Bool
    let swipeEngine: SwipeEngine
    let swipeTypingEnabled: Bool
    /// The current keyboard language (ISO 639-1 code). Drives layout overrides.
    let language: String
    var swipeTrailLength: Int = 20
    var onKeyDown: ((KeyModel) -> Void)?
    let onKeyTap: (KeyModel) -> Void
    let onSwipeComplete: ([(word: String, geometricScore: Double)]) -> Void
    /// Called during a swipe when the swiped letters change, for live prediction updates.
    var onSwipeLettersChanged: (([Character]) -> Void)?

    private let keyboardCoordinateSpace = "keyboardLayout"

    /// Main rows customized for the current language.
    private var currentRows: [[KeyModel]] {
        KeyboardLayout.mainRows(for: language)
    }

    /// Tracks which key is currently pressed (for visual feedback).
    @State private var pressedKeyID: UUID?
    /// Whether the current gesture has become a swipe (moved > threshold).
    @State private var isDragging = false
    /// Base key unit width derived from available space.
    @State private var baseKeyWidth: CGFloat = 38
    /// Scale factor for non-width dimensions (heights, fonts, spacing).
    @State private var scaleFactor: CGFloat = 1.0

    private var keySpacing: CGFloat { 3 * scaleFactor }
    private var sectionGap: CGFloat { 14 * scaleFactor }

    /// Compute base key width from available space so keys fill width without overflowing height.
    private func computeLayout(availableWidth: CGFloat, availableHeight: CGFloat) {
        let hPad: CGFloat = 32 // 16pt each side
        let usableWidth = availableWidth - hPad

        // The widest row determines the unit width.
        let rows = currentRows
        let widestRow = rows.max(by: { rowWidth($0) < rowWidth($1) }) ?? rows[0]
        let totalUnits = rowWidth(widestRow)
        let numKeys = CGFloat(widestRow.count)

        // Solve for baseKey from width:
        // totalUnits * baseKey + (numKeys-1) * keySpacing = effectiveWidth
        // keySpacing = 3 * (baseKey / 38)
        let spacingFactor = (numKeys - 1) * 3.0 / 38.0

        // Reserve space for nav cluster proportionally
        let navReserve: CGFloat
        if showNavigationCluster {
            // Nav cluster: 3 keys wide + spacing + section gap, all scale proportionally
            // At base=38: 3*38 + 2*3 + 14 = 134
            let navFactor: CGFloat = (3.0 + 2.0 * 3.0 / 38.0 + 14.0 / 38.0)
            navReserve = navFactor
        } else {
            navReserve = 0
        }

        let widthBase = usableWidth / (totalUnits + spacingFactor + navReserve)

        // Solve for baseKey from height.
        // All dimensions scale with (base/38), so express total height as:
        //   totalHeight = (base/38) * heightUnits + fixedOverhead
        // Then: base = (availableHeight - fixedOverhead) * 38 / heightUnits
        let numMainRows: CGFloat = CGFloat(rows.count)
        // Units that scale with base/38:
        //   top padding: 4, bottom padding: 4, shadow clearance: 2
        //   main rows: numMainRows * 36 (key heights)
        //   main row gaps: (numMainRows - 1) * 3 (keySpacing)
        //   VStack spacing between func row and main: 4
        var heightUnits: CGFloat = 10.0 // top(4) + bottom(4) + shadow(2)
            + numMainRows * 36.0
            + (numMainRows - 1) * 3.0
            + 4.0 // VStack internal spacing
        if showFunctionRow {
            heightUnits += 28.0 // function key height
            + 4.0 // VStack spacing above divider
        }
        // Fixed overhead that doesn't scale: divider (~1pt)
        let fixedOverhead: CGFloat = showFunctionRow ? 1.0 : 0.0
        let heightBase = (availableHeight - fixedOverhead) / heightUnits * 38.0

        // Use the smaller of the two to avoid clipping
        let newBase = min(widthBase, heightBase)
        baseKeyWidth = max(20, newBase)
        scaleFactor = max(0.6, baseKeyWidth / 38.0)
    }

    private func rowWidth(_ row: [KeyModel]) -> CGFloat {
        row.reduce(0) { $0 + $1.widthMultiplier }
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 4 * scaleFactor) {
                if showFunctionRow {
                    functionRowSection
                    Divider()
                }
                mainAndNavSection
            }
            .padding(.top, 4 * scaleFactor)
            .padding(.horizontal, 16)
            .padding(.bottom, 4 * scaleFactor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .coordinateSpace(name: keyboardCoordinateSpace)
            .overlay {
                SwipeTrailView(
                    swipePath: swipeEngine.swipePath,
                    isSwiping: swipeEngine.isSwiping,
                    maxTrailPoints: swipeTrailLength
                )
            }
            .onAppear { computeLayout(availableWidth: geo.size.width, availableHeight: geo.size.height) }
            .onChange(of: geo.size) { computeLayout(availableWidth: geo.size.width, availableHeight: geo.size.height) }
        }
    }

    // MARK: - Function Row

    @ViewBuilder
    private var functionRowSection: some View {
        HStack(spacing: keySpacing) {
            standaloneKeyButton(KeyboardLayout.functionRow[0])
            Spacer().frame(width: sectionGap)
            ForEach(KeyboardLayout.functionRow[1...4]) { key in
                standaloneKeyButton(key)
            }
            Spacer().frame(width: sectionGap / 2)
            ForEach(KeyboardLayout.functionRow[5...8]) { key in
                standaloneKeyButton(key)
            }
            Spacer().frame(width: sectionGap / 2)
            ForEach(KeyboardLayout.functionRow[9...12]) { key in
                standaloneKeyButton(key)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Main + Nav + Arrows

    @ViewBuilder
    private var mainAndNavSection: some View {
        HStack(alignment: .top, spacing: sectionGap) {
            mainSection
            if showNavigationCluster {
                VStack(spacing: 6) {
                    navCluster
                    Spacer().frame(height: 2)
                    arrowCluster
                }
            }
        }
    }

    /// The widest row's total unit width, used to equalize all rows.
    private var maxRowUnits: CGFloat {
        currentRows.map { rowWidth($0) }.max() ?? 0
    }

    /// The maximum number of keys in any row, used to compute spacing.
    private var maxRowKeyCount: Int {
        currentRows.map(\.count).max() ?? 0
    }

    @ViewBuilder
    private var mainSection: some View {
        let maxUnits = maxRowUnits
        let maxCount = maxRowKeyCount
        // Total pixel width of the widest row (keys + inter-key spacing)
        let maxRowPixelWidth = maxUnits * baseKeyWidth + CGFloat(maxCount - 1) * keySpacing

        VStack(spacing: keySpacing) {
            ForEach(Array(currentRows.enumerated()), id: \.offset) { _, row in
                let naturalWidth = rowWidth(row) * baseKeyWidth + CGFloat(row.count - 1) * keySpacing
                let extraWidth = maxRowPixelWidth - naturalWidth

                HStack(spacing: keySpacing) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { idx, key in
                        if idx == row.count - 1 {
                            // Last key stretches to fill the row
                            keyButton(key, extraWidth: extraWidth)
                        } else {
                            keyButton(key)
                        }
                    }
                }
            }
        }
        .gesture(unifiedGesture)
    }

    // MARK: - Unified Gesture

    /// A single DragGesture on the main section handles both taps and swipes.
    /// - Short drags (< 20pt total movement): treated as a key tap.
    /// - Long drags (≥ 20pt): treated as swipe-to-type.
    private var unifiedGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(keyboardCoordinateSpace))
            .onChanged { value in
                let distance = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )

                if !isDragging && distance < 20 {
                    // Still in "tap" territory — show press feedback on the key under the start point
                    if pressedKeyID == nil {
                        if let key = hitTestKey(at: value.startLocation) {
                            pressedKeyID = key.id
                            onKeyDown?(key)
                        }
                    }
                } else if swipeTypingEnabled {
                    // Transitioned to swipe mode
                    if !isDragging {
                        isDragging = true
                        // Cancel the pressed key visual — this is a swipe, not a tap
                        pressedKeyID = nil
                        swipeEngine.beginSwipe(at: value.startLocation)
                    }
                    let lettersBefore = swipeEngine.swipedLetters.count
                    swipeEngine.continueSwipe(at: value.location)
                    // Notify when a new letter is added for live prediction updates
                    if swipeEngine.swipedLetters.count > lettersBefore {
                        onSwipeLettersChanged?(swipeEngine.swipedLetters)
                    }
                }
            }
            .onEnded { value in
                if isDragging {
                    // End of swipe
                    if swipeEngine.isSwiping {
                        let scoredResults = swipeEngine.endSwipe()
                        if !scoredResults.isEmpty {
                            onSwipeComplete(scoredResults)
                        }
                    }
                } else {
                    // End of tap — fire the key action
                    if let key = hitTestKey(at: value.startLocation) {
                        onKeyTap(key)
                    }
                }
                pressedKeyID = nil
                isDragging = false
            }
    }

    /// Find the key model whose registered rect contains the given point.
    private func hitTestKey(at point: CGPoint) -> KeyModel? {
        let rows = currentRows
        // Check letter key rects from the swipe engine
        for (char, rect) in swipeEngine.keyRects {
            if rect.contains(point) {
                // Find the matching KeyModel
                for row in rows {
                    if let key = row.first(where: {
                        if case .character(let c) = $0.action {
                            return Character(c.lowercased()) == char
                        }
                        return false
                    }) {
                        return key
                    }
                }
            }
        }
        // Check all non-letter keys via their registered rects in allKeyRects
        for (id, rect) in allKeyRects {
            if rect.contains(point) {
                for row in rows {
                    if let key = row.first(where: { $0.id == id }) {
                        return key
                    }
                }
            }
        }
        return nil
    }

    /// Stores rects for non-letter keys (space, shift, modifiers, etc.)
    @State private var allKeyRects: [UUID: CGRect] = [:]

    @ViewBuilder
    private var navCluster: some View {
        VStack(spacing: keySpacing) {
            HStack(spacing: keySpacing) {
                ForEach(KeyboardLayout.navTopRow) { key in
                    standaloneKeyButton(key)
                }
            }
            HStack(spacing: keySpacing) {
                Color.clear.frame(width: 38 * scaleFactor, height: 36 * scaleFactor)
                ForEach(KeyboardLayout.navBottomRow) { key in
                    standaloneKeyButton(key)
                }
            }
        }
    }

    @ViewBuilder
    private var arrowCluster: some View {
        VStack(spacing: keySpacing) {
            HStack(spacing: keySpacing) {
                Color.clear.frame(width: 38 * scaleFactor, height: 36 * scaleFactor)
                ForEach(KeyboardLayout.arrowTopRow) { key in
                    standaloneKeyButton(key)
                }
                Color.clear.frame(width: 38 * scaleFactor, height: 36 * scaleFactor)
            }
            HStack(spacing: keySpacing) {
                ForEach(KeyboardLayout.arrowBottomRow) { key in
                    standaloneKeyButton(key)
                }
            }
        }
    }

    // MARK: - Key Button Factory

    /// Key button used inside the main section — no gesture attached.
    /// All interaction is handled by the parent's unified gesture.
    /// `extraWidth` is added to the last key in each row to equalize row widths.
    @ViewBuilder
    private func keyButton(_ key: KeyModel, extraWidth: CGFloat = 0) -> some View {
        keyButtonView(key, extraWidth: extraWidth)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            registerKeyGeometry(key: key, frame: geo.frame(in: .named(keyboardCoordinateSpace)))
                        }
                        .onChange(of: geo.size) {
                            registerKeyGeometry(key: key, frame: geo.frame(in: .named(keyboardCoordinateSpace)))
                        }
                }
            )
    }

    /// Key button used outside the main section (function row, nav, arrows).
    /// Has its own tap gesture since it's not covered by the unified gesture.
    @ViewBuilder
    private func standaloneKeyButton(_ key: KeyModel) -> some View {
        keyButtonView(key)
            .onTapGesture {
                onKeyDown?(key)
                onKeyTap(key)
            }
    }

    @ViewBuilder
    private func keyButtonView(_ key: KeyModel, extraWidth: CGFloat = 0) -> some View {
        KeyButtonView(
            key: key,
            isShiftActive: isShiftActive || isCapsLockActive,
            isModifierActive: activeModifiers.contains(key.action),
            isPressed: pressedKeyID == key.id,
            visualFeedbackEnabled: visualFeedbackEnabled,
            baseKeyWidth: baseKeyWidth,
            scaleFactor: scaleFactor,
            extraWidth: extraWidth
        )
    }

    /// Report key geometry to the swipe engine and local hit-test map.
    private func registerKeyGeometry(key: KeyModel, frame: CGRect) {
        // Register all keys for hit testing
        allKeyRects[key.id] = frame

        // Register letter keys for swipe matching
        guard case .character(let char) = key.action else { return }
        let lc = Character(char.lowercased())
        guard lc.isLetter else { return }
        swipeEngine.keyCenters[lc] = CGPoint(x: frame.midX, y: frame.midY)
        swipeEngine.keyRects[lc] = frame
    }
}

// MARK: - Single Key Button

/// Pure display component — no gestures. All interaction is handled by
/// the parent's unified gesture via hit-testing.
struct KeyButtonView: View {
    let key: KeyModel
    let isShiftActive: Bool
    let isModifierActive: Bool
    let isPressed: Bool
    let visualFeedbackEnabled: Bool
    var baseKeyWidth: CGFloat = 38
    var scaleFactor: CGFloat = 1.0
    /// Extra width added to stretch this key so all rows have equal total width.
    var extraWidth: CGFloat = 0

    private var displayLabel: String {
        switch key.action {
        case .character(let char):
            if isShiftActive, let shifted = key.shiftedLabel {
                return shifted
            }
            // Show lowercase for letter keys when shift is not active
            if char.isLetter && !isShiftActive {
                return key.label.lowercased()
            }
            return key.label
        default:
            return key.label
        }
    }

    private var keyHeight: CGFloat {
        switch key.action {
        case .functionKey, .escape:
            return 28 * scaleFactor
        default:
            return 36 * scaleFactor
        }
    }

    private var keyWidth: CGFloat {
        baseKeyWidth * key.widthMultiplier + extraWidth
    }

    private var fontSize: Font {
        let scale = scaleFactor
        switch key.action {
        case .functionKey, .escape, .fn, .globe:
            return .system(size: 10 * scale)
        case .character:
            return .system(size: 15 * scale)
        default:
            return .system(size: 12 * scale)
        }
    }

    private var isModifier: Bool {
        switch key.action {
        case .shift, .capsLock, .command, .option, .control, .fn, .globe:
            return true
        default:
            return false
        }
    }

    private var isSpecialKey: Bool {
        switch key.action {
        case .character: return false
        default: return true
        }
    }

    var body: some View {
        keyContent
            .frame(width: keyWidth, height: keyHeight)
            .background(keyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .scaleEffect(isPressed && visualFeedbackEnabled ? 0.93 : 1.0)
            .brightness(isPressed && visualFeedbackEnabled ? 0.1 : 0)
            .animation(.easeOut(duration: 0.06), value: isPressed)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var keyContent: some View {
        if let secondary = key.secondaryLabel, !isShiftActive {
            VStack(spacing: 0) {
                Text(secondary)
                    .font(.system(size: 9 * scaleFactor))
                    .foregroundStyle(.secondary)
                Text(displayLabel)
                    .font(fontSize)
            }
        } else {
            Text(displayLabel)
                .font(fontSize)
                .fontWeight(isModifier ? .medium : .regular)
        }
    }

    @ViewBuilder
    private var keyBackground: some View {
        if isModifierActive {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor.opacity(0.35))
        } else if isSpecialKey {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.08))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var accessibilityDescription: String {
        switch key.action {
        case .character(let char):
            return isShiftActive ? String(localized: "Capital \(char.uppercased())") : String(char)
        case .space: return String(localized: "Space")
        case .backspace: return String(localized: "Delete")
        case .forwardDelete: return String(localized: "Forward Delete")
        case .returnKey: return String(localized: "Return")
        case .tab: return String(localized: "Tab")
        case .escape: return String(localized: "Escape")
        case .shift: return isModifierActive ? String(localized: "Shift on") : String(localized: "Shift off")
        case .capsLock: return isModifierActive ? String(localized: "Caps Lock on") : String(localized: "Caps Lock off")
        case .command: return String(localized: "Command")
        case .option: return String(localized: "Option")
        case .control: return String(localized: "Control")
        case .fn: return String(localized: "Function")
        case .globe: return String(localized: "Globe")
        case .arrowLeft: return String(localized: "Left arrow")
        case .arrowRight: return String(localized: "Right arrow")
        case .arrowUp: return String(localized: "Up arrow")
        case .arrowDown: return String(localized: "Down arrow")
        case .home: return String(localized: "Home")
        case .end: return String(localized: "End")
        case .pageUp: return String(localized: "Page Up")
        case .pageDown: return String(localized: "Page Down")
        case .functionKey(let n): return "F\(n)"
        }
    }
}

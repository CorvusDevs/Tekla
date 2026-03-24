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

    private let keySpacing: CGFloat = 3
    private let sectionGap: CGFloat = 14
    private let keyboardCoordinateSpace = "keyboardLayout"

    /// Main rows customized for the current language.
    private var currentRows: [[KeyModel]] {
        KeyboardLayout.mainRows(for: language)
    }

    /// Tracks which key is currently pressed (for visual feedback).
    @State private var pressedKeyID: UUID?
    /// Whether the current gesture has become a swipe (moved > threshold).
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 6) {
            if showFunctionRow {
                functionRowSection
                Divider().padding(.horizontal, 4)
            }
            mainAndNavSection
        }
        .padding(.top, 8)
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .coordinateSpace(name: keyboardCoordinateSpace)
        .overlay {
            SwipeTrailView(
                swipePath: swipeEngine.swipePath,
                isSwiping: swipeEngine.isSwiping,
                maxTrailPoints: swipeTrailLength
            )
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

    @ViewBuilder
    private var mainSection: some View {
        VStack(spacing: keySpacing) {
            ForEach(Array(currentRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: keySpacing) {
                    ForEach(row) { key in
                        keyButton(key)
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
                Color.clear.frame(width: 38, height: 36)
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
                Color.clear.frame(width: 38, height: 36)
                ForEach(KeyboardLayout.arrowTopRow) { key in
                    standaloneKeyButton(key)
                }
                Color.clear.frame(width: 38, height: 36)
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
    @ViewBuilder
    private func keyButton(_ key: KeyModel) -> some View {
        keyButtonView(key)
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
    private func keyButtonView(_ key: KeyModel) -> some View {
        KeyButtonView(
            key: key,
            isShiftActive: isShiftActive || isCapsLockActive,
            isModifierActive: activeModifiers.contains(key.action),
            isPressed: pressedKeyID == key.id,
            visualFeedbackEnabled: visualFeedbackEnabled
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

    private var displayLabel: String {
        switch key.action {
        case .character:
            if isShiftActive, let shifted = key.shiftedLabel {
                return shifted
            }
            return key.label
        default:
            return key.label
        }
    }

    private var keyHeight: CGFloat {
        switch key.action {
        case .functionKey, .escape:
            return 28
        default:
            return 36
        }
    }

    private var keyWidth: CGFloat {
        let base: CGFloat = 38
        return base * key.widthMultiplier
    }

    private var fontSize: Font {
        switch key.action {
        case .functionKey, .escape, .fn, .globe:
            return .caption2
        case .character:
            return .body
        default:
            return .caption
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
                    .font(.system(size: 9))
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

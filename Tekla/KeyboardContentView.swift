import SwiftUI

/// The root view hosted inside the floating keyboard panel.
struct KeyboardContentView: View {
    @State private var viewModel = KeyboardViewModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.permissions.isAccessibilityGranted {
                permissionBanner
            }

            topBar

            keyboardArea
        }
        .padding(.bottom, 10)
        .frame(
            minWidth: KeyboardLayout.minimumWidth(
                for: viewModel.settings.selectedLanguage,
                showNavigationCluster: viewModel.settings.showNavigationCluster
            ),
            minHeight: 200
        )
        .background(.ultraThinMaterial)
        .onChange(of: viewModel.settings.selectedLanguage) {
            expandWindowIfNeeded()
        }
        .onChange(of: viewModel.settings.showNavigationCluster) {
            expandWindowIfNeeded()
        }
        .opacity(viewModel.settings.keyboardOpacity)
        .onAppear {
            if !viewModel.permissions.isAccessibilityGranted {
                viewModel.permissions.requestAccessibility()
            }
        }
        .onChange(of: showSettings) { _, show in
            if show {
                SettingsWindowController.shared.show(
                    settings: viewModel.settings,
                    predictionEngine: viewModel.predictionEngine
                ) {
                    showSettings = false
                }
            } else {
                SettingsWindowController.shared.close()
            }
        }
    }

    // MARK: - Top Bar (Predictions + Controls)

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 0) {
            if viewModel.settings.predictionsEnabled {
                PredictionBar(
                    predictions: viewModel.predictions,
                    primaryIndex: viewModel.primaryPredictionIndex
                ) { word in
                    viewModel.insertPrediction(word)
                }
            } else {
                Spacer()
            }

            // Controls cluster — sits to the right of predictions
            HStack(spacing: 6) {
                // Current language picker
                Menu {
                    ForEach(LanguageManager.supportedLanguages) { lang in
                        Button {
                            viewModel.settings.selectedLanguage = lang.id
                        } label: {
                            HStack {
                                Text("\(lang.nativeName) (\(lang.name))")
                                if lang.id == viewModel.settings.selectedLanguage {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text(LanguageManager.language(for: viewModel.settings.selectedLanguage).id.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel(String(localized: "Language"))

                // Swipe mode indicator
                if viewModel.settings.swipeTypingEnabled {
                    Image(systemName: "scribble.variable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Swipe typing enabled"))
                }

                // Settings button
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Settings"))
            }
            .padding(.trailing, 12)
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
        Divider()
    }

    // MARK: - Keyboard Area with Swipe

    @ViewBuilder
    private var keyboardArea: some View {
        KeyboardLayoutView(
            isShiftActive: viewModel.isShiftActive,
            isCapsLockActive: viewModel.isCapsLockActive,
            activeModifiers: viewModel.activeModifiers,
            showFunctionRow: viewModel.settings.showFunctionRow,
            showNavigationCluster: viewModel.settings.showNavigationCluster,
            visualFeedbackEnabled: viewModel.settings.visualFeedbackEnabled,
            swipeEngine: viewModel.swipeEngine,
            swipeTypingEnabled: viewModel.settings.swipeTypingEnabled,
            language: viewModel.settings.selectedLanguage,
            swipeTrailLength: Int(viewModel.settings.swipeTrailLength),
            onKeyDown: { key in
                viewModel.handleKeyDown(key)
            },
            onKeyTap: { key in
                viewModel.handleKeyTap(key)
            },
            onSwipeComplete: { scoredCandidates in
                viewModel.handleSwipeResult(scoredCandidates)
            },
            onSwipeLettersChanged: { letters in
                viewModel.handleSwipeLettersChanged(letters)
            }
        )
    }

    // MARK: - Permission Banner

    @ViewBuilder
    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(String(localized: "Accessibility permission required. If already enabled, toggle Tekla off and on in System Settings → Privacy & Security → Accessibility."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(String(localized: "Open Settings")) {
                viewModel.permissions.requestAccessibility()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Window Resize

    /// Expand the hosting window when switching to a wider language layout.
    private func expandWindowIfNeeded() {
        guard let window = NSApp.windows.first(where: { $0 is KeyboardPanel }) else { return }
        let needed = KeyboardLayout.minimumWidth(
            for: viewModel.settings.selectedLanguage,
            showNavigationCluster: viewModel.settings.showNavigationCluster
        )
        window.minSize.width = needed
        if window.frame.width < needed {
            var frame = window.frame
            let delta = needed - frame.width
            frame.size.width = needed
            // Keep centered horizontally
            frame.origin.x -= delta / 2
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

#Preview {
    KeyboardContentView()
        .frame(width: 920, height: 340)
}

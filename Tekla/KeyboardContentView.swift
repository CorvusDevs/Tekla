import SwiftUI

/// The root view hosted inside the floating keyboard panel.
struct KeyboardContentView: View {
    @State private var viewModel = KeyboardViewModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            toolbarBar

            if !viewModel.permissions.isAccessibilityGranted {
                permissionBanner
            }

            if viewModel.settings.predictionsEnabled {
                PredictionBar(
                    predictions: viewModel.predictions,
                    primaryIndex: viewModel.primaryPredictionIndex
                ) { word in
                    viewModel.insertPrediction(word)
                }
                Divider()
            }

            keyboardArea
        }
        .frame(minWidth: 700, minHeight: 200)
        .background(.ultraThinMaterial)
        .opacity(viewModel.settings.keyboardOpacity)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: viewModel.settings, predictionEngine: viewModel.predictionEngine)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarBar: some View {
        HStack(spacing: 6) {
            Spacer()

            // Current language indicator
            let lang = LanguageManager.language(for: viewModel.settings.selectedLanguage)
            Text(lang.id.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08), in: Capsule())

            // Swipe mode indicator
            if viewModel.settings.swipeTypingEnabled {
                Image(systemName: "scribble.variable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Swipe typing enabled"))
            }

            // Settings button
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Settings"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
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

            Text(String(localized: "Accessibility permission required. Click to open System Settings and enable Tekla."))
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
}

#Preview {
    KeyboardContentView()
        .frame(width: 920, height: 340)
}

import SwiftUI

/// Settings panel for Tekla preferences.
struct SettingsView: View {
    @Bindable var settings: SettingsManager
    var predictionEngine: PredictionEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text(String(localized: "Settings"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close Settings"))
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            TabView {
                generalTab
                    .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }

                feedbackTab
                    .tabItem { Label(String(localized: "Feedback"), systemImage: "speaker.wave.2") }

                languageTab
                    .tabItem { Label(String(localized: "Language"), systemImage: "globe") }

                appearanceTab
                    .tabItem { Label(String(localized: "Appearance"), systemImage: "paintbrush") }
            }
        }
        .frame(width: 420, height: 420)
    }

    // MARK: - General

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section(String(localized: "Typing")) {
                Toggle(String(localized: "Swipe typing"), isOn: $settings.swipeTypingEnabled)
                Toggle(String(localized: "Word predictions"), isOn: $settings.predictionsEnabled)
                Toggle(String(localized: "Autocorrect"), isOn: $settings.autocorrectEnabled)
            }

            if settings.predictionsEnabled {
                predictionSettings
            }

            Section(String(localized: "Layout")) {
                Toggle(String(localized: "Show function row (Esc, F1–F12)"), isOn: $settings.showFunctionRow)
                Toggle(String(localized: "Show navigation cluster (arrows, Page Up/Down)"), isOn: $settings.showNavigationCluster)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackTab: some View {
        Form {
            Section(String(localized: "Visual")) {
                Toggle(String(localized: "Key press animation"), isOn: $settings.visualFeedbackEnabled)
            }

            Section(String(localized: "Haptic")) {
                Toggle(String(localized: "Haptic feedback"), isOn: $settings.hapticFeedbackEnabled)
                Text(String(localized: "Requires Force Touch trackpad or Magic Trackpad 2."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Swipe Trail")) {
                HStack {
                    Text(String(localized: "Short"))
                        .font(.caption)
                    Slider(value: $settings.swipeTrailLength, in: 10...60, step: 5)
                    Text(String(localized: "Long"))
                        .font(.caption)
                }
            }

            Section(String(localized: "Sound")) {
                Toggle(String(localized: "Key press sound"), isOn: $settings.soundFeedbackEnabled)
                if settings.soundFeedbackEnabled {
                    HStack {
                        Image(systemName: "speaker")
                        Slider(value: $settings.soundVolume, in: 0...1, step: 0.05)
                        Image(systemName: "speaker.wave.3")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Language

    @ViewBuilder
    private var languageTab: some View {
        Form {
            Section(String(localized: "Keyboard Language")) {
                Picker(String(localized: "Language"), selection: $settings.selectedLanguage) {
                    ForEach(LanguageManager.supportedLanguages) { lang in
                        Text("\(lang.nativeName) (\(lang.name))")
                            .tag(lang.id)
                    }
                }

                Text(String(localized: "Changes the prediction language and keyboard layout where applicable (e.g., AZERTY for French, QWERTZ for German)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Detection")) {
                let detected = LanguageManager.language(for: LanguageManager.detectedSystemLanguage())
                LabeledContent(String(localized: "System language"), value: detected.nativeName)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Predictions

    @ViewBuilder
    private var predictionSettings: some View {
        Section(String(localized: "Predictions")) {
            HStack {
                Text(String(localized: "Number of suggestions"))
                Spacer()
                Picker("", selection: $settings.predictionCount) {
                    Text("3").tag(3)
                    Text("5").tag(5)
                    Text("7").tag(7)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            Toggle(String(localized: "Learn from typing"), isOn: $settings.learnFromTyping)

            Text(String(localized: "Tekla learns which words you use most often to improve predictions. All data stays on your device."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                let count = predictionEngine.learnedWordCount
                Text(String(localized: "\(count) words learned"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Clear Learned Words"), role: .destructive) {
                    showClearConfirmation = true
                }
                .controlSize(.small)
            }
            .alert(String(localized: "Clear Learned Words?"), isPresented: $showClearConfirmation) {
                Button(String(localized: "Cancel"), role: .cancel) { }
                Button(String(localized: "Clear"), role: .destructive) {
                    predictionEngine.clearUserDictionary()
                }
            } message: {
                Text(String(localized: "This will remove all words Tekla has learned from your typing. Predictions will reset to defaults."))
            }
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceTab: some View {
        Form {
            Section(String(localized: "Opacity")) {
                HStack {
                    Text(String(localized: "Transparent"))
                        .font(.caption)
                    Slider(value: $settings.keyboardOpacity, in: 0.3...1.0, step: 0.05)
                    Text(String(localized: "Opaque"))
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

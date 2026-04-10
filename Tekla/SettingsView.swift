import SwiftUI
import Sparkle

/// Settings panel for Tekla preferences.
struct SettingsView: View {
    @Bindable var settings: SettingsManager
    var predictionEngine: PredictionEngine
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false
    @State private var selectedTab: SettingsTab = .general

    private enum SettingsTab: String, CaseIterable {
        case general, feedback, language, appearance, about

        var label: String {
            switch self {
            case .general: String(localized: "General")
            case .feedback: String(localized: "Feedback")
            case .language: String(localized: "Language")
            case .appearance: String(localized: "Appearance")
            case .about: String(localized: "About")
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .feedback: "speaker.wave.2"
            case .language: "globe"
            case .appearance: "paintbrush"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text(String(localized: "Settings"))
                .font(.headline)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Category bar
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11))
                            Text(tab.label)
                                .font(.subheadline)
                                .fixedSize()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTab == tab
                                      ? Color.accentColor.opacity(0.15)
                                      : Color.primary.opacity(0.04))
                        )
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            // Content
            Group {
                switch selectedTab {
                case .general: generalTab
                case .feedback: feedbackTab
                case .language: languageTab
                case .appearance: appearanceTab
                case .about: aboutTab
                }
            }
        }
        .frame(width: 480, height: 380)
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
    }

    // MARK: - About

    @ViewBuilder
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            // App icon and version
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            Text("Tekla")
                .font(.title2.bold())

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("v\(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Check for Updates
            Button(String(localized: "Check for Updates…")) {
                if let delegate = NSApp.delegate as? AppDelegate {
                    delegate.updaterController.checkForUpdates(nil)
                }
            }
            .controlSize(.large)

            Spacer()

            // Corvus Devs branding
            VStack(spacing: 6) {
                Text(String(localized: "Made by"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Button {
                    if let url = URL(string: "https://corvusdevs.github.io") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Corvus Devs")
                            .font(.headline)
                    }
                }
                .buttonStyle(.link)
            }

            Spacer()
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

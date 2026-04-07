import SwiftUI

/// A window that prompts the user to enter their unlock code after purchase.
struct ActivationView: View {

    var settings: SettingsManager
    var onUnlocked: () -> Void

    @State private var code = ""
    @State private var showError = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .accentColor.opacity(0.3), radius: 20, y: 8)
                    .padding(.bottom, 20)
            }

            Text("Tekla")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 4)

            Text(String(localized: "Enter your unlock code to get started."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)

            // Code field
            TextField(String(localized: "Unlock Code"), text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 280)
                .offset(x: shakeOffset)
                .onSubmit { attemptActivation() }
                .padding(.bottom, 8)

            if showError {
                Text(String(localized: "Invalid code. Please try again."))
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }

            Button(action: attemptActivation) {
                Text(String(localized: "Unlock"))
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 280, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 16)

            Link(String(localized: "Purchase Tekla"),
                 destination: URL(string: "https://corvusdevs.github.io/Tekla/")!)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 400, height: 380)
        .background(.background)
    }

    private func attemptActivation() {
        if settings.activate(code: code) {
            onUnlocked()
        } else {
            showError = true
            withAnimation(.default) {
                shakeOffset = -8
            }
            withAnimation(.default.delay(0.1)) {
                shakeOffset = 8
            }
            withAnimation(.default.delay(0.2)) {
                shakeOffset = 0
            }
        }
    }
}

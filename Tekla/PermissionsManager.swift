import ApplicationServices
import AppKit

/// Manages Accessibility permission required for CGEvent posting.
///
/// In DEBUG builds, set `debugBypassPermission` to `true` to skip the
/// Accessibility check. This lets you test the full UI (predictions,
/// swipe trail, feedback) without re-granting permission after every build.
/// CGEvent posting will still fail silently, but everything else works.
@Observable
final class PermissionsManager {

    #if DEBUG
    /// When `true`, the UI behaves as if Accessibility is granted.
    /// CGEvent calls will still fail, but predictions, swipe, and
    /// feedback all work normally for UI testing.
    static let debugBypassPermission = true
    #endif

    private(set) var isAccessibilityGranted: Bool = false

    init() {
        #if DEBUG
        if Self.debugBypassPermission {
            isAccessibilityGranted = true
            return
        }
        #endif
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Check current Accessibility permission status.
    func refresh() {
        #if DEBUG
        if Self.debugBypassPermission {
            isAccessibilityGranted = true
            return
        }
        #endif
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Prompt the system dialog and open System Settings to the Accessibility pane.
    /// The system prompt may not appear for accessory-mode apps, so we always
    /// open Settings as well to ensure the user can find and enable the app.
    func requestAccessibility() {
        // Try the system prompt first
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)

        // Also open System Settings directly — the prompt often doesn't show
        // for non-activating panel apps running in accessory mode
        openAccessibilitySettings()

        // Poll for the user to grant permission
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(2))
                let granted = AXIsProcessTrusted()
                if granted {
                    isAccessibilityGranted = true
                    return
                }
            }
        }
    }

    /// Open System Settings directly to the Accessibility pane.
    func openAccessibilitySettings() {
        // macOS 13+ deep link
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

import ApplicationServices
import AppKit

/// Manages Accessibility permission required for CGEvent posting.
@Observable
final class PermissionsManager {

    private(set) var isAccessibilityGranted: Bool = false

    /// Background polling task that checks permission status periodically.
    private var pollingTask: Task<Void, Never>?

    init() {
        isAccessibilityGranted = AXIsProcessTrusted()
        startPollingIfNeeded()
    }

    /// Check current Accessibility permission status.
    func refresh() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }

    /// Prompt the system dialog and open System Settings to the Accessibility pane.
    /// No-op if permission is already granted.
    func requestAccessibility() {
        // Re-check live — the cached value may be stale at this point
        if AXIsProcessTrusted() {
            isAccessibilityGranted = true
            return
        }

        // Trigger the system prompt
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)

        // Also open System Settings directly — the prompt often doesn't show
        // for non-activating panel apps running in accessory mode
        openAccessibilitySettings()
    }

    /// Open System Settings directly to the Accessibility pane.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Private

    /// Poll every 2 seconds until permission is granted, then stop.
    private func startPollingIfNeeded() {
        guard !isAccessibilityGranted else { return }
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                let granted = AXIsProcessTrusted()
                if granted {
                    self.isAccessibilityGranted = true
                    self.pollingTask = nil
                    return
                }
            }
        }
    }
}

import AppKit
import SwiftUI

/// Manages a standalone, movable settings panel separate from the keyboard panel.
/// Uses NSPanel with `.nonactivatingPanel` so it doesn't steal focus from the target app.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private var panel: NSPanel?
    private var onClose: (() -> Void)?

    private override init() {
        super.init()
    }

    func show(settings: SettingsManager, predictionEngine: PredictionEngine, onClose: @escaping () -> Void) {
        self.onClose = onClose

        if let existing = panel, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(settings: settings, predictionEngine: predictionEngine, onDismiss: { [weak self] in
            self?.close()
        })

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 540, height: 400)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - 270,
            y: screenFrame.midY - 200
        )

        let win = NSPanel(
            contentRect: NSRect(origin: origin, size: NSSize(width: 540, height: 400)),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Settings")
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.level = .floating + 1
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.delegate = self

        win.makeKeyAndOrderFront(nil)
        self.panel = win
    }

    func close() {
        guard let panel else { return }
        panel.close()  // triggers windowWillClose which handles cleanup
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil   // release the closure to avoid retain cycles
        panel = nil
        callback?()
    }
}

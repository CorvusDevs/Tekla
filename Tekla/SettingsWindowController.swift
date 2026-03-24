import AppKit
import SwiftUI

/// Manages a standalone, movable settings window separate from the keyboard panel.
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var onClose: (() -> Void)?

    private init() {}

    func show(settings: SettingsManager, predictionEngine: PredictionEngine, onClose: @escaping () -> Void) {
        self.onClose = onClose

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(settings: settings, predictionEngine: predictionEngine, onDismiss: { [weak self] in
            self?.close()
        })

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 380)

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - 240,
            y: screenFrame.midY - 190
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: 480, height: 380)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Settings")
        win.contentView = hostingView
        win.isReleasedWhenClosed = false
        win.level = .floating + 1
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.delegate = WindowCloseDelegate.shared
        WindowCloseDelegate.shared.onClose = { [weak self] in
            self?.onClose?()
            self?.window = nil
        }

        win.makeKeyAndOrderFront(nil)
        self.window = win
    }

    func close() {
        window?.close()
        onClose?()
        window = nil
    }
}

/// Detects when the user closes the settings window via the title bar close button.
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowCloseDelegate()
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

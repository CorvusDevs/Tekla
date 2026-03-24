import AppKit
import SwiftUI

/// Sets up the floating keyboard panel on launch and provides
/// a menu bar status item for show/hide and quit.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var keyboardPanel: KeyboardPanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hostingView = NSHostingView(rootView: KeyboardContentView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 920, height: 340)

        keyboardPanel = KeyboardPanel(contentView: hostingView)
        keyboardPanel?.orderFront(nil)

        setupStatusItem()

        // Accessory mode — no prominent Dock icon
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running when the panel is closed — user can re-show from menu bar
    }

    // MARK: - Menu Bar Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: String(localized: "Tekla Keyboard"))
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: String(localized: "Show Keyboard"), action: #selector(showKeyboard), keyEquivalent: "k")
        )
        menu.addItem(
            NSMenuItem(title: String(localized: "Hide Keyboard"), action: #selector(hideKeyboard), keyEquivalent: "h")
        )
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: String(localized: "Quit Tekla"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        statusItem?.menu = menu
    }

    @objc private func showKeyboard() {
        if keyboardPanel == nil {
            let hostingView = NSHostingView(rootView: KeyboardContentView())
            hostingView.frame = NSRect(x: 0, y: 0, width: 920, height: 340)
            keyboardPanel = KeyboardPanel(contentView: hostingView)
        }
        keyboardPanel?.orderFront(nil)
        keyboardPanel?.deminiaturize(nil)
    }

    @objc private func hideKeyboard() {
        keyboardPanel?.orderOut(nil)
    }
}

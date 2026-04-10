import AppKit
import SwiftUI
import Sparkle

/// Sets up the floating keyboard panel on launch and provides
/// a menu bar status item for show/hide and quit.
final class AppDelegate: NSObject, NSApplicationDelegate {

    static let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var keyboardPanel: KeyboardPanel?
    private var statusItem: NSStatusItem?
    private var activationWindow: NSWindow?
    let settings = SettingsManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        if settings.isUnlocked {
            launchKeyboard()
        } else {
            showActivationWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running when the panel is closed — user can re-show from menu bar
    }

    // MARK: - Activation

    private func showActivationWindow() {
        // Show in Dock while activation window is visible
        NSApp.setActivationPolicy(.regular)

        let view = ActivationView(settings: settings) { [weak self] in
            self?.activationWindow?.close()
            self?.activationWindow = nil
            self?.launchKeyboard()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tekla"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        activationWindow = window
    }

    private func launchKeyboard() {
        activationWindow?.close()
        activationWindow = nil

        let hostingView = NSHostingView(rootView: KeyboardContentView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 920, height: 340)

        keyboardPanel = KeyboardPanel(contentView: hostingView)
        keyboardPanel?.orderFront(nil)

        // Accessory mode — no prominent Dock icon
        NSApp.setActivationPolicy(.accessory)
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
        let updateItem = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
        if !settings.isUnlocked {
            menu.addItem(
                NSMenuItem(title: String(localized: "Enter License"), action: #selector(showActivation), keyEquivalent: "l")
            )
            menu.addItem(.separator())
        }
        menu.addItem(
            NSMenuItem(title: String(localized: "Quit Tekla"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )

        statusItem?.menu = menu
    }

    @objc private func checkForUpdates() {
        AppDelegate.updaterController.checkForUpdates(nil)
    }

    @objc private func showActivation() {
        showActivationWindow()
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

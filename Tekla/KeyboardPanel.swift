import AppKit
import SwiftUI

/// A non-activating floating panel that hosts the virtual keyboard.
/// Clicking keys on this panel does NOT steal focus from the target app.
final class KeyboardPanel: NSPanel {

    init(contentView: NSView) {
        let defaultWidth: CGFloat = 920
        let defaultHeight: CGFloat = 340

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - defaultWidth / 2,
            y: screenFrame.origin.y + 20
        )
        let contentRect = NSRect(origin: origin, size: NSSize(width: defaultWidth, height: defaultHeight))

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .resizable, .titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden

        // Float above other windows, appear on all Spaces
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Non-activating behavior
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true

        // Visual
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        // NOTE: isMovableByWindowBackground is intentionally OFF.
        // It conflicts with swipe-to-type drag gestures over the keyboard.
        // The window is movable by dragging the titlebar area.
        self.isMovableByWindowBackground = false

        // Min size for usability
        self.minSize = NSSize(width: 700, height: 260)

        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

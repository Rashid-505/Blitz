import AppKit
import SwiftUI

/// A floating, non-activating panel that hosts the Blitz scenario overlay.
///
/// Key properties:
/// - `.nonactivatingPanel` — clicking inside does NOT steal focus from the
///   active application, preserving the user's text selection.
/// - `canBecomeKey = true` — allows the panel to receive Escape key events.
/// - `canBecomeMain = false` — never becomes the "main" application window.
/// - `.floating` level — appears above normal application windows.
/// - `.canJoinAllSpaces` — visible regardless of active Space.
final class BlitzOverlayWindow: NSPanel {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Content

    func setContent<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
    }
}

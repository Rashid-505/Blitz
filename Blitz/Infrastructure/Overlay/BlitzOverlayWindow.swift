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

    // Height of the drag-handle header area in points.
    static let headerHeight: CGFloat = 45

    // Stores the mouse-down event from the header so it can be handed to
    // performWindowDrag when the first drag event arrives.
    private var pendingHeaderMouseDown: NSEvent?

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

    // MARK: - Native window drag

    /// Routes header drag gestures to `performWindowDrag(with:)` so the
    /// WindowServer moves the window — no per-frame main-thread work.
    /// Button clicks in the header still pass through normally because we
    /// intercept the first `leftMouseDragged`, not `leftMouseDown`/`Up`.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pendingHeaderMouseDown = event.locationInWindow.y >= (frame.height - BlitzOverlayWindow.headerHeight)
                ? event : nil
            super.sendEvent(event)

        case .leftMouseDragged:
            if let stored = pendingHeaderMouseDown {
                pendingHeaderMouseDown = nil
                performDrag(with: stored)
                return  // performWindowDrag ran the modal loop; don't forward.
            }
            super.sendEvent(event)

        case .leftMouseUp:
            pendingHeaderMouseDown = nil
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    // MARK: - Content

    func setContent<Content: View>(_ view: Content) {
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
    }
}

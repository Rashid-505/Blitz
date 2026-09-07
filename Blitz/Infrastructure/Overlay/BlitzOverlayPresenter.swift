import AppKit
import SwiftUI
import SwiftData

/// Manages the lifecycle of the floating Blitz overlay panel.
///
/// Responsibilities:
/// - Create and configure the NSPanel
/// - Position it near the selected text
/// - Show / hide it
/// - Coordinate dismissal
///
/// Does NOT contain AI logic, scenario persistence, or text replacement.
@MainActor
final class BlitzOverlayPresenter {

    private var window: BlitzOverlayWindow?
    private let orchestrator: TransformationOrchestrator
    private let providerStore: ProviderStore
    private let scenarioStore: ScenarioStore
    private let modelContainer: ModelContainer
    private var openSettingsAction: (() -> Void)?
    private var clickOutsideMonitor: Any?
    private var completionObserver: Task<Void, Never>?

    init(
        orchestrator: TransformationOrchestrator,
        providerStore: ProviderStore,
        scenarioStore: ScenarioStore,
        modelContainer: ModelContainer
    ) {
        self.orchestrator = orchestrator
        self.providerStore = providerStore
        self.scenarioStore = scenarioStore
        self.modelContainer = modelContainer
    }

    func setOpenSettings(_ action: @escaping () -> Void) {
        openSettingsAction = action
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Show / Hide

    func show(near sourceRect: CGRect?) {
        // If already visible, just reposition and bring to front.
        if let existing = window, existing.isVisible {
            if let rect = sourceRect {
                position(window: existing, near: rect)
            }
            existing.makeKey()
            return
        }

        // Reset orchestrator to idle so the overlay starts with the scenario list.
        orchestrator.cancel()

        let overlayView = BlitzOverlayView(
            onDismiss: { [weak self] in self?.hide() },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.openSettingsAction?()
            },
            onNeedsResize: { [weak self] in self?.resizeToFit() }
        )
        .environment(orchestrator)
        .environment(providerStore)
        .environment(scenarioStore)
        .modelContainer(modelContainer)

        let panel = BlitzOverlayWindow()
        panel.setContent(overlayView)

        // Size the panel to fit the initial (idle) content.
        if let fittingSize = panel.contentView?.fittingSize, fittingSize != .zero {
            panel.setContentSize(fittingSize)
        } else {
            panel.setContentSize(CGSize(width: 240, height: 240))
        }

        if let rect = sourceRect {
            position(window: panel, near: rect)
        } else {
            centerOnScreen(panel)
        }

        window = panel
        panel.orderFrontRegardless()
        panel.makeKey()

        installClickOutsideMonitor()
        observeCompletionForAutoDismiss()
    }

    func hide() {
        removeClickOutsideMonitor()
        completionObserver?.cancel()
        completionObserver = nil
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Positioning

    private func position(window panel: NSPanel, near rect: CGRect) {
        guard let screen = screenContaining(rect) ?? NSScreen.main else {
            centerOnScreen(panel)
            return
        }

        let panelSize = panel.frame.size
        let screenFrame = screen.visibleFrame
        let screenHeight = screen.frame.height

        // AX / Quartz coordinates have origin top-left; AppKit has origin bottom-left.
        let cocoaY = screenHeight - rect.maxY
        let gap: CGFloat = 6

        // Prefer positioning below the selection.
        var origin = CGPoint(
            x: rect.minX,
            y: cocoaY - panelSize.height - gap
        )

        // Clamp horizontally within the visible screen.
        origin.x = min(origin.x, screenFrame.maxX - panelSize.width)
        origin.x = max(origin.x, screenFrame.minX)

        // If below goes off-screen, flip above.
        if origin.y < screenFrame.minY {
            origin.y = cocoaY + rect.height + gap
        }

        // Clamp vertically.
        origin.y = min(origin.y, screenFrame.maxY - panelSize.height)
        origin.y = max(origin.y, screenFrame.minY)

        panel.setFrameOrigin(origin)
    }

    private func centerOnScreen(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let ps = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: sf.midX - ps.width / 2,
            y: sf.midY - ps.height / 2
        ))
    }

    /// Finds the NSScreen whose frame contains the Quartz-coordinate rect midpoint.
    private func screenContaining(_ rect: CGRect) -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        // Convert Quartz midpoint to Cocoa coordinates using the primary screen height.
        let cocoaPoint = CGPoint(x: rect.midX, y: primary.frame.height - rect.midY)
        return NSScreen.screens.first { $0.frame.contains(cocoaPoint) }
    }

    // MARK: - Panel resize

    /// Re-measures the hosting view's fitting size and resizes the panel to match,
    /// preserving the panel's top-left corner so it doesn't jump on screen.
    private func resizeToFit() {
        guard let panel = window, let contentView = panel.contentView else { return }
        let newSize = contentView.fittingSize
        guard newSize != .zero else { return }
        // Preserve top-left corner: AppKit origin is bottom-left, so adjust y.
        let oldFrame = panel.frame
        let deltaHeight = newSize.height - oldFrame.size.height
        let newOriginY = oldFrame.origin.y - deltaHeight
        panel.setFrame(
            CGRect(origin: CGPoint(x: oldFrame.origin.x, y: newOriginY), size: newSize),
            display: true,
            animate: false
        )
    }

    // MARK: - Click-outside dismissal

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        // Global mouse monitor for click-outside. Mouse event monitoring does not
        // require Input Monitoring permission (only keyboard monitoring does).
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, let panel = self.window else { return }
            let mouseLocation = NSEvent.mouseLocation
            // Do not dismiss while the user is actively transforming or reviewing a preview —
            // an accidental mis-click outside the panel must not silently discard their result.
            let state = self.orchestrator.state
            if !panel.frame.contains(mouseLocation),
               !state.isTransforming,
               !state.isPreview {
                Task { @MainActor in self.hide() }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    // MARK: - Auto-dismiss after successful transformation

    private func observeCompletionForAutoDismiss() {
        completionObserver?.cancel()
        completionObserver = Task { [weak self] in
            guard let self else { return }
            var wasTransforming = false
            // Once we enter preview the auto-dismiss logic is disabled:
            // the overlay's Replace/Discard buttons take responsibility for hiding.
            var enteredPreview = false
            while !Task.isCancelled {
                let currentState = await MainActor.run { self.orchestrator.state }
                if currentState.isTransforming {
                    wasTransforming = true
                }
                if currentState.isPreview {
                    enteredPreview = true
                    // Resize the panel now that the preview content is rendered.
                    await MainActor.run { self.resizeToFit() }
                }
                // Auto-dismiss only when going transforming → idle without a preview step.
                if wasTransforming, !enteredPreview, case .idle = currentState {
                    await MainActor.run { self.hide() }
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

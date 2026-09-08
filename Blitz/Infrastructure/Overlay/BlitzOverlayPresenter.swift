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
    private var keyDownMonitor: Any?
    private var completionObserver: Task<Void, Never>?
    private let navigationState = OverlayNavigationState()

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
        // If already visible, just reposition, reset navigation, and bring to front.
        if let existing = window, existing.isVisible {
            navigationState.highlightedIndex = 0
            positionNearMouse(window: existing)
            existing.makeKey()
            return
        }

        // Reset orchestrator to idle so the overlay starts with the scenario list.
        orchestrator.cancel()
        navigationState.highlightedIndex = 0

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
        .environment(navigationState)
        .modelContainer(modelContainer)

        let panel = BlitzOverlayWindow()
        panel.setContent(overlayView)

        // Size the panel to fit the initial (idle) content.
        if let fittingSize = panel.contentView?.fittingSize, fittingSize != .zero {
            panel.setContentSize(fittingSize)
        } else {
            panel.setContentSize(CGSize(width: 240, height: 240))
        }

        positionNearMouse(window: panel)

        window = panel
        panel.orderFrontRegardless()
        panel.makeKey()

        installClickOutsideMonitor()
        installKeyDownMonitor()
        observeCompletionForAutoDismiss()
    }

    func hide() {
        removeClickOutsideMonitor()
        removeKeyDownMonitor()
        completionObserver?.cancel()
        completionObserver = nil
        window?.orderOut(nil)
        window = nil
    }

    // MARK: - Positioning

    /// Positions the panel above the current mouse cursor, falling back to below
    /// when there is insufficient space, then clamping within the visible screen.
    private func positionNearMouse(window panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }

        let sf = screen.visibleFrame
        let ps = panel.frame.size
        let gap: CGFloat = 8

        // Prefer above: panel bottom = mouse.y + gap
        var origin = CGPoint(
            x: mouse.x - ps.width / 2,
            y: mouse.y + gap
        )

        // If panel would overflow the top of the visible area, flip below.
        if origin.y + ps.height > sf.maxY {
            origin.y = mouse.y - ps.height - gap
        }

        // Clamp within visible screen bounds.
        origin.x = min(max(origin.x, sf.minX), sf.maxX - ps.width)
        origin.y = min(max(origin.y, sf.minY), sf.maxY - ps.height)

        panel.setFrameOrigin(origin)
    }

    // MARK: - Panel resize

    /// Re-measures the hosting view's fitting size and resizes the panel to match.
    ///
    /// Expansion direction:
    /// - Default: anchor the **top**-left corner and grow downward (origin.y decreases).
    /// - Fallback: if growing downward would clip below the visible screen, anchor the
    ///   **bottom** instead and grow upward (origin.y stays fixed).
    /// The result is always clamped within the screen's visible frame.
    private func resizeToFit() {
        guard let panel = window, let contentView = panel.contentView else { return }
        let newSize = contentView.fittingSize
        guard newSize != .zero else { return }

        let oldFrame = panel.frame
        let deltaHeight = newSize.height - oldFrame.size.height

        // Resolve the screen that owns the panel's top-left anchor point.
        let topLeft = CGPoint(x: oldFrame.minX, y: oldFrame.maxY)
        let screen = NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? oldFrame
        let screenMinY = visibleFrame.minY
        let screenMaxY = visibleFrame.maxY

        // Try top-anchored growth (origin moves down, top stays fixed).
        var newOriginY = oldFrame.origin.y - deltaHeight

        // If that clips below the screen, switch to bottom-anchored growth (origin
        // stays, window top moves up). This handles windows positioned above the
        // text selection — they should open further upward, not off-screen downward.
        if newOriginY < screenMinY {
            newOriginY = oldFrame.origin.y
        }

        // Clamp within the visible screen so neither edge escapes.
        newOriginY = max(newOriginY, screenMinY)
        newOriginY = min(newOriginY, screenMaxY - newSize.height)

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
               !state.isPreview,
               !state.isFailed {
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

    // MARK: - Keyboard navigation

    private func installKeyDownMonitor() {
        removeKeyDownMonitor()
        // Local monitors run on the main thread and only see events processed by
        // our own app's windows. No Input Monitoring permission is required.
        // We use this instead of SwiftUI .keyboardShortcut because the focus
        // system in a non-activating panel is unreliable.
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyDownMonitor() {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }

    /// Returns `nil` to consume the event (prevent further dispatch), or the original
    /// event to let it fall through to SwiftUI's responder chain (e.g. Escape → `.onExitCommand`).
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Only intercept events directed at our overlay panel.
        guard window?.isKeyWindow == true else { return event }

        // Never block input while a transformation is running — let Escape reach
        // `.onExitCommand` so the user can still cancel.
        guard case .idle = orchestrator.state else { return event }

        let scenarios = scenarioStore.enabledScenarios
        guard !scenarios.isEmpty else { return event }

        switch event.keyCode {
        case 126: // ↑ Up arrow
            navigationState.highlightedIndex = max(0, navigationState.highlightedIndex - 1)
            return nil
        case 125: // ↓ Down arrow
            navigationState.highlightedIndex = min(scenarios.count - 1, navigationState.highlightedIndex + 1)
            return nil
        case 36, 76: // Return / numpad Enter
            triggerScenario(at: navigationState.highlightedIndex)
            return nil
        default:
            // Digit shortcuts 1–9 with no modifier keys held.
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if mods.isEmpty,
               let char = event.charactersIgnoringModifiers,
               let digit = Int(char),
               digit >= 1, digit <= 9 {
                let index = digit - 1
                if index < scenarios.count {
                    triggerScenario(at: index)
                }
                return nil
            }
            return event
        }
    }

    private func triggerScenario(at index: Int) {
        let scenarios = scenarioStore.enabledScenarios
        guard index < scenarios.count else { return }
        let scenario = scenarios[index]
        guard let provider = providerStore.makeActiveProvider() else {
            openSettingsAction?()
            return
        }
        orchestrator.transform(with: scenario, provider: provider)
    }

    // MARK: - Auto-dismiss after successful transformation

    private func observeCompletionForAutoDismiss() {
        completionObserver?.cancel()
        // Run explicitly on the main actor so all orchestrator and window accesses
        // are direct — no MainActor.run hops required.
        completionObserver = Task { @MainActor [weak self] in
            guard let self else { return }
            var wasTransforming = false
            // Once we enter preview the auto-dismiss logic is disabled:
            // the overlay's Replace/Discard buttons take responsibility for hiding.
            var enteredPreview = false
            var lastRevisionDepth = -1

            while !Task.isCancelled {
                let state = orchestrator.state
                let depth = orchestrator.revisionDepth

                if state.isTransforming { wasTransforming = true }

                if state.isPreview {
                    enteredPreview = true
                    if depth != lastRevisionDepth {
                        lastRevisionDepth = depth
                        resizeToFit()
                    }
                }

                // Auto-dismiss only when going transforming → idle without a preview step.
                if wasTransforming, !enteredPreview, case .idle = state {
                    hide()
                    return
                }

                // The one-shot paste path calls orderOut on the panel so ⌘V reaches
                // the target app. If the paste then fails, re-show the error panel.
                if state.isFailed, let w = window, !w.isVisible {
                    w.orderFrontRegardless()
                    w.makeKey()
                    resizeToFit()
                }

                // Suspend until orchestrator state or revisionDepth actually changes.
                // withObservationTracking is push-based: the main actor is untouched
                // during idle periods (e.g. while the user drags another window).
                // The old 100 ms sleep-poll caused ~30 main-actor hops per second,
                // producing input latency and frame drops during drag operations.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.orchestrator.state
                        _ = self.orchestrator.revisionDepth
                    } onChange: {
                        continuation.resume()
                    }
                }
                // One yield after resumption so Task cancellation (from hide()) can
                // be detected before the next loop iteration reads orchestrator state.
                await Task.yield()
            }
        }
    }
}

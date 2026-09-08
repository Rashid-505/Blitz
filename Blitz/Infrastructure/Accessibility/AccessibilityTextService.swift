import AppKit
import ApplicationServices
import os

/// Lightweight logging used to diagnose text-selection issues. Visible in the
/// Xcode console and Console.app (subsystem "com.rashidhuseynov.Blitz").
enum BlitzLog {
    private static let logger = Logger(subsystem: "com.rashidhuseynov.Blitz", category: "ax")
    static func ax(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        print("[Blitz.ax] \(message)")
    }
}

final class AccessibilityTextService: TextSelectionService, TextReplacementService {

    private var previousFrontmostApp: NSRunningApplication?
    private var notificationObserver: NSObjectProtocol?

    // Text captured on hotkey press, before the overlay window appears.
    // Consumed by the first readSelectedText() call and then cleared.
    private var cachedSelectedText: String?

    // AX element and selection range captured in preReadSelection(). Used in
    // pasteboardFallback() to restore focus and the original selection so ⌘V
    // replaces the selection rather than inserting at a lost cursor position.
    private var cachedFocusedElement: AXUIElement? = nil
    private var cachedSelectionRangeRef: CFTypeRef? = nil

    init() {
        // Track the last non-Blitz frontmost app so we can target it after
        // the menu bar opens and Blitz becomes the frontmost process.
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.previousFrontmostApp = app
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Pre-read

    /// Captures the current text selection while the target app still holds keyboard focus.
    ///
    /// **Must be called before showing the Blitz overlay.** Electron/Chromium apps
    /// (Teams, Slack, VS Code, Chrome) often clear their text selection when any
    /// other window calls `makeKey()`, even a `.nonactivatingPanel`. Reading the
    /// selection before `show()` guarantees the text is available when the user
    /// taps a scenario.
    ///
    /// The captured text is stored internally and consumed by the next
    /// `readSelectedText()` call. If the read fails, the cache remains nil and
    /// `readSelectedText()` performs a live read as a fallback.
    func preReadSelection() async {
        cachedSelectedText = nil
        cachedFocusedElement = nil
        cachedSelectionRangeRef = nil
        BlitzLog.ax("preRead: capturing selection before overlay appears")
        cachedSelectedText = try? await readSelectedTextCore()
        // Capture the focused AX element and its selection range while the target app
        // still has keyboard focus. pasteboardFallback() uses these to restore focus
        // and the original selection in Chrome / Teams before posting ⌘V, so the paste
        // replaces the original text rather than inserting at a lost cursor position.
        if let app = resolveTargetApp() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            let focused = focusedElement(in: appElement) ?? focusedElementViaWindow(in: appElement)
            cachedFocusedElement = focused
            if let el = focused {
                var rangeRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success {
                    cachedSelectionRangeRef = rangeRef
                }
            }
        }
        BlitzLog.ax("preRead: cached \(cachedSelectedText.map { "\($0.count) chars" } ?? "nil"), element=\(cachedFocusedElement != nil), range=\(cachedSelectionRangeRef != nil)")
    }

    // MARK: - TextSelectionService

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readSelectedText() async throws -> String {
        // Prefer the text captured by preReadSelection() — it was read while the
        // target app still had keyboard focus, before the overlay stole it.
        if let cached = cachedSelectedText, !cached.isEmpty {
            cachedSelectedText = nil
            BlitzLog.ax("readSelectedText: returning pre-captured text (\(cached.count) chars)")
            return cached
        }
        cachedSelectedText = nil
        return try await readSelectedTextCore()
    }

    private func readSelectedTextCore() async throws -> String {
        let trusted = hasAccessibilityPermission()
        BlitzLog.ax("readSelectedText start — AXIsProcessTrusted=\(trusted)")
        guard trusted else {
            throw TextServiceError.accessibilityPermissionDenied
        }

        // Attempt 1: Accessibility API. Fast and non-destructive, but only works
        // for native AppKit text controls that expose kAXSelectedText.
        if let text = readSelectedTextViaAccessibility(), !text.isEmpty {
            BlitzLog.ax("AX read succeeded (\(text.count) chars)")
            return text
        }

        // Attempt 2: Clipboard copy fallback. Browsers (Safari, Chrome) and
        // Electron/Catalyst apps (VS Code, Slack, Teams, etc.) do NOT expose
        // their selection through the Accessibility API, so we simulate ⌘C and
        // read the selection off the pasteboard, restoring it afterward.
        if let text = try await readSelectedTextViaPasteboard(), !text.isEmpty {
            BlitzLog.ax("Pasteboard read succeeded (\(text.count) chars)")
            return text
        }

        BlitzLog.ax("Both read paths failed → throwing noTextSelected")
        throw TextServiceError.noTextSelected
    }

    // MARK: - AX read

    /// Reads the current selection through the Accessibility API.
    ///
    /// Two-level search: the application element first (standard AppKit path),
    /// then via the focused window element (Chromium/Electron fallback).
    /// Setting `AXEnhancedUserInterface` before querying activates the Chromium
    /// accessibility tree; native AppKit apps ignore this attribute.
    private func readSelectedTextViaAccessibility() -> String? {
        guard let app = resolveTargetApp() else {
            BlitzLog.ax("AX: resolveTargetApp returned nil")
            return nil
        }
        BlitzLog.ax("AX: target app = \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] pid=\(app.processIdentifier) active=\(app.isActive)")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Hint Chromium/Electron to expose their accessibility tree.
        AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)

        // Path 1: app element → focused UI element (standard AppKit apps).
        if let focused = focusedElement(in: appElement) {
            if let text = selectedText(in: focused), !text.isEmpty {
                BlitzLog.ax("AX: selected-text length=\(text.count) (app element path)")
                return text
            }
            BlitzLog.ax("AX: app-level focused element found but no selected text")
        }

        // Path 2: app element → focused window → focused UI element.
        // Chromium/Electron often only surfaces kAXFocusedUIElement on the
        // window, not on the application element.
        if let focused = focusedElementViaWindow(in: appElement) {
            if let text = selectedText(in: focused), !text.isEmpty {
                BlitzLog.ax("AX: selected-text length=\(text.count) (window element path)")
                return text
            }
            BlitzLog.ax("AX: window-level focused element found but no selected text")
        }

        BlitzLog.ax("AX: all accessibility paths exhausted")
        return nil
    }

    // MARK: - Pasteboard read

    /// Reads the current selection by simulating ⌘C and inspecting the pasteboard,
    /// then restoring the previous clipboard contents.
    private func readSelectedTextViaPasteboard() async throws -> String? {
        guard let app = resolveTargetApp() else {
            BlitzLog.ax("Pasteboard: no target app")
            return nil
        }

        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        // Unconditionally re-activate the target app — even when isActive=true.
        //
        // Root cause: BlitzOverlayWindow calls makeKey() when it appears, which
        // transfers keyboard focus to the panel even though NSRunningApplication
        // still reports the target app as "active" (a .nonactivatingPanel quirk).
        // Without re-activation ⌘C is delivered to the Blitz panel, not Teams/Chrome.
        // Explicit activation restores keyboard focus to the target app.
        BlitzLog.ax("Pasteboard: activating \(app.localizedName ?? "?") (isActive=\(app.isActive))")
        app.activate(from: NSRunningApplication.current)
        // Wait for the OS to transfer keyboard focus before posting the keystroke.
        try await Task.sleep(for: .milliseconds(120))

        BlitzLog.ax("Pasteboard: posting ⌘C (previousChangeCount=\(previousChangeCount))")
        postCommandKey(keyCode: 8) // 'c'

        // Poll with retries instead of a single fixed wait. Electron/Chromium apps
        // route ⌘C through the renderer process and can take 200–400 ms to update
        // the pasteboard. Budget: first check at 100 ms, then 4 × 80 ms = 420 ms.
        var copied: String?
        for attempt in 0..<5 {
            try await Task.sleep(for: .milliseconds(attempt == 0 ? 100 : 80))
            let newCount = pasteboard.changeCount
            if newCount != previousChangeCount {
                copied = pasteboard.string(forType: .string)
                BlitzLog.ax("Pasteboard: changed on attempt \(attempt + 1) newCount=\(newCount) copiedLen=\(copied?.count ?? -1)")
                break
            }
            BlitzLog.ax("Pasteboard: no change on attempt \(attempt + 1)")
        }

        if copied == nil {
            BlitzLog.ax("Pasteboard: no change after all retries — likely no selection in target app")
        }

        // Restore the user's previous clipboard contents.
        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }

        return copied
    }

    /// Posts a Command+<key> keystroke to the system-wide HID event tap.
    private func postCommandKey(keyCode: CGKeyCode) {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - TextReplacementService

    func replaceSelectedText(with newText: String) async throws {
        guard hasAccessibilityPermission() else {
            throw TextServiceError.accessibilityPermissionDenied
        }

        guard let app = resolveTargetApp() else {
            throw TextServiceError.replacementFailed("No target application found")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Try AX write first (instant, no clipboard pollution).
        // Check both the app-element path and the window path for Chromium/Electron.
        let focusedEl = focusedElement(in: appElement) ?? focusedElementViaWindow(in: appElement)
        if let focused = focusedEl {
            // Read the selection BEFORE writing so we can detect silent failures.
            // Chromium and Electron often return .success but silently discard the
            // write — the only reliable confirmation is that the selected text changed.
            let selectionBefore = selectedText(in: focused)
            let result = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)
            if result == .success {
                if selectedText(in: focused) != selectionBefore {
                    return  // Write confirmed: the selection actually changed.
                }
                BlitzLog.ax("AX: write returned success but selection is unchanged — falling back to pasteboard")
            } else {
                BlitzLog.ax("AX: set selected-text failed err=\(result.rawValue), falling back to pasteboard")
            }
        } else {
            BlitzLog.ax("AX: no focused element for replacement, falling back to pasteboard")
        }

        // ⌘V paste fallback: works for all apps including Electron/Chromium.
        try await pasteboardFallback(newText, into: app)
    }

    // MARK: - Position

    /// Returns a screen-coordinate rect for the current text selection, suitable
    /// for positioning the overlay panel near the selected text.
    ///
    /// Fallback order:
    ///   1. Selected-text bounds via AX parameterized attribute (supported by
    ///      NSTextView-based apps; unavailable in browsers, Electron, etc.)
    ///   2. Focused element frame via kAXFrameAttribute (widely supported)
    ///   3. Mouse cursor position (always available)
    ///   4. nil — caller should use a screen-center fallback
    func getSelectionScreenRect() -> CGRect? {
        guard let app = resolveTargetApp() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        guard let focused = focusedElement(in: appElement) ?? focusedElementViaWindow(in: appElement) else {
            return mouseLocationFallback()
        }

        if let rect = selectedTextBounds(in: focused) { return rect }
        if let rect = elementFrame(focused) { return rect }
        return mouseLocationFallback()
    }

    // MARK: - AX helpers

    /// Returns the element holding keyboard focus within `element` (app or window).
    private func focusedElement(in element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &ref)
        guard err == .success, let ref else {
            BlitzLog.ax("AX: focused element query failed err=\(err.rawValue)")
            return nil
        }
        return (ref as! AXUIElement)
    }

    /// Returns the focused UI element via the app's focused window.
    /// Chromium/Electron often only exposes `kAXFocusedUIElement` on the window,
    /// not on the application element.
    private func focusedElementViaWindow(in appElement: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        guard err == .success, let windowRef else {
            BlitzLog.ax("AX: focused window query failed err=\(err.rawValue)")
            return nil
        }
        return focusedElement(in: windowRef as! AXUIElement)
    }

    /// Returns the selected text for `element`, or nil if unavailable.
    private func selectedText(in element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref)
        guard err == .success, let text = ref as? String else {
            if err != .success {
                BlitzLog.ax("AX: selected-text query failed err=\(err.rawValue)")
            }
            return nil
        }
        return text
    }

    private func selectedTextBounds(in element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeRef,
            &boundsRef
        )
        guard status == .success, let boundsRef else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        guard rect != .zero else { return nil }
        return rect
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              let posRef else { return nil }
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position) else { return nil }
        guard AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        let rect = CGRect(origin: position, size: size)
        guard rect != .zero else { return nil }
        return rect
    }

    private func mouseLocationFallback() -> CGRect? {
        let loc = NSEvent.mouseLocation
        return CGRect(x: loc.x, y: loc.y, width: 0, height: 0)
    }

    // MARK: - Private

    private func resolveTargetApp() -> NSRunningApplication? {
        if let current = NSWorkspace.shared.frontmostApplication,
           current.bundleIdentifier != Bundle.main.bundleIdentifier {
            return current
        }
        return previousFrontmostApp
    }

    private func pasteboardFallback(_ text: String, into app: NSRunningApplication) async throws {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Order out Blitz's overlay panel before posting ⌘V.
        //
        // A hidden window cannot be the key window, so ordering it out forces
        // the OS to immediately transfer key-window status back to Chrome / Teams.
        // Calling resignKey() was insufficient: it is a notification method and
        // does not reliably strip the panel of key status in all OS versions.
        // The presenter's observeCompletionForAutoDismiss re-shows the panel when
        // it detects the window became invisible while the state is .failed.
        NSApp.windows.first { $0.isKeyWindow }?.orderOut(nil)

        app.activate(from: NSRunningApplication.current)
        // Give the window server time to complete the focus transfer.
        try await Task.sleep(for: .milliseconds(200))

        // Attempt to restore the original text selection via the Accessibility API.
        // When the Blitz panel was key, Chrome / Teams loses internal text-field focus
        // even though the window remains visually active. Setting kAXSelectedTextRange
        // on the pre-captured element both refocuses the field and re-establishes the
        // selection, so ⌘V replaces the original text rather than inserting at an
        // unknown cursor position.
        if let el = cachedFocusedElement, let rangeRef = cachedSelectionRangeRef {
            let restoreResult = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, rangeRef)
            BlitzLog.ax("Pasteboard: restore selection range result=\(restoreResult.rawValue)")
            if restoreResult == .success {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else {
            // CGEvent creation failed — restore the clipboard before giving up.
            pasteboard.clearContents()
            if let saved {
                pasteboard.setString(saved, forType: .string)
            }
            throw TextServiceError.replacementFailed("Failed to create keyboard event")
        }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try await Task.sleep(for: .milliseconds(200))

        pasteboard.clearContents()
        if let saved {
            pasteboard.setString(saved, forType: .string)
        }
    }
}

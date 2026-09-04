import AppKit
import ApplicationServices

final class AccessibilityTextService: TextSelectionService, TextReplacementService {

    private var previousFrontmostApp: NSRunningApplication?
    private var notificationObserver: NSObjectProtocol?

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

    // MARK: - TextSelectionService

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func readSelectedText() async throws -> String {
        guard hasAccessibilityPermission() else {
            throw TextServiceError.accessibilityPermissionDenied
        }

        guard let app = resolveTargetApp() else {
            throw TextServiceError.noTextSelected
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else {
            throw TextServiceError.noTextSelected
        }

        // AXUIElementCopyAttributeValue for kAXFocusedUIElement always returns an AXUIElement.
        let focused = focusedRef as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
              let text = selectedRef as? String,
              !text.isEmpty else {
            throw TextServiceError.noTextSelected
        }

        return text
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

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else {
            throw TextServiceError.replacementFailed("Could not find focused element in target application")
        }

        let focused = focusedRef as! AXUIElement
        let result = AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, newText as CFTypeRef)

        if result != .success {
            try await pasteboardFallback(newText, into: app)
        }
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

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else {
            return mouseLocationFallback()
        }
        let focused = focusedRef as! AXUIElement

        // Attempt 1: bounds for the selected text range
        if let rect = selectedTextBounds(in: focused) {
            return rect
        }

        // Attempt 2: frame of the focused element itself
        if let rect = elementFrame(focused) {
            return rect
        }

        // Attempt 3: mouse cursor
        return mouseLocationFallback()
    }

    private func selectedTextBounds(in element: AXUIElement) -> CGRect? {
        // Get the selected text range as an AXValue wrapping a CFRange.
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        // Ask for the bounding rect of that range.
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

        app.activate()

        // Brief delay so the target app comes to foreground before the keypress.
        try await Task.sleep(for: .milliseconds(100))

        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else {
            // CGEvent creation failed — restore the clipboard before giving up.
            if let saved {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
            throw TextServiceError.replacementFailed("Failed to create keyboard event")
        }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try await Task.sleep(for: .milliseconds(150))

        if let saved {
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }
}

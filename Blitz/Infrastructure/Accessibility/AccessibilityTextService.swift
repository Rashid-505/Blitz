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
        // Electron/Catalyst apps (VS Code, Slack, Notion, etc.) do NOT expose
        // their selection through the Accessibility API, so we simulate ⌘C and
        // read the selection off the pasteboard, restoring it afterward.
        if let text = try await readSelectedTextViaPasteboard(), !text.isEmpty {
            BlitzLog.ax("Pasteboard read succeeded (\(text.count) chars)")
            return text
        }

        BlitzLog.ax("Both read paths failed → throwing noTextSelected")
        throw TextServiceError.noTextSelected
    }

    /// Reads the current selection through the Accessibility API.
    /// Returns nil if the target app does not expose selected text this way.
    private func readSelectedTextViaAccessibility() -> String? {
        guard let app = resolveTargetApp() else {
            BlitzLog.ax("AX: resolveTargetApp returned nil")
            return nil
        }
        BlitzLog.ax("AX: target app = \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "?")] pid=\(app.processIdentifier) active=\(app.isActive)")

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focusedRef else {
            BlitzLog.ax("AX: focused element query failed err=\(focusErr.rawValue)")
            return nil
        }

        // AXUIElementCopyAttributeValue for kAXFocusedUIElement always returns an AXUIElement.
        let focused = focusedRef as! AXUIElement
        var selectedRef: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef)
        guard selErr == .success, let text = selectedRef as? String else {
            BlitzLog.ax("AX: selected-text query failed err=\(selErr.rawValue) type=\(String(describing: selectedRef))")
            return nil
        }

        BlitzLog.ax("AX: selected-text length=\(text.count)")
        return text
    }

    /// Reads the current selection by simulating ⌘C and inspecting the pasteboard,
    /// then restoring the previous clipboard contents. Works in apps that do not
    /// support the Accessibility selected-text attribute.
    private func readSelectedTextViaPasteboard() async throws -> String? {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        // Ensure the target app is frontmost so the copy keystroke reaches it.
        if let app = resolveTargetApp(), !app.isActive {
            BlitzLog.ax("Pasteboard: activating target app \(app.localizedName ?? "?")")
            app.activate()
            try await Task.sleep(for: .milliseconds(80))
        }

        BlitzLog.ax("Pasteboard: posting ⌘C (previousChangeCount=\(previousChangeCount))")
        postCommandKey(keyCode: 8) // 'c'

        // Give the target app time to write the selection to the pasteboard.
        try await Task.sleep(for: .milliseconds(120))

        let changed = pasteboard.changeCount != previousChangeCount
        let copied = changed ? pasteboard.string(forType: .string) : nil
        BlitzLog.ax("Pasteboard: changed=\(changed) newChangeCount=\(pasteboard.changeCount) copiedLen=\(copied?.count ?? -1)")

        // Restore the user's previous clipboard contents.
        if let saved {
            pasteboard.clearContents()
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

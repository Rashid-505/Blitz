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

import Carbon
import AppKit
import Observation

/// Registers and manages a single application-wide global keyboard shortcut
/// using Carbon's RegisterEventHotKey API, which works in sandboxed apps
/// without requiring Input Monitoring permission.
@Observable
final class GlobalShortcutManager {

    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32   // Carbon modifier flags
        let displayString: String

        static let optionSpace = Shortcut(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            displayString: "⌥Space"
        )

        /// Build a Shortcut from a key-down NSEvent captured during recording.
        /// Returns nil if the event has no modifiers (prevents hijacking plain typing).
        static func from(event: NSEvent) -> Shortcut? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
                return nil
            }
            var carbonMods: UInt32 = 0
            if flags.contains(.command)  { carbonMods |= UInt32(cmdKey)     }
            if flags.contains(.option)   { carbonMods |= UInt32(optionKey)  }
            if flags.contains(.control)  { carbonMods |= UInt32(controlKey) }
            if flags.contains(.shift)    { carbonMods |= UInt32(shiftKey)   }

            let chars = event.charactersIgnoringModifiers ?? ""
            let display = makeDisplay(flags: flags, chars: chars)
            return Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonMods, displayString: display)
        }

        private static func makeDisplay(flags: NSEvent.ModifierFlags, chars: String) -> String {
            var s = ""
            if flags.contains(.control) { s += "⌃" }
            if flags.contains(.option)  { s += "⌥" }
            if flags.contains(.shift)   { s += "⇧" }
            if flags.contains(.command) { s += "⌘" }
            switch chars.lowercased() {
            case " ":      s += "Space"
            case "\r":     s += "Return"
            case "\t":     s += "Tab"
            case "\u{7f}": s += "Delete"
            default:       s += chars.uppercased()
            }
            return s
        }
    }

    private(set) var currentShortcut: Shortcut
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private static let hotkeySignature: OSType = 0x424C_545A

    private enum DefaultsKeys {
        static let keyCode      = "blitz.shortcut.keyCode"
        static let modifiers    = "blitz.shortcut.modifiers"
        static let displayString = "blitz.shortcut.displayString"
    }

    init() {
        currentShortcut = Self.loadSaved() ?? .optionSpace
    }

    deinit {
        unregister()
    }

    // MARK: - Public

    func register() {
        unregister()
        installEventHandlerIfNeeded()

        var hotkeyID = EventHotKeyID(signature: Self.hotkeySignature, id: 1)
        RegisterEventHotKey(
            currentShortcut.keyCode,
            currentShortcut.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        // Non-zero status is non-fatal: the menu bar remains functional.
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    func update(shortcut: Shortcut) {
        currentShortcut = shortcut
        persist(shortcut)
        register()
    }

    // MARK: - Persistence

    private static func loadSaved() -> Shortcut? {
        let d = UserDefaults.standard
        guard d.object(forKey: DefaultsKeys.keyCode) != nil,
              let display = d.string(forKey: DefaultsKeys.displayString) else { return nil }
        let keyCode   = UInt32(d.integer(forKey: DefaultsKeys.keyCode))
        let modifiers = UInt32(d.integer(forKey: DefaultsKeys.modifiers))
        return Shortcut(keyCode: keyCode, modifiers: modifiers, displayString: display)
    }

    private func persist(_ shortcut: Shortcut) {
        let d = UserDefaults.standard
        d.set(Int(shortcut.keyCode),   forKey: DefaultsKeys.keyCode)
        d.set(Int(shortcut.modifiers), forKey: DefaultsKeys.modifiers)
        d.set(shortcut.displayString,  forKey: DefaultsKeys.displayString)
    }

    // MARK: - Carbon event handler

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let m = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { m.onActivate?() }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )
    }
}

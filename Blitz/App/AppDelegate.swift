import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside LSUIElement=YES: guarantees the app
        // never appears in the Dock or Cmd+Tab switcher.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

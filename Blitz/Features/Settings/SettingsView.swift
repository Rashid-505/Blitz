import SwiftUI

struct SettingsView: View {
    let shortcutManager: GlobalShortcutManager

    var body: some View {
        TabView {
            GeneralSettingsView(shortcutManager: shortcutManager)
                .tabItem { Label("General", systemImage: "gear") }

            ScenariosSettingsView()
                .tabItem { Label("Scenarios", systemImage: "list.bullet") }

            ProvidersSettingsView()
                .tabItem { Label("Providers", systemImage: "cpu") }
        }
        .frame(width: 520, height: 460)
    }
}

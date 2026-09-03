import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ScenariosSettingsView()
                .tabItem { Label("Scenarios", systemImage: "list.bullet") }

            ProvidersSettingsView()
                .tabItem { Label("Providers", systemImage: "cpu") }
        }
        .frame(width: 520, height: 400)
    }
}

#Preview {
    SettingsView()
}

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ScenariosSettingsView()
                .tabItem { Label("Scenarios", systemImage: "list.bullet") }

            ContentUnavailableView(
                "Providers",
                systemImage: "cpu",
                description: Text("AI provider configuration will be available in Phase 3.")
            )
            .tabItem { Label("Providers", systemImage: "cpu") }
        }
        .frame(width: 520, height: 400)
    }
}

#Preview {
    SettingsView()
}

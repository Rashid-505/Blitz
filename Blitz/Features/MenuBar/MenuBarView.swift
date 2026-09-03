import SwiftUI
import SwiftData

struct MenuBarView: View {
    @Query(sort: \Scenario.order) private var scenarios: [Scenario]
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        scenariosSection

        Divider()

        Button("Settings...") {
            openSettings()
        }
        .keyboardShortcut(",")

        Button("About Blitz") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        Button("Quit Blitz") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var scenariosSection: some View {
        let enabled = scenarios.filter(\.isEnabled)
        if enabled.isEmpty {
            Text("No scenarios enabled")
                .foregroundStyle(.secondary)
        } else {
            ForEach(enabled) { scenario in
                Button(scenario.name) {
                    // Text acquisition and transformation wired in Phase 4.
                }
            }
        }
    }
}

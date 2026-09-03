import SwiftUI

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Activation hotkey") {
                    Text("⌘⇧B")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Launch at login") {
                    Text("Off")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    GeneralSettingsView()
        .frame(width: 500, height: 320)
}

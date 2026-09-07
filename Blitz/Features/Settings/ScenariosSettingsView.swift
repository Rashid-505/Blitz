import SwiftUI
import SwiftData

struct ScenariosSettingsView: View {
    @Query(sort: \Scenario.order) private var scenarios: [Scenario]
    @Environment(ScenarioStore.self) private var store

    @State private var isAddingScenario = false
    @State private var editingScenario: Scenario?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(scenarios) { scenario in
                    ScenarioRow(
                        scenario: scenario,
                        onEdit: { editingScenario = scenario },
                        onDelete: { store.delete(scenario) }
                    )
                }
                .onMove { source, destination in
                    store.move(from: source, to: destination, in: scenarios)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack {
                Button {
                    isAddingScenario = true
                } label: {
                    Label("Add Scenario", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(8)

                Spacer()
            }
        }
        .sheet(isPresented: $isAddingScenario) {
            ScenarioEditView(mode: .add)
                .environment(store)
        }
        .sheet(item: $editingScenario) { scenario in
            ScenarioEditView(mode: .edit(scenario))
                .environment(store)
        }
    }
}

private struct ScenarioRow: View {
    @Bindable var scenario: Scenario
    @Environment(\.modelContext) private var modelContext
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .imageScale(.small)

            Toggle("", isOn: $scenario.isEnabled)
                .labelsHidden()
                .onChange(of: scenario.isEnabled) { _, _ in
                    try? modelContext.save()
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(scenario.name)
                        .fontWeight(.medium)
                    if scenario.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(scenario.instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            Button("Edit", action: onEdit)
                .buttonStyle(.borderless)
                .foregroundStyle(.link)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
}

import SwiftUI

enum ScenarioEditMode {
    case add
    case edit(Scenario)

    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }
}

struct ScenarioEditView: View {
    let mode: ScenarioEditMode
    @Environment(ScenarioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var instruction = ""

    private var isBuiltIn: Bool {
        if case .edit(let scenario) = mode { return scenario.isBuiltIn }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !instruction.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if isBuiltIn {
                    Section {
                        LabeledContent("Type", value: "Built-in")
                    } footer: {
                        Text("Built-in scenarios cannot be deleted but can be customized.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Details") {
                    TextField("Name", text: $name)
                        .multilineTextAlignment(.leading)
                    TextField("Instruction", text: $instruction, axis: .vertical)
                        .lineLimit(5...)
                        .multilineTextAlignment(.leading)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(mode.isAdding ? "Add" : "Save") {
                    commit()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 440, height: 320)
        .onAppear {
            if case .edit(let scenario) = mode {
                name = scenario.name
                instruction = scenario.instruction
            }
        }
    }

    private func commit() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .add:
            store.addScenario(name: trimmedName, instruction: trimmedInstruction)
        case .edit(let scenario):
            scenario.name = trimmedName
            scenario.instruction = trimmedInstruction
            store.save()
        }
    }
}

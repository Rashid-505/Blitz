import SwiftUI
import SwiftData

struct HistorySettingsView: View {
    @Query(sort: \ReplacementEntry.date, order: .reverse) private var entries: [ReplacementEntry]
    @Environment(ReplacementHistoryStore.self) private var historyStore
    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Save replacement history") {
                    @Bindable var store = historyStore
                    Toggle("", isOn: $store.isHistoryEnabled)
                        .labelsHidden()
                }
            }

            Section("History") {
                if entries.isEmpty {
                    Text(historyStore.isHistoryEnabled
                         ? "No replacements recorded yet."
                         : "History collection is off.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    ForEach(entries) { entry in
                        HistoryEntryRow(entry: entry) {
                            historyStore.delete(entry)
                        }
                    }
                }
            }

            if !entries.isEmpty {
                Section {
                    Button("Clear All History", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Clear All History?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) { historyStore.clearAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All replacement history will be permanently deleted.")
        }
    }
}

// MARK: - Entry row

private struct HistoryEntryRow: View {
    let entry: ReplacementEntry
    let onDelete: () -> Void
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(entry.scenarioName)
                    .fontWeight(.medium)

                Spacer()

                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.resultText, forType: .string)
                    didCopy = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(didCopy ? .green : .secondary)
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Copy result")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Delete entry")
            }

            Text(entry.resultText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

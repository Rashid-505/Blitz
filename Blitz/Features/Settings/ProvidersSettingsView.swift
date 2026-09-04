import SwiftUI

struct ProvidersSettingsView: View {
    @Environment(ProviderStore.self) private var store
    @State private var apiKeyInput = ""
    @State private var isKeyVisible = false
    @State private var testStatus: TestStatus = .idle
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        Form {
            providerSection
            if !store.activeProviderID.availableModels.isEmpty {
                modelSection
            }
            if store.activeProviderID.requiresAPIKey {
                apiKeySection
            }
            if store.activeProviderID == .apple {
                appleStatusSection
            }
            connectionSection
        }
        .formStyle(.grouped)
        .onDisappear {
            testTask?.cancel()
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section("Provider") {
            Picker("AI Provider", selection: Binding(
                get: { store.activeProviderID },
                set: {
                    store.setActiveProvider($0)
                    testTask?.cancel()
                    resetInputState()
                }
            )) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        let providerID = store.activeProviderID
        Section("Model") {
            Picker("Model", selection: Binding(
                get: { store.activeModelID(for: providerID) },
                set: { store.setModel($0, for: providerID) }
            )) {
                ForEach(providerID.availableModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        Section("API Key") {
            HStack {
                Group {
                    if isKeyVisible {
                        TextField("Paste API key...", text: $apiKeyInput)
                    } else {
                        SecureField("Paste API key...", text: $apiKeyInput)
                    }
                }
                .textFieldStyle(.plain)

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button("Save") { saveKey() }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Clear", role: .destructive) { clearKey() }
                    .disabled(!store.hasAPIKey(for: store.activeProviderID))

                Spacer()

                if store.hasAPIKey(for: store.activeProviderID) {
                    Label("Key saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Not configured", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var appleStatusSection: some View {
        Section("Apple Intelligence") {
            let status = AppleIntelligenceCapability.status
            HStack(spacing: 10) {
                switch status {
                case .available:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Available and ready")
                case .notEnabled:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Not enabled")
                            .fontWeight(.medium)
                        Text("Enable in System Settings → Apple Intelligence & Siri")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .notEligible:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("This device does not support Apple Intelligence")
                case .modelNotReady:
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.blue)
                    Text("Model is still downloading")
                }
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            Button("Test Connection") {
                startConnectionTest()
            }
            .disabled(!store.hasAPIKey(for: store.activeProviderID) || testStatus == .running)

            switch testStatus {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65)
                    Text("Testing…").foregroundStyle(.secondary).font(.caption)
                }
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.caption)
            case .failure(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red).font(.caption)
            }
        }
    }

    private func resetInputState() {
        apiKeyInput = ""
        isKeyVisible = false
        testStatus = .idle
    }

    private func saveKey() {
        do {
            try store.storeAPIKey(apiKeyInput, for: store.activeProviderID)
            apiKeyInput = ""
        } catch {
            testStatus = .failure("Failed to save key: \(error.localizedDescription)")
        }
    }

    private func clearKey() {
        try? store.clearAPIKey(for: store.activeProviderID)
    }

    private func startConnectionTest() {
        testTask?.cancel()
        testStatus = .running
        testTask = Task { await runConnectionTest() }
    }

    private func runConnectionTest() async {
        guard let provider = store.makeProvider(for: store.activeProviderID) else {
            testStatus = .failure("No API key configured.")
            return
        }
        do {
            let result = try await provider.transform(
                text: "Hello",
                instruction: "Reply with only the word 'OK' and nothing else."
            )
            guard !Task.isCancelled else { return }
            testStatus = .success("Connected — \"\(result.prefix(60))\"")
        } catch is CancellationError {
            testStatus = .idle
        } catch let error as AIError {
            testStatus = .failure(error.localizedDescription)
        } catch {
            testStatus = .failure(error.localizedDescription)
        }
    }
}

private enum TestStatus: Equatable {
    case idle
    case running
    case success(String)
    case failure(String)
}

import SwiftUI
import SwiftData

// MARK: - Brand colors

private extension Color {
    static let blitzBlue     = Color(hex: 0x0088FF)
    static let blitzSkyBlue  = Color(hex: 0x62C1FF)
    static let blitzGradient = LinearGradient(
        colors: [.blitzBlue, .blitzSkyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - View

struct BlitzOverlayView: View {

    @Environment(ScenarioStore.self) private var scenarioStore
    @Environment(TransformationOrchestrator.self) private var orchestrator
    @Environment(ProviderStore.self) private var providerStore

    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [.blitzBlue.opacity(0.6), .blitzSkyBlue.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.blitzBlue.opacity(0.18), radius: 20, x: 0, y: 6)
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        .onExitCommand {
            if orchestrator.state.isTransforming { orchestrator.cancel() }
            onDismiss()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blitzGradient)
                    .frame(width: 24, height: 24)
                Image("lightning")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
            }

            Text("Blitz")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blitzBlue, .blitzSkyBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.blitzBlue.opacity(0.07), Color.blitzSkyBlue.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blitzBlue.opacity(0.25), Color.blitzSkyBlue.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 0.5)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch orchestrator.state {
        case .idle:
            idleContent
        case .transforming(let name):
            transformingContent(name: name)
        case .failed(let error):
            failedContent(error: error)
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            let enabled = scenarioStore.enabledScenarios
            if enabled.isEmpty {
                Text("No scenarios enabled")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            } else {
                ForEach(enabled) { scenario in
                    scenarioRow(scenario)
                }
            }

            Divider()
                .padding(.horizontal, 8)
                .padding(.top, 2)

            Button {
                onOpenSettings()
            } label: {
                Label("Manage Scenarios…", systemImage: "slider.horizontal.3")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 6)
    }

    private func scenarioRow(_ scenario: Scenario) -> some View {
        Button {
            triggerTransformation(for: scenario)
        } label: {
            Text(scenario.name)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(BlitzRowButtonStyle())
        .padding(.horizontal, 6)
    }

    // MARK: - Transforming

    private func transformingContent(name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.blitzGradient)
                        .frame(width: 28, height: 28)
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blitzBlue, .blitzSkyBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("Transforming…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Cancel") {
                orchestrator.cancel()
            }
            .buttonStyle(BlitzOutlineButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: - Failed

    private func failedContent(error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.blitzBlue)
                Text("Something went wrong")
                    .font(.callout)
                    .fontWeight(.medium)
            }
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button("Dismiss") {
                orchestrator.cancel()
                onDismiss()
            }
            .buttonStyle(BlitzOutlineButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func triggerTransformation(for scenario: Scenario) {
        guard let provider = providerStore.makeActiveProvider() else {
            onOpenSettings()
            return
        }
        orchestrator.transform(with: scenario, provider: provider)
    }
}

// MARK: - Button styles

private struct BlitzRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        configuration.isPressed
                            ? LinearGradient(
                                colors: [Color.blitzBlue.opacity(0.15), Color.blitzSkyBlue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [Color.clear, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct BlitzOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(Color.blitzBlue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.blitzBlue, Color.blitzSkyBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.blitzBlue.opacity(configuration.isPressed ? 0.1 : 0.04))
                    )
            )
    }
}

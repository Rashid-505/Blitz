import AppKit
import SwiftUI
import SwiftData

// MARK: - Keyboard navigation state

/// Tracks which row is keyboard-highlighted in the scenario list.
/// Owned by `BlitzOverlayPresenter`; injected into the view via `.environment`.
@Observable
final class OverlayNavigationState {
    var highlightedIndex: Int = 0
}

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
    @Environment(OverlayNavigationState.self) private var navigationState

    let onDismiss: () -> Void
    let onOpenSettings: () -> Void
    /// Called when the view's content changes size so the hosting panel can resize.
    let onNeedsResize: () -> Void

    @State private var revisionText: String = ""
    @FocusState private var revisionFieldFocused: Bool

    init(
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onNeedsResize: @escaping () -> Void = {}
    ) {
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.onNeedsResize = onNeedsResize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onExitCommand {
            if orchestrator.state.isTransforming {
                orchestrator.cancel()
                // If this was a revision cancel, orchestrator.cancel() restores to .preview.
                // Only dismiss if we actually went to idle (original transform cancel).
                if !orchestrator.state.isPreview { onDismiss() }
            } else {
                orchestrator.cancel()
                onDismiss()
            }
        }
        // Resize panel whenever we enter or exit preview, or revision depth changes.
        .onChange(of: orchestrator.state.isPreview) { _, isPreview in
            if isPreview { onNeedsResize() }
        }
        .onChange(of: orchestrator.revisionDepth) { _, _ in
            if orchestrator.state.isPreview { onNeedsResize() }
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
            // Dragging is handled natively by BlitzOverlayWindow.sendEvent
            // via performWindowDrag — no SwiftUI gesture needed here.
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch orchestrator.state {
        case .idle:
            idleContent
        case .transforming(let name):
            transformingContent(name: name)
        case .preview(let name, _, let result):
            previewContent(scenarioName: name, result: result)
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
                ForEach(enabled.indices, id: \.self) { index in
                    scenarioRow(enabled[index], index: index)
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
        .onAppear {
            navigationState.highlightedIndex = 0
        }
    }

    private func scenarioRow(_ scenario: Scenario, index: Int) -> some View {
        let isHighlighted = navigationState.highlightedIndex == index
        return Button {
            triggerTransformation(for: scenario)
        } label: {
            HStack(spacing: 4) {
                Group {
                    if index < 9 {
                        Text("\(index + 1)")
                            .monospacedDigit()
                    } else {
                        Color.clear
                    }
                }
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .trailing)

                Text(scenario.name)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BlitzRowButtonStyle(isHighlighted: isHighlighted))
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
                if !orchestrator.state.isPreview { onDismiss() }
            }
            .buttonStyle(BlitzOutlineButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: - Preview

    private func previewContent(scenarioName: String, result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: scenario name / revision indicator + optional Back button
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.blitzBlue)

                if orchestrator.revisionDepth > 0 {
                    Text("Revision \(orchestrator.revisionDepth)")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blitzBlue, .blitzSkyBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                } else {
                    Text(scenarioName)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blitzBlue, .blitzSkyBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                Spacer()

                if orchestrator.canGoBack {
                    Button {
                        orchestrator.back()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .imageScale(.small)
                            Text("Back")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Result text
            ScrollView {
                Text(result)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 200)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.secondary.opacity(0.15), lineWidth: 0.5)
            )

            // Revision input field
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Revise… (e.g. make it shorter)", text: $revisionText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($revisionFieldFocused)
                        .onSubmit { submitRevision() }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.secondary.opacity(0.25), lineWidth: 0.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.secondary.opacity(0.04))
                                )
                        )

                    Button("Revise") { submitRevision() }
                        .buttonStyle(BlitzOutlineButtonStyle())
                        .disabled(revisionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // Give the text field focus automatically when preview appears.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    revisionFieldFocused = true
                }
            }

            // Action row
            HStack(spacing: 8) {
                Button("Replace") {
                    orchestrator.commit()
                    onDismiss()
                }
                .buttonStyle(BlitzPrimaryButtonStyle())

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    onDismiss()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(BlitzOutlineButtonStyle())

                Spacer()

                Button("Discard") {
                    orchestrator.cancel()
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .onChange(of: orchestrator.revisionDepth) { _, _ in
            // Clear the revision field whenever we step into a new revision depth.
            revisionText = ""
        }
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

            HStack(spacing: 8) {
                if orchestrator.state.isRetryable {
                    Button("Retry") {
                        orchestrator.retryLast()
                    }
                    .buttonStyle(BlitzPrimaryButtonStyle())
                }

                Button("Dismiss") {
                    orchestrator.cancel()
                    onDismiss()
                }
                .buttonStyle(BlitzOutlineButtonStyle())
            }
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

    private func submitRevision() {
        let trimmed = revisionText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let provider = providerStore.makeActiveProvider() else {
            onOpenSettings()
            return
        }
        revisionText = ""
        orchestrator.revise(followUp: trimmed, provider: provider)
    }
}

// MARK: - Button styles

private struct BlitzRowButtonStyle: ButtonStyle {
    var isHighlighted: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        (configuration.isPressed || isHighlighted)
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

/// Gradient-filled primary action button used for the Replace action in the preview state.
private struct BlitzPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blitzBlue.opacity(configuration.isPressed ? 0.75 : 1.0),
                                Color.blitzSkyBlue.opacity(configuration.isPressed ? 0.75 : 1.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }
}

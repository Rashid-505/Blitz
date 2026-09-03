import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Injected by BlitzApp.init() so service handlers can reach the active provider.
    var providerStore: ProviderStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - NSServices handlers

    @objc func fixGrammar(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        applyService(pboard, scenarioName: "Fix Grammar")
    }

    @objc func makeFormal(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        applyService(pboard, scenarioName: "Make Formal")
    }

    @objc func makeCasual(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        applyService(pboard, scenarioName: "Make Casual")
    }

    @objc func summarize(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        applyService(pboard, scenarioName: "Summarize")
    }

    @objc func translateToEnglish(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        applyService(pboard, scenarioName: "Translate to English")
    }

    // MARK: - Private

    private func applyService(_ pboard: NSPasteboard, scenarioName: String) {
        guard
            let text = pboard.string(forType: .string),
            let provider = providerStore?.makeActiveProvider(),
            let scenario = BuiltInScenarios.all.first(where: { $0.name == scenarioName })
        else { return }

        let instruction = scenario.instruction

        // ResultHolder allows the detached task to write its result into
        // a heap-allocated container that is safely readable after the
        // semaphore signals. nonisolated(unsafe) opts out of actor isolation
        // checking; the semaphore provides the necessary memory ordering.
        final class ResultHolder: @unchecked Sendable { nonisolated(unsafe) var value: String? }
        let holder = ResultHolder()
        let semaphore = DispatchSemaphore(value: 0)

        // Task.detached runs on the cooperative thread pool — not the main actor.
        // transform() is nonisolated, so no main-actor hop occurs while the
        // main thread is blocked on semaphore.wait(), avoiding a deadlock.
        Task.detached {
            do {
                holder.value = try await provider.transform(text: text, instruction: instruction)
            } catch {}
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 30)

        guard
            let transformed = holder.value,
            !transformed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        pboard.clearContents()
        pboard.setString(transformed, forType: .string)
    }
}

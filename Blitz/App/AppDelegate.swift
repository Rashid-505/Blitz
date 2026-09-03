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
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)

        // Task.detached runs on the cooperative thread pool — it does NOT require
        // the main actor. transform() is nonisolated so it also stays off the main
        // actor. This lets the semaphore.wait() below safely block the calling
        // thread while network I/O runs on system threads.
        Task.detached {
            do {
                result = try await provider.transform(text: text, instruction: instruction)
            } catch {}
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 30)

        guard
            let transformed = result,
            !transformed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        pboard.clearContents()
        pboard.setString(transformed, forType: .string)
    }
}

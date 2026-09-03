//
//  BlitzApp.swift
//  Blitz
//
//  Created by Rashid Huseynov on 01.09.26.
//

import SwiftUI
import SwiftData

@main
struct BlitzApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let sharedContainer: ModelContainer
    private let scenarioStore: ScenarioStore

    init() {
        do {
            sharedContainer = try ModelContainer(for: Scenario.self)
        } catch {
            fatalError("SwiftData container failed to initialize: \(error)")
        }
        scenarioStore = ScenarioStore(modelContext: sharedContainer.mainContext)
    }

    var body: some Scene {
        MenuBarExtra("Blitz", systemImage: "bolt.fill") {
            MenuBarView()
                .environment(scenarioStore)
        }
        .menuBarExtraStyle(.menu)
        .modelContainer(sharedContainer)

        Settings {
            SettingsView()
                .environment(scenarioStore)
        }
        .modelContainer(sharedContainer)
    }
}

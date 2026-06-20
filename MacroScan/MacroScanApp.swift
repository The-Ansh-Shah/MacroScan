//
//  MacroScanApp.swift
//  MacroScan
//
//  Created by Ansh Shah on 4/20/26.
//

import SwiftUI
import SwiftData

@main
struct MacroScanApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Food.self,
            LogEntry.self,
            UserProfile.self,
            BodyMeasurement.self,
            WeightGoal.self,
            Recipe.self,
            RecipeIngredient.self,
            WaterEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Migration failed — most commonly when the simulator holds a store from a prior
            // schema. Wipe the default store and retry so the user doesn't have to delete the
            // app manually. Pre-release app, no durable data worth preserving across breaks.
            print("ModelContainer init failed, wiping store and retrying: \(error)")
            Self.wipeDefaultStore()
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after wipe: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }

    private static func wipeDefaultStore() {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }

        // SwiftData's default file set — remove sidecar WAL/SHM too.
        for suffix in ["", "-shm", "-wal"] {
            let url = appSupport.appendingPathComponent("default.store" + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }
}

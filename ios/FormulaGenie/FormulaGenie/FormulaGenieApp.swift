//
//  FormulaGenieApp.swift
//  FormulaGenie
//
//  Created by Huy Tran on 15/09/26.
//

import SwiftUI
import SwiftData

@main
struct FormulaGenieApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self, 
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

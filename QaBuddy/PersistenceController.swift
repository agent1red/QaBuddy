//
//  PersistenceController.swift
//  QaBuddy
//
//  Created by Kevin Hudson on 8/27/25.
//

import Foundation
import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let modelName = "QaBuddy"

        // Search in main app + any linked frameworks (useful if the model ends up in a different bundle).
        let candidateBundles: [Bundle] = [Bundle.main,
                                          Bundle(for: BundleMarker.self)] + Bundle.allFrameworks

        // Try explicit momd/mom first
        let modelURL = candidateBundles.lazy.compactMap {
            $0.url(forResource: modelName, withExtension: "momd")
            ?? $0.url(forResource: modelName, withExtension: "mom")
        }.first

        let managedObjectModel: NSManagedObjectModel

        if let url = modelURL, let model = NSManagedObjectModel(contentsOf: url) {
            managedObjectModel = model
            print("✅ Core Data: loaded explicit model '\(modelName)' from \(url.lastPathComponent)")
        } else if let merged = NSManagedObjectModel.mergedModel(from: candidateBundles) {
            managedObjectModel = merged
            print("⚠️ Core Data: explicit model '\(modelName)' not found; using merged model.")
        } else {
            fatalError("❌ Core Data: model '\(modelName)' not found in any bundle.")
        }

        container = NSPersistentContainer(name: modelName, managedObjectModel: managedObjectModel)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { desc, error in
            if let error = error {
                fatalError("Unresolved Core Data error: \(error)")
            }

            let ctx = self.container.viewContext
            ctx.automaticallyMergesChangesFromParent = true
            ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            // Visibility: list all entities so we can verify "Photo" exists at runtime.
            let names = self.container.managedObjectModel.entities.compactMap { $0.name }.sorted()
            print("✅ Core Data store loaded at: \(desc.url?.path ?? "(memory)")")
            print("✅ Entities present: \(names)")

            // Sanity check (will assert in Debug if entity missing)
            assert(self.container.managedObjectModel.entitiesByName["Photo"] != nil,
                   "Entity 'Photo' missing from model. Check the entity name/spelling.")
        }
    }
}

// Marker class so we can get a Bundle reference reliably
private final class BundleMarker {}

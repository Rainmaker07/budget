import CoreData

/// Owns the Core Data stack.
///
/// Uses `NSPersistentCloudKitContainer` from day one, with CloudKit switched
/// off for now. v0.5 turns on iCloud sync and adds a second store for
/// budgets shared with a partner — that needs a CloudKit container ID and an
/// Apple Developer team, which this version doesn't require.
final class PersistenceController {
    static let shared = PersistenceController(inMemory: LaunchOptions.isDemo)

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inMemory: use a throwaway store (demo data, previews, tests).
    ///   - storeURL: a specific SQLite file (tests); defaults to the app's store.
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentCloudKitContainer(name: "Tide", managedObjectModel: TideModel.shared)

        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            description.url = storeURL
        }
        description.cloudKitContainerOptions = nil
        for (key, value) in StoreMigrator.storeOptions {
            if let key = key as? String { description.setOption(value as? NSObject, forKey: key) }
        }
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        if !inMemory, let url = description.url {
            do {
                try StoreMigrator.migrateIfNeeded(storeAt: url)
            } catch {
                fatalError("Tide could not upgrade its data store: \(error)")
            }
        }

        container.loadPersistentStores { _, error in
            if let error {
                // A store that can't open is unrecoverable at this stage.
                fatalError("Tide could not open its data store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"
    }

    /// An in-memory store filled with demo data, for SwiftUI previews.
    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        DemoData.populate(controller.viewContext)
        return controller
    }()
}

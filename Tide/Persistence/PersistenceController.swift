import CoreData

/// Owns the Core Data stack.
///
/// Uses `NSPersistentCloudKitContainer` from day one, with CloudKit switched
/// off for now. Milestone 5 turns on iCloud sync and adds a second store for
/// budgets shared with a partner — that needs a CloudKit container ID and an
/// Apple Developer team, which this milestone doesn't require.
final class PersistenceController {
    static let shared = PersistenceController(inMemory: LaunchOptions.isDemo)

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Tide", managedObjectModel: TideModel.shared)

        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        description.cloudKitContainerOptions = nil
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

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

import CoreData

/// Upgrades an existing store to the current schema before it's opened.
///
/// Core Data can only migrate automatically when the old model is available
/// as a compiled `.momd` in the app bundle. Tide builds its models in code,
/// so this does the same "lightweight" migration by hand: find which old
/// version the store was made with, infer the mapping, migrate into a
/// temporary file, then swap it in.
enum StoreMigrator {
    enum MigrationError: LocalizedError {
        case unknownModel

        var errorDescription: String? {
            "This data was made by a newer or unknown version of Tide."
        }
    }

    /// Store options Tide always opens with. Migration must use the same ones.
    static let storeOptions: [AnyHashable: Any] = [
        NSPersistentHistoryTrackingKey: true as NSNumber,
    ]

    /// Returns true if a migration ran.
    @discardableResult
    static func migrateIfNeeded(storeAt url: URL,
                                to current: NSManagedObjectModel = TideModel.shared,
                                history: [NSManagedObjectModel] = TideModel.history) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: storeOptions
        )
        if current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
            return false
        }
        guard let source = history.first(where: { $0.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) }) else {
            throw MigrationError.unknownModel
        }

        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: source, destinationModel: current)
        let manager = NSMigrationManager(sourceModel: source, destinationModel: current)
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent("Tide-migrating-\(UUID().uuidString).sqlite")

        try manager.migrateStore(
            from: url, sourceType: NSSQLiteStoreType, options: storeOptions,
            with: mapping,
            toDestinationURL: temporaryURL, destinationType: NSSQLiteStoreType, destinationOptions: storeOptions
        )

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        try coordinator.replacePersistentStore(
            at: url, destinationOptions: storeOptions,
            withPersistentStoreFrom: temporaryURL, sourceOptions: storeOptions,
            ofType: NSSQLiteStoreType
        )
        try? coordinator.destroyPersistentStore(at: temporaryURL, ofType: NSSQLiteStoreType, options: storeOptions)
        return true
    }
}

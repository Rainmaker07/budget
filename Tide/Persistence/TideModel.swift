import CoreData

/// Tide's Core Data schema, built in code so it's easy to review in diffs.
///
/// CloudKit rules this schema follows (needed for sync and couple sharing):
/// every attribute is optional or has a default, every relationship is
/// optional with an inverse, and there are no unique constraints.
///
/// Everything hangs off `Household`, so sharing a household with a partner
/// shares the whole budget.
///
/// Versions: every schema change adds a new version here instead of editing
/// an old one. `StoreMigrator` upgrades stores from any older version.
/// - v1 (0.1.0): households, members, categories, accounts, entries, budgets, snapshots, goals
/// - v2 (0.1.1): places (shops and vendors) with logos, linked from entries
enum TideModel {
    static let currentVersion = 2

    /// The model the app runs on, bound to Tide's managed object classes.
    static let shared: NSManagedObjectModel = build(version: currentVersion, bindClasses: true)

    /// Older versions, newest first, for migrating existing stores. Not bound to
    /// classes, so they never compete with `shared` for the entity classes.
    static let history: [NSManagedObjectModel] = (1..<currentVersion).reversed().map {
        build(version: $0, bindClasses: false)
    }

    static func build(version: Int, bindClasses: Bool) -> NSManagedObjectModel {
        func entity<T: NSManagedObject>(_ name: String, _ managedClass: T.Type) -> NSEntityDescription {
            NSEntityDescription(name: name, className: bindClasses ? NSStringFromClass(managedClass) : "NSManagedObject")
        }

        let household = entity("Household", Household.self)
        household.attributes(common + [
            .string("name", default: "Our Budget"),
            .string("baseCurrency", default: "EUR"),
            .string("budgetModeRaw", default: "limits"),
        ])

        let member = entity("Member", Member.self)
        member.attributes(common + [
            .string("name", default: ""),
            .string("colorName", default: "blue"),
            .int16("sortOrder"),
        ])

        let category = entity("BudgetCategory", BudgetCategory.self)
        category.attributes(common + [
            .string("name", default: ""),
            .string("kindRaw", default: "expense"),
            .string("icon", default: "circle.fill"),
            .string("colorName", default: "blue"),
            .int16("sortOrder"),
            .bool("isHidden"),
            .bool("isPersonal"),
        ])

        let account = entity("Account", Account.self)
        account.attributes(common + [
            .string("name", default: ""),
            .string("kindRaw", default: "current"),
            .string("currencyCode", default: "EUR"),
            .string("icon", default: "building.columns.fill"),
            .string("colorName", default: "blue"),
            .decimal("openingBalance"),
            .decimal("interestRate"),
            .decimal("minimumPayment"),
            .int16("dueDay"),
            .int16("sortOrder"),
            .bool("isArchived"),
        ])

        let entry = entity("LedgerEntry", LedgerEntry.self)
        entry.attributes(common + [
            .string("kindRaw", default: "expense"),
            .date("date"),
            .string("payee"),
            .string("note"),
            .decimal("originalAmount"),
            .string("originalCurrency", default: "EUR"),
            .decimal("baseAmount"),
            .decimal("principalAmount", optionalNoDefault: true),
            .decimal("interestAmount", optionalNoDefault: true),
            .string("sourceRaw", default: "manual"),
            .string("externalID"),
            .bool("isPending"),
        ])

        let budget = entity("MonthlyBudget", MonthlyBudget.self)
        budget.attributes(common + [
            .string("monthID", default: ""),
            .decimal("amount"),
            .bool("rollsOver"),
        ])

        let snapshot = entity("BalanceSnapshot", BalanceSnapshot.self)
        snapshot.attributes(common + [
            .string("monthID", default: ""),
            .decimal("balance"),
        ])

        let goal = entity("SavingsGoal", SavingsGoal.self)
        goal.attributes(common + [
            .string("name", default: ""),
            .string("kindRaw", default: "save"),
            .string("icon", default: "star.fill"),
            .string("colorName", default: "teal"),
            .decimal("targetAmount"),
            .decimal("savedAmount"),
            .date("targetDate"),
            .int16("sortOrder"),
        ])

        // Household owns everything (cascade), so deleting or sharing it covers the whole budget.
        relate(household, "members", .toMany, .cascadeDeleteRule, member, "household", .toOne, .nullifyDeleteRule)
        relate(household, "categories", .toMany, .cascadeDeleteRule, category, "household", .toOne, .nullifyDeleteRule)
        relate(household, "accounts", .toMany, .cascadeDeleteRule, account, "household", .toOne, .nullifyDeleteRule)
        relate(household, "entries", .toMany, .cascadeDeleteRule, entry, "household", .toOne, .nullifyDeleteRule)
        relate(household, "budgets", .toMany, .cascadeDeleteRule, budget, "household", .toOne, .nullifyDeleteRule)
        relate(household, "goals", .toMany, .cascadeDeleteRule, goal, "household", .toOne, .nullifyDeleteRule)

        relate(category, "children", .toMany, .cascadeDeleteRule, category, "parent", .toOne, .nullifyDeleteRule)
        relate(category, "entries", .toMany, .nullifyDeleteRule, entry, "category", .toOne, .nullifyDeleteRule)
        relate(category, "budgets", .toMany, .cascadeDeleteRule, budget, "category", .toOne, .nullifyDeleteRule)
        relate(category, "goals", .toMany, .nullifyDeleteRule, goal, "category", .toOne, .nullifyDeleteRule)
        relate(category, "accounts", .toMany, .nullifyDeleteRule, account, "category", .toOne, .nullifyDeleteRule)

        relate(account, "entries", .toMany, .nullifyDeleteRule, entry, "account", .toOne, .nullifyDeleteRule)
        relate(account, "incomingTransfers", .toMany, .nullifyDeleteRule, entry, "toAccount", .toOne, .nullifyDeleteRule)
        relate(account, "snapshots", .toMany, .cascadeDeleteRule, snapshot, "account", .toOne, .nullifyDeleteRule)
        relate(account, "goals", .toMany, .nullifyDeleteRule, goal, "account", .toOne, .nullifyDeleteRule)

        relate(member, "paidEntries", .toMany, .nullifyDeleteRule, entry, "payer", .toOne, .nullifyDeleteRule)

        var entities = [household, member, category, account, entry, budget, snapshot, goal]

        if version >= 2 {
            let place = entity("Place", Place.self)
            place.attributes(common + [
                .string("name", default: ""),
                .string("colorName"),
                .string("emoji"),
                .string("symbol"),
                .binary("logoData"),
            ])
            relate(household, "places", .toMany, .cascadeDeleteRule, place, "household", .toOne, .nullifyDeleteRule)
            relate(place, "entries", .toMany, .nullifyDeleteRule, entry, "place", .toOne, .nullifyDeleteRule)
            entities.append(place)
        }

        let model = NSManagedObjectModel()
        model.entities = entities
        model.versionIdentifiers = ["\(version)"]
        return model
    }

    private static let common: [AttributeSpec] = [
        .uuid("id"),
        .date("createdAt"),
    ]

    private enum Cardinality { case toOne, toMany }

    private static func relate(
        _ source: NSEntityDescription, _ name: String, _ cardinality: Cardinality, _ rule: NSDeleteRule,
        _ destination: NSEntityDescription, _ inverseName: String, _ inverseCardinality: Cardinality, _ inverseRule: NSDeleteRule
    ) {
        let forward = NSRelationshipDescription()
        forward.name = name
        forward.destinationEntity = destination
        forward.minCount = 0
        forward.maxCount = cardinality == .toMany ? 0 : 1
        forward.isOptional = true
        forward.deleteRule = rule

        let inverse = NSRelationshipDescription()
        inverse.name = inverseName
        inverse.destinationEntity = source
        inverse.minCount = 0
        inverse.maxCount = inverseCardinality == .toMany ? 0 : 1
        inverse.isOptional = true
        inverse.deleteRule = inverseRule

        forward.inverseRelationship = inverse
        inverse.inverseRelationship = forward
        source.properties.append(forward)
        destination.properties.append(inverse)
    }
}

/// A compact way to declare CloudKit-friendly attributes.
struct AttributeSpec {
    let name: String
    let type: NSAttributeType
    let defaultValue: Any?

    static func string(_ name: String, default value: String? = nil) -> AttributeSpec {
        AttributeSpec(name: name, type: .stringAttributeType, defaultValue: value)
    }
    static func uuid(_ name: String) -> AttributeSpec {
        AttributeSpec(name: name, type: .UUIDAttributeType, defaultValue: nil)
    }
    static func date(_ name: String) -> AttributeSpec {
        AttributeSpec(name: name, type: .dateAttributeType, defaultValue: nil)
    }
    static func decimal(_ name: String, optionalNoDefault: Bool = false) -> AttributeSpec {
        AttributeSpec(name: name, type: .decimalAttributeType,
                      defaultValue: optionalNoDefault ? nil : NSDecimalNumber.zero)
    }
    static func int16(_ name: String) -> AttributeSpec {
        AttributeSpec(name: name, type: .integer16AttributeType, defaultValue: NSNumber(value: 0))
    }
    static func bool(_ name: String) -> AttributeSpec {
        AttributeSpec(name: name, type: .booleanAttributeType, defaultValue: NSNumber(value: false))
    }
    /// Binary data stored outside the database when large (photos).
    static func binary(_ name: String) -> AttributeSpec {
        AttributeSpec(name: name, type: .binaryDataAttributeType, defaultValue: nil)
    }
}

private extension NSEntityDescription {
    convenience init(name: String, className: String) {
        self.init()
        self.name = name
        self.managedObjectClassName = className
    }

    func attributes(_ specs: [AttributeSpec]) {
        properties += specs.map { spec in
            let attribute = NSAttributeDescription()
            attribute.name = spec.name
            attribute.attributeType = spec.type
            attribute.isOptional = true
            attribute.defaultValue = spec.defaultValue
            if spec.type == .binaryDataAttributeType {
                attribute.allowsExternalBinaryDataStorage = true
            }
            return attribute
        }
    }
}

import CoreData

/// Tide's Core Data schema, built in code so it's easy to review in diffs.
///
/// CloudKit rules this schema follows (needed for sync and couple sharing):
/// every attribute is optional or has a default, every relationship is
/// optional with an inverse, and there are no unique constraints.
///
/// Everything hangs off `Household`, so sharing a household with a partner
/// shares the whole budget.
enum TideModel {
    static let shared: NSManagedObjectModel = build()

    private static func build() -> NSManagedObjectModel {
        let household = NSEntityDescription(name: "Household", class: Household.self)
        household.attributes(common + [
            .string("name", default: "Our Budget"),
            .string("baseCurrency", default: "EUR"),
            .string("budgetModeRaw", default: "limits"),
        ])

        let member = NSEntityDescription(name: "Member", class: Member.self)
        member.attributes(common + [
            .string("name", default: ""),
            .string("colorName", default: "blue"),
            .int16("sortOrder"),
        ])

        let category = NSEntityDescription(name: "BudgetCategory", class: BudgetCategory.self)
        category.attributes(common + [
            .string("name", default: ""),
            .string("kindRaw", default: "expense"),
            .string("icon", default: "circle.fill"),
            .string("colorName", default: "blue"),
            .int16("sortOrder"),
            .bool("isHidden"),
            .bool("isPersonal"),
        ])

        let account = NSEntityDescription(name: "Account", class: Account.self)
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

        let entry = NSEntityDescription(name: "LedgerEntry", class: LedgerEntry.self)
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

        let budget = NSEntityDescription(name: "MonthlyBudget", class: MonthlyBudget.self)
        budget.attributes(common + [
            .string("monthID", default: ""),
            .decimal("amount"),
            .bool("rollsOver"),
        ])

        let snapshot = NSEntityDescription(name: "BalanceSnapshot", class: BalanceSnapshot.self)
        snapshot.attributes(common + [
            .string("monthID", default: ""),
            .decimal("balance"),
        ])

        let goal = NSEntityDescription(name: "SavingsGoal", class: SavingsGoal.self)
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
        relate(household, "members", .toMany, .cascade, member, "household", .toOne, .nullify)
        relate(household, "categories", .toMany, .cascade, category, "household", .toOne, .nullify)
        relate(household, "accounts", .toMany, .cascade, account, "household", .toOne, .nullify)
        relate(household, "entries", .toMany, .cascade, entry, "household", .toOne, .nullify)
        relate(household, "budgets", .toMany, .cascade, budget, "household", .toOne, .nullify)
        relate(household, "goals", .toMany, .cascade, goal, "household", .toOne, .nullify)

        relate(category, "children", .toMany, .cascade, category, "parent", .toOne, .nullify)
        relate(category, "entries", .toMany, .nullify, entry, "category", .toOne, .nullify)
        relate(category, "budgets", .toMany, .cascade, budget, "category", .toOne, .nullify)
        relate(category, "goals", .toMany, .nullify, goal, "category", .toOne, .nullify)
        relate(category, "accounts", .toMany, .nullify, account, "category", .toOne, .nullify)

        relate(account, "entries", .toMany, .nullify, entry, "account", .toOne, .nullify)
        relate(account, "incomingTransfers", .toMany, .nullify, entry, "toAccount", .toOne, .nullify)
        relate(account, "snapshots", .toMany, .cascade, snapshot, "account", .toOne, .nullify)
        relate(account, "goals", .toMany, .nullify, goal, "account", .toOne, .nullify)

        relate(member, "paidEntries", .toMany, .nullify, entry, "payer", .toOne, .nullify)

        let model = NSManagedObjectModel()
        model.entities = [household, member, category, account, entry, budget, snapshot, goal]
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
}

private extension NSEntityDescription {
    convenience init<T: NSManagedObject>(name: String, class managedClass: T.Type) {
        self.init()
        self.name = name
        self.managedObjectClassName = NSStringFromClass(managedClass)
    }

    func attributes(_ specs: [AttributeSpec]) {
        properties += specs.map { spec in
            let attribute = NSAttributeDescription()
            attribute.name = spec.name
            attribute.attributeType = spec.type
            attribute.isOptional = true
            attribute.defaultValue = spec.defaultValue
            return attribute
        }
    }
}

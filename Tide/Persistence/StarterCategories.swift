import CoreData
import TideKit

/// The category tree a new household starts with. Everything can be
/// renamed, hidden or extended later.
enum StarterCategories {
    struct Group {
        let name: String
        let icon: String
        let color: String
        let children: [(String, String)]
    }

    static let tree: [CategoryKind: [Group]] = [
        .income: [
            Group(name: "Salary", icon: "briefcase.fill", color: "green", children: [
                ("Salary", "briefcase.fill"), ("Bonus", "sparkles"),
            ]),
            Group(name: "Side income", icon: "hammer.fill", color: "mint", children: [
                ("Freelance", "laptopcomputer"), ("Selling things", "tag.fill"),
            ]),
            Group(name: "Other income", icon: "gift.fill", color: "teal", children: [
                ("Gifts received", "gift.fill"), ("Refunds", "arrow.uturn.backward"), ("Interest & dividends", "percent"),
            ]),
        ],
        .expense: [
            Group(name: "Home", icon: "house.fill", color: "indigo", children: [
                ("Rent", "key.fill"), ("Utilities", "bolt.fill"), ("Internet & phone", "wifi"),
                ("Insurance", "shield.fill"), ("Maintenance", "wrench.and.screwdriver.fill"),
            ]),
            Group(name: "Food", icon: "fork.knife", color: "orange", children: [
                ("Groceries", "cart.fill"), ("Restaurants", "fork.knife"), ("Coffee & snacks", "cup.and.saucer.fill"),
            ]),
            Group(name: "Transport", icon: "car.fill", color: "blue", children: [
                ("Fuel & charging", "fuelpump.fill"), ("Public transport", "tram.fill"),
                ("Car costs", "car.fill"), ("Parking", "parkingsign"),
            ]),
            Group(name: "Health", icon: "heart.fill", color: "red", children: [
                ("Pharmacy", "pills.fill"), ("Doctor", "stethoscope"), ("Fitness", "figure.run"),
            ]),
            Group(name: "Shopping", icon: "bag.fill", color: "pink", children: [
                ("Clothes", "tshirt.fill"), ("Electronics", "iphone"), ("Household", "sofa.fill"),
            ]),
            Group(name: "Fun", icon: "party.popper.fill", color: "purple", children: [
                ("Going out", "music.note"), ("Hobbies", "paintpalette.fill"), ("Subscriptions", "play.rectangle.fill"),
            ]),
            Group(name: "Travel", icon: "airplane", color: "cyan", children: [
                ("Flights & trains", "airplane"), ("Stays", "bed.double.fill"), ("Holiday spending", "sun.max.fill"),
            ]),
            Group(name: "Personal", icon: "person.fill", color: "yellow", children: [
                ("Personal care", "scissors"), ("Gifts given", "gift.fill"), ("Education", "book.fill"),
            ]),
            Group(name: "Other", icon: "ellipsis.circle.fill", color: "gray", children: [
                ("Fees & charges", "doc.text.fill"), ("Miscellaneous", "questionmark.circle.fill"),
            ]),
        ],
        .savings: [
            Group(name: "Savings", icon: "banknote.fill", color: "teal", children: [
                ("Emergency fund", "lifepreserver.fill"), ("Travel fund", "airplane"), ("Big purchases", "shippingbox.fill"),
            ]),
        ],
        .investment: [
            Group(name: "Investments", icon: "chart.line.uptrend.xyaxis", color: "green", children: [
                ("Pension", "figure.walk"), ("ETF portfolio", "chart.pie.fill"),
            ]),
        ],
        .debt: [
            Group(name: "Debts", icon: "creditcard.fill", color: "red", children: [
                ("Car loan", "car.fill"), ("Credit card", "creditcard.fill"), ("Student loan", "graduationcap.fill"),
            ]),
        ],
    ]

    /// Creates the starter tree. Returns subcategories keyed by name.
    @discardableResult
    static func install(in household: Household, context: NSManagedObjectContext) -> [String: BudgetCategory] {
        var byName: [String: BudgetCategory] = [:]
        var order: Int16 = 0
        for kind in CategoryKind.allCases {
            for group in tree[kind] ?? [] {
                let parent = BudgetCategory(context: context)
                parent.name = group.name
                parent.kindRaw = kind.rawValue
                parent.icon = group.icon
                parent.colorName = group.color
                parent.sortOrder = order
                parent.household = household
                order += 1
                byName[group.name] = parent

                for (index, child) in group.children.enumerated() {
                    let category = BudgetCategory(context: context)
                    category.name = child.0
                    category.icon = child.1
                    category.kindRaw = kind.rawValue
                    category.colorName = group.color
                    category.sortOrder = Int16(index)
                    category.parent = parent
                    category.household = household
                    // Subcategory names win lookups; "Salary" maps to the leaf.
                    byName[child.0] = category
                }
            }
        }
        return byName
    }
}

enum HouseholdBootstrap {
    /// Returns the household, creating a fresh one on first launch.
    @MainActor
    static func ensureHousehold(in context: NSManagedObjectContext) -> Household {
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchLimit = 1
        if let existing = try? context.fetch(request).first {
            return existing
        }

        let household = Household(context: context)
        household.name = "Our Budget"
        household.baseCurrency = CurrencyCode.eur.rawValue

        let me = Member(context: context)
        me.name = "Me"
        me.colorName = "blue"
        me.household = household

        let account = Account(context: context)
        account.name = "Current account"
        account.kindRaw = AccountKind.current.rawValue
        account.household = household

        StarterCategories.install(in: household, context: context)
        try? context.save()
        return household
    }
}

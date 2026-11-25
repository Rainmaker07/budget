import CoreData
import TideKit

/// Adding, editing, reordering, moving, hiding and deleting categories.
@MainActor
enum CategoryStore {
    /// Creates a category. With a parent it's a subcategory and inherits the
    /// parent's kind and color.
    @discardableResult
    static func create(name: String, kind: CategoryKind, icon: String, colorName: String,
                       parent: BudgetCategory?, household: Household, context: NSManagedObjectContext) -> BudgetCategory {
        let category = BudgetCategory(context: context)
        category.name = PlaceName.clean(name)
        category.kindRaw = (parent?.kind ?? kind).rawValue
        category.icon = icon
        category.colorName = parent?.colorName ?? colorName
        category.parent = parent
        category.household = household
        let siblings = parent?.allChildren ?? household.topCategories(kind, includeHidden: true)
        category.sortOrder = (siblings.filter { $0 != category }.map(\.sortOrder).max() ?? -1) + 1
        try? context.save()
        return category
    }

    /// Saves new sort orders for an already-reordered list of siblings.
    static func applyOrder(_ categories: [BudgetCategory], context: NSManagedObjectContext) {
        for (index, category) in categories.enumerated() where category.sortOrder != Int16(index) {
            category.sortOrder = Int16(index)
        }
        try? context.save()
    }

    /// Moves a subcategory under another top-level category of the same kind.
    static func move(_ category: BudgetCategory, to newParent: BudgetCategory, context: NSManagedObjectContext) {
        guard category.parent != nil, newParent.parent == nil, newParent.kind == category.kind, newParent != category else { return }
        category.sortOrder = (newParent.allChildren.map(\.sortOrder).max() ?? -1) + 1
        category.parent = newParent
        category.colorName = newParent.colorName
        try? context.save()
    }

    /// Recolors a top-level category and its subcategories together.
    static func setColor(_ colorName: String, for category: BudgetCategory, context: NSManagedObjectContext) {
        category.colorName = colorName
        for child in category.allChildren { child.colorName = colorName }
        try? context.save()
    }

    static func setHidden(_ hidden: Bool, _ category: BudgetCategory, context: NSManagedObjectContext) {
        category.isHidden = hidden
        try? context.save()
    }

    /// Number of transactions filed under the category or its subcategories.
    static func transactionCount(_ category: BudgetCategory) -> Int {
        category.subtree.reduce(0) { $0 + (($1.entries as? Set<LedgerEntry>)?.count ?? 0) }
    }

    /// Categories that transactions from `category` can be moved to before it
    /// is deleted: same kind, not inside the category being deleted.
    static func reassignTargets(for category: BudgetCategory) -> [BudgetCategory] {
        guard let household = category.household else { return [] }
        let excluded = Set(category.subtree.map(\.objectID))
        return household.pickableCategories([category.kind]).filter { !excluded.contains($0.objectID) }
    }

    /// Deletes a category and its subcategories. Their transactions move to
    /// `target` first; their budgets are deleted with them.
    static func delete(_ category: BudgetCategory, movingTransactionsTo target: BudgetCategory?, context: NSManagedObjectContext) {
        let tree = category.subtree
        if let target {
            for node in tree {
                for entry in (node.entries as? Set<LedgerEntry>) ?? [] {
                    entry.category = target
                }
            }
        }
        let siblingsParent = category.parent
        context.delete(category) // cascades to subcategories and their budgets
        if let siblingsParent {
            applyOrder(siblingsParent.allChildren.filter { $0 != category }, context: context)
        }
        try? context.save()
    }

    /// A curated set of SF Symbols for category and place icons.
    static let iconChoices: [String] = [
        "cart.fill", "basket.fill", "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill",
        "house.fill", "key.fill", "bolt.fill", "drop.fill", "flame.fill", "wifi",
        "phone.fill", "tv.fill", "shield.fill", "wrench.and.screwdriver.fill", "sofa.fill", "lightbulb.fill",
        "car.fill", "fuelpump.fill", "tram.fill", "bus.fill", "bicycle", "parkingsign",
        "airplane", "bed.double.fill", "suitcase.fill", "sun.max.fill", "beach.umbrella.fill", "map.fill",
        "heart.fill", "pills.fill", "stethoscope", "cross.case.fill", "figure.run", "dumbbell.fill",
        "bag.fill", "tshirt.fill", "shoe.fill", "iphone", "laptopcomputer", "headphones",
        "party.popper.fill", "music.note", "gamecontroller.fill", "film.fill", "book.fill", "paintpalette.fill",
        "play.rectangle.fill", "ticket.fill", "camera.fill", "scissors", "gift.fill", "graduationcap.fill",
        "pawprint.fill", "leaf.fill", "figure.and.child.holdinghands", "stroller.fill", "teddybear.fill", "hammer.fill",
        "briefcase.fill", "laptopcomputer.and.iphone", "tag.fill", "sparkles", "percent", "arrow.uturn.backward",
        "banknote.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill", "building.columns.fill", "lifepreserver.fill",
        "shippingbox.fill", "doc.text.fill", "ellipsis.circle.fill", "questionmark.circle.fill", "star.fill", "flag.fill",
    ]
}

import CoreData
import TideKit

/// Monthly budgets per category: set, copy, suggest, move money.
@MainActor
enum BudgetStore {
    static func budgets(for month: MonthKey, in household: Household, context: NSManagedObjectContext) -> [MonthlyBudget] {
        let request = NSFetchRequest<MonthlyBudget>(entityName: "MonthlyBudget")
        request.predicate = NSPredicate(format: "household == %@ AND monthID == %@", household, month.id)
        return (try? context.fetch(request)) ?? []
    }

    static func budget(for category: BudgetCategory, month: MonthKey, context: NSManagedObjectContext) -> MonthlyBudget? {
        let request = NSFetchRequest<MonthlyBudget>(entityName: "MonthlyBudget")
        request.predicate = NSPredicate(format: "category == %@ AND monthID == %@", category, month.id)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    /// Sets (or with 0 and no rollover, removes) a category's budget for a month.
    static func setBudget(_ amount: Decimal, rollsOver: Bool, for category: BudgetCategory, month: MonthKey,
                          context: NSManagedObjectContext, save: Bool = true) {
        let existing = budget(for: category, month: month, context: context)
        if amount <= 0, !rollsOver {
            if let existing { context.delete(existing) }
        } else {
            let budget = existing ?? MonthlyBudget(context: context)
            budget.monthID = month.id
            budget.amount = max(0, amount).number
            budget.rollsOver = rollsOver
            budget.category = category
            budget.household = category.household
        }
        if save { try? context.save() }
    }

    /// Copies last month's budgets into `month` for categories that don't have
    /// one yet. Returns how many were added.
    @discardableResult
    static func copyPreviousMonth(into month: MonthKey, household: Household, context: NSManagedObjectContext) -> Int {
        let existing = Set(budgets(for: month, in: household, context: context).compactMap { $0.category?.objectID })
        var added = 0
        for previous in budgets(for: month.previous, in: household, context: context) {
            guard let category = previous.category, !existing.contains(category.objectID), !category.isEffectivelyHidden else { continue }
            setBudget(previous.value, rollsOver: previous.rollsOver, for: category, month: month, context: context, save: false)
            added += 1
        }
        try? context.save()
        return added
    }

    /// Sets budgets from the average of the last `months` months of activity,
    /// for budgetable categories without a budget yet. Returns how many were set.
    @discardableResult
    static func fillWithAverages(_ month: MonthKey, months: Int = 3, household: Household, context: NSManagedObjectContext) -> Int {
        let existing = Set(budgets(for: month, in: household, context: context).compactMap { $0.category?.objectID })
        let history = monthlyActuals(before: month, months: months, household: household, context: context)
        var added = 0
        for category in budgetableCategories(household) where !existing.contains(category.objectID) {
            let amounts = (1...months).map { history[month.adding(months: -$0)]?[category.objectID] ?? 0 }
            let average = BudgetSuggestion.average(amounts)
            guard average > 0 else { continue }
            setBudget(average, rollsOver: false, for: category, month: month, context: context, save: false)
            added += 1
        }
        try? context.save()
        return added
    }

    static func clear(_ month: MonthKey, household: Household, context: NSManagedObjectContext) {
        budgets(for: month, in: household, context: context).forEach(context.delete)
        try? context.save()
    }

    /// Moves budgeted money from one category to another in the same month.
    static func move(_ amount: Decimal, from source: BudgetCategory, to target: BudgetCategory, month: MonthKey,
                     context: NSManagedObjectContext) {
        guard amount > 0, source != target else { return }
        let sourceBudget = budget(for: source, month: month, context: context)
        let targetBudget = budget(for: target, month: month, context: context)
        setBudget((sourceBudget?.value ?? 0) - amount, rollsOver: sourceBudget?.rollsOver ?? false,
                  for: source, month: month, context: context, save: false)
        setBudget((targetBudget?.value ?? 0) + amount, rollsOver: targetBudget?.rollsOver ?? false,
                  for: target, month: month, context: context, save: false)
        try? context.save()
    }

    /// Categories that take a budget: subcategories, or top-level categories
    /// without subcategories, for expenses, savings, investments and debts.
    static func budgetableCategories(_ household: Household) -> [BudgetCategory] {
        household.pickableCategories(CategoryKind.assignable)
    }

    /// Actual amounts per month per category (positive), for `months` months
    /// before `month`.
    static func monthlyActuals(before month: MonthKey, months: Int, household: Household,
                               context: NSManagedObjectContext) -> [MonthKey: [NSManagedObjectID: Decimal]] {
        let start = month.adding(months: -months).firstDay()
        let end = month.firstDay()
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "household == %@ AND date >= %@ AND date < %@ AND isPending == NO",
                                        household, start as NSDate, end as NSDate)
        var result: [MonthKey: [NSManagedObjectID: Decimal]] = [:]
        for entry in (try? context.fetch(request)) ?? [] {
            guard let date = entry.date, let category = entry.category else { continue }
            result[MonthKey(date: date), default: [:]][category.objectID, default: 0] += entry.base
        }
        return result
    }

    /// Average monthly actual for one category over the last `months` months.
    static func average(for category: BudgetCategory, before month: MonthKey, months: Int = 3,
                        context: NSManagedObjectContext) -> Decimal {
        guard let household = category.household else { return 0 }
        let history = monthlyActuals(before: month, months: months, household: household, context: context)
        return BudgetSuggestion.average((1...months).map { history[month.adding(months: -$0)]?[category.objectID] ?? 0 })
    }

    /// What a category had last month.
    static func lastMonthActual(for category: BudgetCategory, before month: MonthKey, context: NSManagedObjectContext) -> Decimal {
        guard let household = category.household else { return 0 }
        return monthlyActuals(before: month, months: 1, household: household, context: context)[month.previous]?[category.objectID] ?? 0
    }
}

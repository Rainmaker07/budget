import CoreData
import TideKit

/// Everything the Home screen needs for one month, computed in one pass.
struct MonthSnapshot {
    struct CategoryProgress: Identifiable {
        let category: BudgetCategory
        let line: CategoryBudgetLine
        var id: NSManagedObjectID { category.objectID }
    }

    var month: MonthKey
    var summary: MonthSummary
    /// Top-level expense categories that have a budget or spending.
    var expenseCategories: [CategoryProgress]
    /// Top-level savings, investment and debt categories.
    var transferCategories: [CategoryProgress]
    var recentEntries: [LedgerEntry]
    var goals: [SavingsGoal]

    @MainActor
    static func build(for month: MonthKey, household: Household, context: NSManagedObjectContext,
                      now: Date = .now, calendar: Calendar = .current) -> MonthSnapshot {
        let range = month.interval(calendar: calendar)

        let entryRequest = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        entryRequest.predicate = NSPredicate(format: "household == %@ AND date >= %@ AND date < %@",
                                             household, range.start as NSDate, range.end as NSDate)
        entryRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let entries = (try? context.fetch(entryRequest)) ?? []

        let budgetRequest = NSFetchRequest<MonthlyBudget>(entityName: "MonthlyBudget")
        budgetRequest.predicate = NSPredicate(format: "household == %@ AND monthID == %@", household, month.id)
        let budgets = (try? context.fetch(budgetRequest)) ?? []

        // Budget and actual per category, before rolling up.
        var budgeted: [NSManagedObjectID: Decimal] = [:]
        for budget in budgets {
            guard let category = budget.category else { continue }
            budgeted[category.objectID, default: 0] += budget.value
        }
        var actual: [NSManagedObjectID: Decimal] = [:]
        var income: Decimal = 0
        for entry in entries where !entry.isPending {
            if entry.kind == .income { income += entry.base }
            guard let category = entry.category else { continue }
            actual[category.objectID, default: 0] += entry.base
        }

        func progress(for top: BudgetCategory) -> CategoryProgress {
            let tree = top.subtree
            let budget = tree.reduce(Decimal(0)) { $0 + (budgeted[$1.objectID] ?? 0) }
            let spent = tree.reduce(Decimal(0)) { $0 + (actual[$1.objectID] ?? 0) }
            return CategoryProgress(category: top, line: CategoryBudgetLine(kind: top.kind, budgeted: budget, actual: spent))
        }

        // Hidden categories still count: hiding only removes them from pickers.
        let expenseTops = household.topCategories(.expense, includeHidden: true).map(progress)
        let transferTops = [CategoryKind.savings, .investment, .debt]
            .flatMap { household.topCategories($0, includeHidden: true) }
            .map(progress)

        let lines = (expenseTops + transferTops).map(\.line)
        let summary = BudgetEngine.summarize(
            mode: household.budgetMode,
            lines: lines,
            incomeReceived: income,
            monthProgress: month.progress(at: now, calendar: calendar),
            daysRemaining: month.daysRemaining(from: now, calendar: calendar)
        )

        let isActive: (CategoryProgress) -> Bool = {
            $0.line.actual > 0 || ($0.line.budgeted > 0 && !$0.category.isHidden)
        }
        return MonthSnapshot(
            month: month,
            summary: summary,
            expenseCategories: expenseTops.filter(isActive),
            transferCategories: transferTops.filter(isActive),
            recentEntries: Array(entries.prefix(6)),
            goals: household.goalList
        )
    }
}

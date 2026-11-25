import CoreData
import TideKit

/// Everything Home and Plan need for one month, computed in one pass.
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
    /// Every category's own line (not rolled up), for the Plan tab.
    var lines: [NSManagedObjectID: CategoryBudgetLine]
    /// Budgets that roll over, by category.
    var rollsOver: Set<NSManagedObjectID>
    var recentEntries: [LedgerEntry]
    /// Recurring items waiting for confirmation (due up to now).
    var pendingEntries: [LedgerEntry]
    var goals: [SavingsGoal]

    /// How many months back carry-over is followed.
    static let rolloverHistory = 12

    @MainActor
    static func build(for month: MonthKey, household: Household, context: NSManagedObjectContext,
                      now: Date = .now, calendar: Calendar = .current) -> MonthSnapshot {
        let range = month.interval(calendar: calendar)

        let entryRequest = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        entryRequest.predicate = NSPredicate(format: "household == %@ AND date >= %@ AND date < %@",
                                             household, range.start as NSDate, range.end as NSDate)
        entryRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let entries = (try? context.fetch(entryRequest)) ?? []

        let budgets = BudgetStore.budgets(for: month, in: household, context: context)

        // Budget and actual per category, before rolling up.
        var budgeted: [NSManagedObjectID: Decimal] = [:]
        var rollsOver = Set<NSManagedObjectID>()
        for budget in budgets {
            guard let category = budget.category else { continue }
            budgeted[category.objectID, default: 0] += budget.value
            if budget.rollsOver { rollsOver.insert(category.objectID) }
        }
        var actual: [NSManagedObjectID: Decimal] = [:]
        var income: Decimal = 0
        for entry in entries where !entry.isPending {
            if entry.kind == .income { income += entry.base }
            guard let category = entry.category else { continue }
            actual[category.objectID, default: 0] += entry.base
        }

        let carryover = carryovers(into: month, household: household, context: context)

        var lines: [NSManagedObjectID: CategoryBudgetLine] = [:]
        for category in household.categoryList where category.kind != .income {
            let id = category.objectID
            lines[id] = CategoryBudgetLine(kind: category.kind, budgeted: budgeted[id] ?? 0,
                                           actual: actual[id] ?? 0, carryover: carryover[id] ?? 0)
        }

        func progress(for top: BudgetCategory) -> CategoryProgress {
            let tree = top.subtree.compactMap { lines[$0.objectID] }
            let line = CategoryBudgetLine(
                kind: top.kind,
                budgeted: tree.reduce(Decimal(0)) { $0 + $1.budgeted },
                actual: tree.reduce(Decimal(0)) { $0 + $1.actual },
                carryover: tree.reduce(Decimal(0)) { $0 + $1.carryover }
            )
            return CategoryProgress(category: top, line: line)
        }

        // Hidden categories still count: hiding only removes them from pickers.
        let expenseTops = household.topCategories(.expense, includeHidden: true).map(progress)
        let transferTops = [CategoryKind.savings, .investment, .debt]
            .flatMap { household.topCategories($0, includeHidden: true) }
            .map(progress)

        let isCurrentMonth = range.contains(now)
        let upcoming = isCurrentMonth
            ? RecurringStore.upcomingExpenses(in: month, household: household, context: context, now: now)
            : 0

        let summary = BudgetEngine.summarize(
            mode: household.budgetMode,
            lines: (expenseTops + transferTops).map(\.line),
            incomeReceived: income,
            unassignedCarryIn: unassignedCarryIn(before: month, household: household, context: context),
            upcomingBills: upcoming,
            monthProgress: month.progress(at: now, calendar: calendar),
            daysRemaining: month.daysRemaining(from: now, calendar: calendar)
        )

        let isActive: (CategoryProgress) -> Bool = {
            $0.line.actual > 0 || ($0.line.available != 0 && !$0.category.isHidden)
        }
        return MonthSnapshot(
            month: month,
            summary: summary,
            expenseCategories: expenseTops.filter(isActive),
            transferCategories: transferTops.filter(isActive),
            lines: lines,
            rollsOver: rollsOver,
            recentEntries: Array(entries.filter { !$0.isPending }.prefix(6)),
            pendingEntries: RecurringStore.pending(in: household, context: context).filter { ($0.date ?? .distantFuture) <= now },
            goals: household.goalList
        )
    }

    /// Money carried into `month` per category from budgets that roll over.
    @MainActor
    private static func carryovers(into month: MonthKey, household: Household,
                                   context: NSManagedObjectContext) -> [NSManagedObjectID: Decimal] {
        let first = month.adding(months: -rolloverHistory)
        let request = NSFetchRequest<MonthlyBudget>(entityName: "MonthlyBudget")
        request.predicate = NSPredicate(format: "household == %@ AND monthID >= %@ AND monthID < %@",
                                        household, first.id, month.id)
        let past = (try? context.fetch(request)) ?? []
        // Only categories that rolled over last month can carry anything in.
        let candidates = Set(past.filter { $0.rollsOver && $0.monthID == month.previous.id }.compactMap { $0.category?.objectID })
        guard !candidates.isEmpty else { return [:] }

        var budgetsByMonth: [String: [NSManagedObjectID: MonthlyBudget]] = [:]
        for budget in past {
            guard let id = budget.category?.objectID, candidates.contains(id), let monthID = budget.monthID else { continue }
            budgetsByMonth[monthID, default: [:]][id] = budget
        }
        let actuals = BudgetStore.monthlyActuals(before: month, months: rolloverHistory, household: household, context: context)

        var result: [NSManagedObjectID: Decimal] = [:]
        for id in candidates {
            let history = (1...rolloverHistory).reversed().map { offset -> MonthFlow in
                let key = month.adding(months: -offset)
                let budget = budgetsByMonth[key.id]?[id]
                return MonthFlow(budgeted: budget?.value ?? 0, actual: actuals[key]?[id] ?? 0,
                                 rollsOver: budget?.rollsOver ?? false)
            }
            result[id] = Rollover.carryover(after: history)
        }
        return result
    }

    /// Every Euro: income received before `month` minus everything assigned before it.
    @MainActor
    private static func unassignedCarryIn(before month: MonthKey, household: Household,
                                          context: NSManagedObjectContext) -> Decimal {
        guard household.budgetMode == .everyDollar else { return 0 }
        let incomeRequest = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        incomeRequest.predicate = NSPredicate(format: "household == %@ AND kindRaw == %@ AND isPending == NO AND date < %@",
                                              household, EntryKind.income.rawValue, month.firstDay() as NSDate)
        let incomeBefore = ((try? context.fetch(incomeRequest)) ?? []).reduce(Decimal(0)) { $0 + $1.base }

        let budgetRequest = NSFetchRequest<MonthlyBudget>(entityName: "MonthlyBudget")
        budgetRequest.predicate = NSPredicate(format: "household == %@ AND monthID < %@", household, month.id)
        let assignedBefore = ((try? context.fetch(budgetRequest)) ?? [])
            .filter { budget in budget.category.map { CategoryKind.assignable.contains($0.kind) } ?? false }
            .reduce(Decimal(0)) { $0 + $1.value }

        return EveryEuro.unassignedCarryIn(incomeBefore: incomeBefore, assignedBefore: assignedBefore)
    }
}

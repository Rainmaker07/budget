import CoreData
import TideKit

/// Goal progress: a starting amount plus money moved into the goal's
/// category since the goal was created.
@MainActor
enum GoalStore {
    static func progress(for goal: SavingsGoal, now: Date = .now) -> GoalProgress {
        GoalProgress(target: target(for: goal), saved: saved(for: goal),
                     start: goal.createdAt ?? now, deadline: goal.targetDate)
    }

    /// For emergency funds with a number of months, the target follows your
    /// average monthly spending; otherwise it's the amount you set.
    static func target(for goal: SavingsGoal) -> Decimal {
        if goal.kind == .emergency, goal.targetMonths > 0, let household = goal.household,
           let context = goal.managedObjectContext {
            let monthly = averageMonthlyExpenses(household, context: context)
            if monthly > 0 { return (monthly * Decimal(Int(goal.targetMonths))).rounded(scale: -2, mode: .up) }
        }
        return goal.target
    }

    static func saved(for goal: SavingsGoal) -> Decimal {
        var total = goal.saved
        guard let category = goal.category else { return total }
        let since = goal.createdAt ?? .distantPast
        for node in category.subtree {
            for entry in (node.entries as? Set<LedgerEntry>) ?? [] where !entry.isPending && entry.kind == .transfer {
                if let date = entry.date, date >= since { total += entry.base }
            }
        }
        return total
    }

    /// Average monthly expenses over the last 3 full months (falls back to
    /// this month so far if there's no history yet).
    static func averageMonthlyExpenses(_ household: Household, context: NSManagedObjectContext, now: Date = .now) -> Decimal {
        let month = MonthKey(date: now)
        let history = BudgetStore.monthlyActuals(before: month, months: 3, household: household, context: context)
        let expenseIDs = Set(household.categoryList.filter { $0.kind == .expense }.map(\.objectID))
        let totals = (1...3).map { offset -> Decimal in
            (history[month.adding(months: -offset)] ?? [:])
                .filter { expenseIDs.contains($0.key) }
                .reduce(Decimal(0)) { $0 + $1.value }
        }
        let nonEmpty = totals.filter { $0 > 0 }
        if !nonEmpty.isEmpty { return BudgetSuggestion.average(nonEmpty) }
        let current = BudgetStore.monthlyActuals(before: month.next, months: 1, household: household, context: context)[month] ?? [:]
        return current.filter { expenseIDs.contains($0.key) }.reduce(Decimal(0)) { $0 + $1.value }
    }
}

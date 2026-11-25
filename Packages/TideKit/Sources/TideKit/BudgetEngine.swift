import Foundation

/// One category's budget for a month, in the household's base currency.
/// All amounts are positive: `actual` is money spent (expenses), received
/// (income), or moved (savings, investments, debt payments).
public struct CategoryBudgetLine: Hashable, Sendable {
    public var kind: CategoryKind
    public var budgeted: Decimal
    public var carryover: Decimal
    public var actual: Decimal

    public init(kind: CategoryKind, budgeted: Decimal, actual: Decimal, carryover: Decimal = 0) {
        self.kind = kind
        self.budgeted = budgeted
        self.actual = actual
        self.carryover = carryover
    }

    /// Budget plus anything carried over from last month.
    public var available: Decimal { budgeted + carryover }

    /// What's left. Negative means overspent.
    public var remaining: Decimal { available - actual }

    /// Whether this category has any money budgeted this month.
    public var isBudgeted: Bool { available > 0 }

    /// Fraction of the available budget used. Can exceed 1.
    /// Zero for unbudgeted categories, which have nothing to measure against.
    public var progress: Double {
        isBudgeted ? (actual / available).doubleValue : 0
    }

    public var status: BudgetStatus {
        guard isBudgeted else { return actual > 0 ? .unbudgeted : .onTrack }
        if actual > available { return .over }
        if progress >= BudgetStatus.nearLimitThreshold { return .nearLimit }
        return .onTrack
    }
}

public enum BudgetStatus: Sendable {
    case onTrack
    case nearLimit
    case over
    /// Money spent in a category with no budget. Never counts as "over".
    case unbudgeted

    public static let nearLimitThreshold = 0.85
}

/// The overall mood of the month. Drives the background tint.
public enum BudgetHealth: String, Sendable, CaseIterable {
    /// On track (cool blue-teal).
    case calm
    /// Spending faster than the month is passing (amber).
    case watch
    /// Over budget, or more money assigned than received (coral).
    case over
}

public struct MonthSummary: Hashable, Sendable {
    public var mode: BudgetMode
    /// Safe to spend (Limits) or ready to assign (Every Euro).
    public var headline: Decimal
    public var incomeReceived: Decimal
    public var expenseBudgeted: Decimal
    public var expenseSpent: Decimal
    /// Everything assigned across expenses, savings, investments and debts.
    public var totalAssigned: Decimal
    /// Money moved to savings, investments and debt payments.
    public var totalTransferred: Decimal
    public var upcomingBills: Decimal
    public var health: BudgetHealth
    /// Headline spread over the remaining days (Limits mode), else nil.
    public var dailyAllowance: Decimal?

    /// Whether any expense budget exists this month. In Limits mode without
    /// budgets, Tide shows what was spent instead of "safe to spend".
    public var hasExpenseBudget: Bool { expenseBudgeted > 0 }

    /// Fraction of the expense budget spent, 0...1+.
    public var spentFraction: Double {
        expenseBudgeted > 0 ? (expenseSpent / expenseBudgeted).doubleValue : 0
    }

    public var headlineTitle: String {
        switch mode {
        case .limits where !hasExpenseBudget: "Spent this month"
        case .limits: headline >= 0 ? "Safe to spend" : "Over budget"
        case .everyDollar: headline >= 0 ? "Ready to assign" : "Over-assigned"
        }
    }

    public static func empty(mode: BudgetMode) -> MonthSummary {
        MonthSummary(mode: mode, headline: 0, incomeReceived: 0, expenseBudgeted: 0, expenseSpent: 0,
                     totalAssigned: 0, totalTransferred: 0, upcomingBills: 0, health: .calm, dailyAllowance: nil)
    }
}

public enum BudgetEngine {
    /// Allowed lead of spending over time before the month turns amber.
    public static let paceTolerance = 0.10

    /// Summarizes a month.
    /// - Parameters:
    ///   - lines: one line per budgeted category (leaf or roll-up, but not both).
    ///   - unassignedCarryIn: Every Euro mode, money left unassigned last month.
    ///   - upcomingBills: Limits mode, bills still due this month.
    ///   - monthProgress: how far through the month we are, 0...1.
    ///   - daysRemaining: days left in the month including today.
    public static func summarize(
        mode: BudgetMode,
        lines: [CategoryBudgetLine],
        incomeReceived: Decimal,
        unassignedCarryIn: Decimal = 0,
        upcomingBills: Decimal = 0,
        monthProgress: Double,
        daysRemaining: Int
    ) -> MonthSummary {
        let expenses = lines.filter { $0.kind == .expense }
        let expenseBudgeted = expenses.reduce(Decimal(0)) { $0 + $1.available }
        let expenseSpent = expenses.reduce(Decimal(0)) { $0 + $1.actual }
        let assigned = lines.filter { CategoryKind.assignable.contains($0.kind) }
            .reduce(Decimal(0)) { $0 + $1.budgeted }
        let transferred = lines.filter { $0.kind.isBalanceBacked }
            .reduce(Decimal(0)) { $0 + $1.actual }

        let headline: Decimal
        var daily: Decimal?
        switch mode {
        case .limits where expenseBudgeted == 0:
            // Nothing budgeted yet: show spending, never a negative "safe to spend".
            headline = expenseSpent
        case .limits:
            headline = expenseBudgeted - expenseSpent - upcomingBills
            if daysRemaining > 0, headline > 0 {
                daily = (headline / Decimal(daysRemaining)).rounded(scale: 2)
            }
        case .everyDollar:
            headline = incomeReceived + unassignedCarryIn - assigned
        }

        let health: BudgetHealth
        if mode == .limits, expenseBudgeted == 0 {
            health = .calm
        } else if headline < 0 {
            health = .over
        } else if mode == .limits, expenseBudgeted > 0 {
            let spent = (expenseSpent / expenseBudgeted).doubleValue
            health = spent > monthProgress + paceTolerance ? .watch : .calm
        } else if expenses.contains(where: { $0.status == .over }) {
            health = .watch
        } else {
            health = .calm
        }

        return MonthSummary(
            mode: mode,
            headline: headline,
            incomeReceived: incomeReceived,
            expenseBudgeted: expenseBudgeted,
            expenseSpent: expenseSpent,
            totalAssigned: assigned,
            totalTransferred: transferred,
            upcomingBills: upcomingBills,
            health: health,
            dailyAllowance: daily
        )
    }
}

import Foundation

/// One past month for a category, for carry-over.
public struct MonthFlow: Hashable, Sendable {
    public var budgeted: Decimal
    public var actual: Decimal
    /// Whether this month's leftover (or overspending) moves to the next month.
    public var rollsOver: Bool

    public init(budgeted: Decimal, actual: Decimal, rollsOver: Bool) {
        self.budgeted = budgeted
        self.actual = actual
        self.rollsOver = rollsOver
    }
}

public enum Rollover {
    /// Money carried into the month after `history` (oldest first).
    ///
    /// A month that rolls over passes on what it had left — its budget plus
    /// anything carried into it, minus what was spent. Overspending carries
    /// too, as a negative amount. A month that doesn't roll over starts the
    /// chain again from zero.
    public static func carryover(after history: [MonthFlow]) -> Decimal {
        var carry: Decimal = 0
        for month in history {
            carry = month.rollsOver ? month.budgeted + carry - month.actual : 0
        }
        return carry
    }
}

public enum EveryEuro {
    /// Money received but never assigned in earlier months (negative if more
    /// was assigned than received). It's available to assign this month.
    public static func unassignedCarryIn(incomeBefore: Decimal, assignedBefore: Decimal) -> Decimal {
        incomeBefore - assignedBefore
    }
}

/// Budget suggestions from past spending.
public enum BudgetSuggestion {
    /// The average of the given monthly amounts, rounded up to whole units.
    /// Months with no spending count, so a yearly expense is spread out.
    public static func average(_ monthly: [Decimal]) -> Decimal {
        guard !monthly.isEmpty else { return 0 }
        let total = monthly.reduce(Decimal(0), +)
        return (total / Decimal(monthly.count)).rounded(scale: 0, mode: .up)
    }
}

/// Progress and pace for a savings or payoff goal.
public struct GoalProgress: Hashable, Sendable {
    public var target: Decimal
    public var saved: Decimal
    public var start: Date
    public var deadline: Date?

    public init(target: Decimal, saved: Decimal, start: Date, deadline: Date?) {
        self.target = target
        self.saved = saved
        self.start = start
        self.deadline = deadline
    }

    public var remaining: Decimal { max(0, target - saved) }
    public var isComplete: Bool { target > 0 && saved >= target }

    public var fraction: Double {
        target > 0 ? min(1, max(0, (saved / target).doubleValue)) : 0
    }

    /// Months left until the deadline, counting the current month (min 1).
    public func monthsLeft(from date: Date, calendar: Calendar = .current) -> Int? {
        guard let deadline else { return nil }
        let from = MonthKey(date: date, calendar: calendar)
        let to = MonthKey(date: deadline, calendar: calendar)
        let months = (to.year - from.year) * 12 + (to.month - from.month) + 1
        return max(1, months)
    }

    /// What needs to go in each month to finish on time (whole units).
    public func monthlyNeeded(from date: Date, calendar: Calendar = .current) -> Decimal? {
        guard !isComplete, let months = monthsLeft(from: date, calendar: calendar) else { return nil }
        return (remaining / Decimal(months)).rounded(scale: 0, mode: .up)
    }

    public enum Pace: Sendable { case done, ahead, onPace, behind, noDeadline }

    /// Compares progress with a straight line from start to deadline.
    public func pace(at date: Date, tolerance: Double = 0.05) -> Pace {
        if isComplete { return .done }
        guard let deadline, deadline > start else { return .noDeadline }
        let elapsed = min(1, max(0, date.timeIntervalSince(start) / deadline.timeIntervalSince(start)))
        if fraction > elapsed + tolerance { return .ahead }
        if fraction >= elapsed - tolerance { return .onPace }
        return .behind
    }
}

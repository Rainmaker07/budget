import CoreData
import TideKit

/// Recurring items (salary, rent, subscriptions): posting what's due and
/// forecasting what's still to come this month.
@MainActor
enum RecurringStore {
    static func all(in household: Household, context: NSManagedObjectContext) -> [RecurringRule] {
        let request = NSFetchRequest<RecurringRule>(entityName: "RecurringRule")
        request.predicate = NSPredicate(format: "household == %@", household)
        return ((try? context.fetch(request)) ?? []).sorted {
            ($0.nextDate ?? .distantFuture, $0.displayName) < ($1.nextDate ?? .distantFuture, $1.displayName)
        }
    }

    /// Creates the transactions for every occurrence that's due up to `now`.
    /// Items set to post automatically become normal transactions; the rest
    /// are added as pending, waiting for you to confirm. Safe to call often.
    @discardableResult
    static func postDue(in household: Household, context: NSManagedObjectContext, now: Date = .now) -> Int {
        var created = 0
        for rule in all(in: household, context: context) where !rule.isPaused {
            guard let recurrence = rule.recurrence else { continue }
            let from = rule.nextDate ?? recurrence.start
            let dates = recurrence.occurrences(from: from, through: now)
            for date in dates {
                makeEntry(for: rule, on: date, context: context)
                created += 1
            }
            if let last = dates.last {
                rule.nextDate = recurrence.next(after: last)
            } else if rule.nextDate == nil {
                rule.nextDate = recurrence.next(after: now) ?? recurrence.start
            }
        }
        if context.hasChanges { try? context.save() }
        return created
    }

    @discardableResult
    static func makeEntry(for rule: RecurringRule, on date: Date, context: NSManagedObjectContext) -> LedgerEntry {
        let entry = LedgerEntry(context: context)
        entry.kind = rule.kind
        entry.date = date
        entry.baseAmount = rule.amount
        entry.originalAmount = rule.amount
        entry.originalCurrency = rule.household?.currency.rawValue ?? "EUR"
        entry.category = rule.category
        entry.account = rule.account
        entry.payer = rule.payer
        entry.place = rule.place
        entry.payee = rule.place?.name
        entry.note = rule.note
        entry.household = rule.household
        entry.recurringRule = rule
        entry.isPending = !rule.autoPost
        entry.sourceRaw = EntrySource.manual.rawValue
        if rule.kind == .transfer, let category = rule.category {
            entry.toAccount = (category.accounts as? Set<Account>)?.first ?? (category.parent?.accounts as? Set<Account>)?.first
        }
        return entry
    }

    /// Transactions created by recurring items that wait for confirmation.
    static func pending(in household: Household, context: NSManagedObjectContext) -> [LedgerEntry] {
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "household == %@ AND isPending == YES", household)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    static func confirm(_ entry: LedgerEntry, context: NSManagedObjectContext) {
        entry.isPending = false
        try? context.save()
    }

    /// Skips a pending occurrence (deletes it; the schedule moves on).
    static func skip(_ entry: LedgerEntry, context: NSManagedObjectContext) {
        context.delete(entry)
        try? context.save()
    }

    /// Expense amounts still expected in the rest of `month`: pending
    /// confirmations plus scheduled occurrences after `now`.
    static func upcomingExpenses(in month: MonthKey, household: Household, context: NSManagedObjectContext,
                                 now: Date = .now) -> Decimal {
        let range = month.interval()
        guard now < range.end else { return 0 }
        var total: Decimal = 0
        for entry in pending(in: household, context: context) where entry.kind == .expense {
            if let date = entry.date, range.contains(date) { total += entry.base }
        }
        for rule in all(in: household, context: context) where !rule.isPaused && rule.kind == .expense {
            guard let recurrence = rule.recurrence else { continue }
            let from = max(range.start, now, rule.nextDate ?? recurrence.start)
            let dates = recurrence.occurrences(from: from, through: range.end.addingTimeInterval(-1))
            total += rule.value * Decimal(dates.filter { $0 > now }.count)
        }
        return total
    }

    /// Creates a recurring item from an existing transaction (its date is the
    /// first occurrence; the next one is scheduled after it).
    @discardableResult
    static func makeRule(from entry: LedgerEntry, cadence: Cadence = .monthly, autoPost: Bool = true,
                         context: NSManagedObjectContext) -> RecurringRule {
        let rule = RecurringRule(context: context)
        rule.name = entry.placeName ?? entry.category?.displayName
        rule.kind = entry.kind
        rule.amount = entry.baseAmount
        rule.currencyCode = entry.household?.currency.rawValue
        rule.cadence = cadence
        rule.interval = 1
        rule.startDate = entry.date ?? .now
        rule.category = entry.category
        rule.account = entry.account
        rule.payer = entry.payer
        rule.place = entry.place
        rule.autoPost = autoPost
        rule.household = entry.household
        entry.recurringRule = rule
        rule.nextDate = rule.recurrence?.next(after: entry.date ?? .now)
        try? context.save()
        return rule
    }
}

import CoreData
import Observation
import SwiftUI
import TideKit

/// App-wide state: the household, the month being viewed, and that month's
/// computed snapshot. Recomputes whenever the data changes.
@MainActor
@Observable
final class AppModel {
    let context: NSManagedObjectContext
    private(set) var household: Household
    private(set) var snapshot: MonthSnapshot
    var month: MonthKey {
        didSet { refresh() }
    }
    /// The selected tab, so screens can send you elsewhere (e.g. Home → Plan).
    var selectedTab: AppTab = LaunchOptions.initialTab

    @ObservationIgnored private var observer: NSObjectProtocol?

    init(context: NSManagedObjectContext) {
        self.context = context
        let household = HouseholdBootstrap.ensureHousehold(in: context)
        PlaceStore.backfill(household, context: context)
        RecurringStore.postDue(in: household, context: context)
        let month = MonthKey(date: .now)
        self.household = household
        self.month = month
        self.snapshot = MonthSnapshot.build(for: month, household: household, context: context)

        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var currency: CurrencyCode { household.currency }

    var budgetMode: BudgetMode {
        get { household.budgetMode }
        set {
            household.budgetMode = newValue
            try? context.save()
        }
    }

    /// When the app comes to the foreground: post recurring items that came
    /// due, move to the new month if one started, refresh exchange rates.
    func becameActive() {
        RecurringStore.postDue(in: household, context: context)
        let current = MonthKey(date: .now)
        if month < current, month == current.previous { month = current }
        refresh()
        Task { await ExchangeRateService.shared.refreshIfNeeded() }
    }

    func refresh() {
        snapshot = MonthSnapshot.build(for: month, household: household, context: context)
    }

    func money(_ amount: Decimal) -> Money {
        Money(amount, currency)
    }
}

import CoreData
import SwiftUI
import TideKit

// Managed object classes. Raw stored fields are suffixed `Raw` or kept
// optional for CloudKit; the typed accessors below are what views use.

/// Gives every record a stable id and creation date.
class TideObject: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        if id == nil { id = UUID() }
        if createdAt == nil { createdAt = .now }
    }
}

@objc(TDHousehold)
final class Household: TideObject {
    @NSManaged var name: String?
    @NSManaged var baseCurrency: String?
    @NSManaged var budgetModeRaw: String?
    @NSManaged var members: NSSet?
    @NSManaged var categories: NSSet?
    @NSManaged var accounts: NSSet?
    @NSManaged var entries: NSSet?
    @NSManaged var budgets: NSSet?
    @NSManaged var goals: NSSet?
    @NSManaged var places: NSSet?

    var currency: CurrencyCode { CurrencyCode(baseCurrency ?? "EUR") }

    var budgetMode: BudgetMode {
        get { BudgetMode(rawValue: budgetModeRaw ?? "") ?? .limits }
        set { budgetModeRaw = newValue.rawValue }
    }

    var memberList: [Member] {
        (members as? Set<Member> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var categoryList: [BudgetCategory] {
        (categories as? Set<BudgetCategory> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    var accountList: [Account] {
        (accounts as? Set<Account> ?? []).filter { !$0.isArchived }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var goalList: [SavingsGoal] {
        (goals as? Set<SavingsGoal> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Top-level categories of one kind (the middle level of the tree).
    func topCategories(_ kind: CategoryKind, includeHidden: Bool = false) -> [BudgetCategory] {
        categoryList.filter { $0.kind == kind && $0.parent == nil && (includeHidden || !$0.isHidden) }
    }

    /// Categories a transaction can be filed under: subcategories, or a
    /// top-level category that has none.
    func pickableCategories(_ kinds: [CategoryKind]) -> [BudgetCategory] {
        kinds.flatMap { kind in
            topCategories(kind).flatMap { top in
                top.childList.isEmpty ? [top] : top.childList
            }
        }
    }
}

@objc(TDMember)
final class Member: TideObject {
    @NSManaged var name: String?
    @NSManaged var colorName: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var household: Household?
    @NSManaged var paidEntries: NSSet?

    var displayName: String { name ?? "Someone" }
    var color: Color { TidePalette.color(named: colorName) }
    var initial: String { String(displayName.prefix(1)).uppercased() }
}

@objc(TDBudgetCategory)
final class BudgetCategory: TideObject {
    @NSManaged var name: String?
    @NSManaged var kindRaw: String?
    @NSManaged var icon: String?
    @NSManaged var colorName: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var isHidden: Bool
    @NSManaged var isPersonal: Bool
    @NSManaged var household: Household?
    @NSManaged var parent: BudgetCategory?
    @NSManaged var children: NSSet?
    @NSManaged var entries: NSSet?
    @NSManaged var budgets: NSSet?
    @NSManaged var goals: NSSet?
    @NSManaged var accounts: NSSet?

    var displayName: String { name ?? "Untitled" }
    var kind: CategoryKind { CategoryKind(rawValue: kindRaw ?? "") ?? .expense }
    var symbol: String { icon ?? "circle.fill" }

    /// Subcategories inherit their parent's color so groups read as one.
    var color: Color { TidePalette.color(named: parent?.colorName ?? colorName) }

    /// Visible subcategories, in order.
    var childList: [BudgetCategory] {
        allChildren.filter { !$0.isHidden }
    }

    /// All subcategories including hidden ones, in order.
    var allChildren: [BudgetCategory] {
        (children as? Set<BudgetCategory> ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Hidden itself, or inside a hidden category.
    var isEffectivelyHidden: Bool { isHidden || (parent?.isHidden ?? false) }

    /// This category plus all its descendants (hidden ones included, so
    /// their history still counts in totals).
    var subtree: [BudgetCategory] {
        [self] + allChildren.flatMap(\.subtree)
    }

    /// "Food › Groceries"
    var path: String {
        if let parent { return "\(parent.displayName) › \(displayName)" }
        return displayName
    }
}

enum AccountKind: String, CaseIterable, Identifiable {
    case current, cash, creditCard, savings, investment, loan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current: "Current account"
        case .cash: "Cash"
        case .creditCard: "Credit card"
        case .savings: "Savings"
        case .investment: "Investments"
        case .loan: "Loan"
        }
    }

    var isLiability: Bool { self == .creditCard || self == .loan }
}

@objc(TDAccount)
final class Account: TideObject {
    @NSManaged var name: String?
    @NSManaged var kindRaw: String?
    @NSManaged var currencyCode: String?
    @NSManaged var icon: String?
    @NSManaged var colorName: String?
    @NSManaged var openingBalance: NSDecimalNumber?
    @NSManaged var interestRate: NSDecimalNumber?
    @NSManaged var minimumPayment: NSDecimalNumber?
    @NSManaged var dueDay: Int16
    @NSManaged var sortOrder: Int16
    @NSManaged var isArchived: Bool
    @NSManaged var household: Household?
    @NSManaged var category: BudgetCategory?
    @NSManaged var entries: NSSet?
    @NSManaged var incomingTransfers: NSSet?
    @NSManaged var snapshots: NSSet?
    @NSManaged var goals: NSSet?

    var displayName: String { name ?? "Account" }
    var kind: AccountKind { AccountKind(rawValue: kindRaw ?? "") ?? .current }
    var currency: CurrencyCode { CurrencyCode(currencyCode ?? "EUR") }
    var symbol: String { icon ?? "building.columns.fill" }
    var color: Color { TidePalette.color(named: colorName) }
}

@objc(TDLedgerEntry)
final class LedgerEntry: TideObject {
    @NSManaged var kindRaw: String?
    @NSManaged var date: Date?
    @NSManaged var payee: String?
    @NSManaged var note: String?
    /// The amount as paid, in `originalCurrency` (e.g. £42.10 abroad).
    @NSManaged var originalAmount: NSDecimalNumber?
    @NSManaged var originalCurrency: String?
    /// The same amount in the household's base currency (e.g. €49.38).
    /// All budgets and reports use this.
    @NSManaged var baseAmount: NSDecimalNumber?
    /// For debt payments: the part that reduced the balance (Milestone 3).
    @NSManaged var principalAmount: NSDecimalNumber?
    @NSManaged var interestAmount: NSDecimalNumber?
    @NSManaged var sourceRaw: String?
    @NSManaged var externalID: String?
    @NSManaged var isPending: Bool
    @NSManaged var household: Household?
    @NSManaged var category: BudgetCategory?
    @NSManaged var account: Account?
    @NSManaged var toAccount: Account?
    @NSManaged var payer: Member?
    @NSManaged var place: Place?

    var kind: EntryKind {
        get { EntryKind(rawValue: kindRaw ?? "") ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var base: Decimal { baseAmount?.decimalValue ?? 0 }

    var original: Money {
        Money(originalAmount?.decimalValue ?? 0, CurrencyCode(originalCurrency ?? "EUR"))
    }

    var isForeign: Bool { original.currency != (household?.currency ?? .eur) }

    /// The place name if there is one, else the category.
    var title: String {
        if let name = place?.name, !name.isEmpty { return name }
        if let payee, !payee.isEmpty { return payee }
        return category?.displayName ?? kind.title
    }

    var placeName: String? {
        if let name = place?.name, !name.isEmpty { return name }
        if let payee, !payee.isEmpty { return payee }
        return nil
    }

    /// Signed amount for totals: spending positive, income negative.
    var spendingAmount: Decimal {
        switch kind {
        case .expense: base
        case .income: -base
        case .transfer: 0
        }
    }
}

@objc(TDMonthlyBudget)
final class MonthlyBudget: TideObject {
    @NSManaged var monthID: String?
    @NSManaged var amount: NSDecimalNumber?
    @NSManaged var rollsOver: Bool
    @NSManaged var household: Household?
    @NSManaged var category: BudgetCategory?

    var value: Decimal { amount?.decimalValue ?? 0 }
}

@objc(TDBalanceSnapshot)
final class BalanceSnapshot: TideObject {
    @NSManaged var monthID: String?
    @NSManaged var balance: NSDecimalNumber?
    @NSManaged var account: Account?
}

@objc(TDSavingsGoal)
final class SavingsGoal: TideObject {
    @NSManaged var name: String?
    @NSManaged var kindRaw: String?
    @NSManaged var icon: String?
    @NSManaged var colorName: String?
    @NSManaged var targetAmount: NSDecimalNumber?
    @NSManaged var savedAmount: NSDecimalNumber?
    @NSManaged var targetDate: Date?
    @NSManaged var sortOrder: Int16
    @NSManaged var household: Household?
    @NSManaged var category: BudgetCategory?
    @NSManaged var account: Account?

    var displayName: String { name ?? "Goal" }
    var target: Decimal { targetAmount?.decimalValue ?? 0 }
    var saved: Decimal { savedAmount?.decimalValue ?? 0 }
    var color: Color { TidePalette.color(named: colorName) }
    var symbol: String { icon ?? "star.fill" }

    var progress: Double {
        target > 0 ? min(1, (saved / target).doubleValue) : 0
    }

    /// Monthly amount needed to hit the target by the target date.
    func monthlyNeeded(from date: Date = .now, calendar: Calendar = .current) -> Decimal? {
        guard let targetDate, target > saved else { return nil }
        let months = calendar.dateComponents([.month], from: date, to: targetDate).month ?? 0
        return ((target - saved) / Decimal(max(1, months))).rounded(scale: 0, mode: .up)
    }
}

@objc(TDPlace)
final class Place: TideObject {
    @NSManaged var name: String?
    @NSManaged var colorName: String?
    @NSManaged var emoji: String?
    @NSManaged var symbol: String?
    @NSManaged var logoData: Data?
    @NSManaged var household: Household?
    @NSManaged var entries: NSSet?

    var displayName: String { name ?? "Place" }

    /// The place's own color, or a stable one derived from its name.
    var color: Color { LogoAppearance(place: self).color }

    var entryList: [LedgerEntry] {
        (entries as? Set<LedgerEntry> ?? []).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

extension Decimal {
    var number: NSDecimalNumber { NSDecimalNumber(decimal: self) }
}

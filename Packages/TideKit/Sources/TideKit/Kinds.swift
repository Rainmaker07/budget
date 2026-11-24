import Foundation

/// The top level of Tide's three-level category tree:
/// kind → category → subcategory.
public enum CategoryKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case income
    case expense
    case savings
    case investment
    case debt

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .income: "Income"
        case .expense: "Expenses"
        case .savings: "Savings"
        case .investment: "Investments"
        case .debt: "Debts"
        }
    }

    public var systemImage: String {
        switch self {
        case .income: "arrow.down.circle.fill"
        case .expense: "cart.fill"
        case .savings: "banknote.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .debt: "creditcard.fill"
        }
    }

    /// Savings, investments and debts are backed by accounts with balances;
    /// money sent there is a transfer, not spending.
    public var isBalanceBacked: Bool {
        switch self {
        case .savings, .investment, .debt: true
        case .income, .expense: false
        }
    }

    /// Kinds that money gets assigned to in Every Dollar mode.
    public static let assignable: [CategoryKind] = [.expense, .savings, .investment, .debt]
}

/// What a single transaction does.
public enum EntryKind: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Money spent on an expense category.
    case expense
    /// Money received from an income category.
    case income
    /// Money moved to savings, investments, or to pay down a debt.
    case transfer

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: "Expense"
        case .income: "Income"
        case .transfer: "Transfer"
        }
    }

    /// Which category kinds a transaction of this kind can be filed under.
    public var categoryKinds: [CategoryKind] {
        switch self {
        case .expense: [.expense]
        case .income: [.income]
        case .transfer: [.savings, .investment, .debt]
        }
    }
}

/// How a household budgets. Both modes share the same data.
public enum BudgetMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// A monthly cap per category; the headline is "safe to spend".
    case limits
    /// Zero-based: every euro of income gets a job; the headline is
    /// "ready to assign".
    case everyDollar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .limits: "Limits"
        case .everyDollar: "Every Euro"
        }
    }

    public var summary: String {
        switch self {
        case .limits: "Set a monthly cap per category and see what's safe to spend."
        case .everyDollar: "Give every euro of income a job before the month starts."
        }
    }
}

/// Where a transaction came from. Only `.manual` exists today; bank import
/// via open banking will add `.bankImport` later without a schema change.
public enum EntrySource: String, Codable, Sendable {
    case manual
    case bankImport
}

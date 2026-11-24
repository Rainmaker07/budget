import Foundation

/// An ISO 4217 currency code such as `EUR` or `GBP`.
public struct CurrencyCode: Hashable, Codable, Sendable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.uppercased()
    }

    public init(_ code: String) {
        self.init(rawValue: code)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }

    public static let eur: CurrencyCode = "EUR"
    public static let usd: CurrencyCode = "USD"
    public static let gbp: CurrencyCode = "GBP"
    public static let chf: CurrencyCode = "CHF"

    /// Currencies offered first in pickers. Euro first; the rest are common
    /// travel currencies for a euro-based household.
    public static let common: [CurrencyCode] = [
        "EUR", "USD", "GBP", "CHF", "SEK", "DKK", "NOK", "PLN", "CZK", "HUF",
        "JPY", "CAD", "AUD", "TRY", "THB", "AED", "MXN",
    ]

    /// Number of minor-unit digits (cents) the currency uses.
    public var fractionDigits: Int {
        switch rawValue {
        case "JPY", "KRW", "ISK", "CLP", "VND", "XOF", "XAF", "PYG", "UGX", "RWF":
            return 0
        case "BHD", "KWD", "OMR", "JOD", "TND", "LYD", "IQD":
            return 3
        default:
            return 2
        }
    }

    /// The currency symbol for the given locale, e.g. `€`, `£`, `CHF`.
    public func symbol(locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = rawValue
        return formatter.currencySymbol ?? rawValue
    }

    /// Localized currency name, e.g. "British Pound".
    public func localizedName(locale: Locale = .current) -> String {
        locale.localizedString(forCurrencyCode: rawValue) ?? rawValue
    }
}

/// An exact amount of money in one currency. Amounts are `Decimal`, never
/// floating point, so cents never drift.
public struct Money: Hashable, Codable, Sendable {
    public var amount: Decimal
    public var currency: CurrencyCode

    public init(_ amount: Decimal, _ currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money {
        Money(0, currency)
    }

    public var isZero: Bool { amount == 0 }
    public var isNegative: Bool { amount < 0 }

    /// Rounded to the currency's minor units.
    public var rounded: Money {
        Money(amount.rounded(scale: currency.fractionDigits), currency)
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot add \(lhs.currency) and \(rhs.currency)")
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot subtract \(rhs.currency) from \(lhs.currency)")
        return Money(lhs.amount - rhs.amount, lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(-value.amount, value.currency)
    }

    public static func * (lhs: Money, rhs: Decimal) -> Money {
        Money(lhs.amount * rhs, lhs.currency)
    }
}

extension Decimal {
    /// Rounds to `scale` decimal places (`.plain` = half away from zero).
    public func rounded(scale: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    public var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

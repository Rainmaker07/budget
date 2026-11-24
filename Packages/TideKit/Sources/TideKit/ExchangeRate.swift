import Foundation

/// A conversion rate: 1 unit of `from` = `rate` units of `to`.
public struct ExchangeRate: Hashable, Codable, Sendable {
    public var from: CurrencyCode
    public var to: CurrencyCode
    public var rate: Decimal
    public var date: Date

    public init(from: CurrencyCode, to: CurrencyCode, rate: Decimal, date: Date = .now) {
        precondition(rate > 0, "Exchange rates must be positive")
        self.from = from
        self.to = to
        self.rate = rate
        self.date = date
    }

    /// The rate implied by what was paid abroad and what the bank charged,
    /// e.g. £42.10 charged as €49.38 → 1 GBP = 1.172921 EUR.
    public static func implied(original: Money, converted: Money, date: Date = .now) -> ExchangeRate? {
        guard original.amount > 0, converted.amount > 0 else { return nil }
        let rate = (converted.amount / original.amount).rounded(scale: 6)
        return ExchangeRate(from: original.currency, to: converted.currency, rate: rate, date: date)
    }

    public var inverted: ExchangeRate {
        ExchangeRate(from: to, to: from, rate: (1 / rate).rounded(scale: 6), date: date)
    }

    /// Converts and rounds to the target currency's minor units.
    public func convert(_ money: Money) -> Money {
        precondition(money.currency == from, "Rate is for \(from), got \(money.currency)")
        return Money(money.amount * rate, to).rounded
    }
}

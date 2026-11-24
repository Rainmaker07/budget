import Foundation

extension Money {
    /// Localized currency text, e.g. "€1,240.00" or "1.240,00 €".
    public func formatted(cents: Bool = true, signed: Bool = false, locale: Locale = .current) -> String {
        var style = Decimal.FormatStyle.Currency(code: currency.rawValue, locale: locale)
        let digits = cents ? currency.fractionDigits : 0
        style = style.precision(.fractionLength(digits))
        if signed {
            style = style.sign(strategy: .always())
        }
        return amount.formatted(style)
    }

    /// Whole units only when the amount is large, e.g. "€1,240" vs "€6.50".
    public func formattedCompact(locale: Locale = .current) -> String {
        let whole = amount.rounded(scale: 0) == amount
        return formatted(cents: !(whole || abs(amount.doubleValue) >= 1000), locale: locale)
    }
}

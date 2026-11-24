import Foundation

/// The state behind Tide's number pad. Builds an amount key by key,
/// respecting the currency's number of decimal places.
public struct AmountInput: Hashable, Sendable {
    public private(set) var integerDigits: String = ""
    public private(set) var fractionDigits: String = ""
    public private(set) var hasSeparator = false
    public var maxFractionDigits: Int
    public static let maxIntegerDigits = 9

    public init(maxFractionDigits: Int = 2) {
        self.maxFractionDigits = maxFractionDigits
    }

    public init(currency: CurrencyCode) {
        self.init(maxFractionDigits: currency.fractionDigits)
    }

    public enum Key: Hashable, Sendable {
        case digit(Int)
        case separator
        case delete
    }

    public mutating func press(_ key: Key) {
        switch key {
        case .digit(let digit):
            precondition((0...9).contains(digit))
            if hasSeparator {
                guard fractionDigits.count < maxFractionDigits else { return }
                fractionDigits.append(String(digit))
            } else {
                guard integerDigits.count < Self.maxIntegerDigits else { return }
                if integerDigits == "0" { integerDigits = "" }
                if digit == 0, integerDigits.isEmpty {
                    integerDigits = "0"
                } else {
                    integerDigits.append(String(digit))
                }
            }
        case .separator:
            guard !hasSeparator, maxFractionDigits > 0 else { return }
            hasSeparator = true
            if integerDigits.isEmpty { integerDigits = "0" }
        case .delete:
            if !fractionDigits.isEmpty {
                fractionDigits.removeLast()
            } else if hasSeparator {
                hasSeparator = false
            } else if !integerDigits.isEmpty {
                integerDigits.removeLast()
            }
        }
    }

    /// Changes the allowed decimal places (e.g. switching EUR → JPY),
    /// trimming extra digits.
    public mutating func setMaxFractionDigits(_ digits: Int) {
        maxFractionDigits = digits
        if fractionDigits.count > digits { fractionDigits = String(fractionDigits.prefix(digits)) }
        if digits == 0 { hasSeparator = false }
    }

    public mutating func clear() {
        integerDigits = ""
        fractionDigits = ""
        hasSeparator = false
    }

    public var isEmpty: Bool { integerDigits.isEmpty && fractionDigits.isEmpty }

    public var value: Decimal {
        let text = (integerDigits.isEmpty ? "0" : integerDigits) + (fractionDigits.isEmpty ? "" : "." + fractionDigits)
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    /// Text as typed, using the locale's decimal separator ("12,5").
    public func displayText(locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ""
        var integer = integerDigits.isEmpty ? "0" : integerDigits
        if integer.count > 3, !grouping.isEmpty {
            var grouped = ""
            for (index, char) in integer.reversed().enumerated() {
                if index > 0, index % 3 == 0 { grouped.append(contentsOf: grouping.reversed()) }
                grouped.append(char)
            }
            integer = String(grouped.reversed())
        }
        return hasSeparator ? integer + separator + fractionDigits : integer
    }
}

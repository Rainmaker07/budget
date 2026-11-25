import SwiftUI
import TideKit

enum AmountText {
    /// Parses "1.234,56", "1,234.56", "1234.5", "12,5" or "€ 40".
    /// The last "." or "," is the decimal point when 1–2 digits follow it;
    /// with 3 digits after it it's a thousands separator ("1.234" = 1234).
    static func parse(_ text: String) -> Decimal? {
        let kept = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !kept.isEmpty else { return nil }
        var normalized = kept.filter(\.isNumber)
        if let last = kept.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = kept[kept.index(after: last)...].filter(\.isNumber)
            if (1...2).contains(tail.count) {
                let whole = kept[..<last].filter(\.isNumber)
                normalized = (whole.isEmpty ? "0" : String(whole)) + "." + tail
            }
        }
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else { return nil }
        return value
    }

    static func string(_ value: Decimal) -> String {
        value == 0 ? "" : NSDecimalNumber(decimal: value).stringValue
    }
}

/// A text field for an amount with the currency symbol in front.
struct AmountTextField: View {
    var title: String
    @Binding var value: Decimal
    var currency: CurrencyCode

    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(currency.symbol())
                .foregroundStyle(.secondary)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 140)
                .onChange(of: text) { value = AmountText.parse(text) ?? 0 }
        }
        .onAppear { text = AmountText.string(value) }
    }
}

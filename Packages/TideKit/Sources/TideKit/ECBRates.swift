import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// European Central Bank reference rates: for each day, how many units of
/// each currency one euro buys. Published around 16:00 CET on working days.
public struct ECBRates: Hashable, Sendable {
    /// Day (start of day, UTC) → currency → units per 1 EUR.
    public private(set) var days: [Date: [CurrencyCode: Decimal]]

    public init(days: [Date: [CurrencyCode: Decimal]]) {
        self.days = days
    }

    public var latestDate: Date? { days.keys.max() }
    public var isEmpty: Bool { days.isEmpty }

    /// The rate from `from` to `to` on the latest published day on or before
    /// `date` (or the earliest day available if `date` is older).
    public func rate(from: CurrencyCode, to: CurrencyCode, on date: Date) -> ExchangeRate? {
        guard from != to else { return ExchangeRate(from: from, to: to, rate: 1, date: date) }
        let sorted = days.keys.sorted()
        guard let day = sorted.last(where: { $0 <= date }) ?? sorted.first,
              let table = days[day] else { return nil }
        func perEuro(_ code: CurrencyCode) -> Decimal? { code == .eur ? 1 : table[code] }
        guard let fromPerEuro = perEuro(from), let toPerEuro = perEuro(to), fromPerEuro > 0 else { return nil }
        return ExchangeRate(from: from, to: to, rate: (toPerEuro / fromPerEuro).rounded(scale: 6), date: day)
    }

    /// Parses the ECB XML feeds (`eurofxref-daily.xml`, `eurofxref-hist-90d.xml`).
    public static func parse(_ data: Data) -> ECBRates? {
        let delegate = ECBParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), !delegate.days.isEmpty else { return nil }
        return ECBRates(days: delegate.days)
    }

    public static let dailyURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    public static let ninetyDayURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!
}

private final class ECBParserDelegate: NSObject, XMLParserDelegate {
    var days: [Date: [CurrencyCode: Decimal]] = [:]
    private var currentDay: Date?

    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        guard elementName == "Cube" || elementName.hasSuffix(":Cube") else { return }
        if let time = attributes["time"] {
            currentDay = Self.dayFormatter.date(from: time)
        } else if let day = currentDay, let currency = attributes["currency"], let rateText = attributes["rate"],
                  let rate = Decimal(string: rateText, locale: Locale(identifier: "en_US_POSIX")), rate > 0 {
            days[day, default: [:]][CurrencyCode(currency)] = rate
        }
    }
}

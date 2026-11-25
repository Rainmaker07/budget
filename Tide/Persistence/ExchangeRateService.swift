import Foundation
import Observation
import TideKit

/// Fetches European Central Bank reference rates (last 90 days, no API key)
/// and suggests what a foreign purchase cost in your main currency. Rates are
/// cached on the device and refreshed at most every 6 hours.
@MainActor
@Observable
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    private(set) var rates: ECBRates?
    private(set) var lastFetch: Date?
    private var isFetching = false

    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ecb-rates-90d.xml")

    init() {
        if let data = try? Data(contentsOf: cacheURL) {
            rates = ECBRates.parse(data)
            lastFetch = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date
        }
    }

    /// The suggested base-currency amount for `money` paid on `date`.
    func suggestion(for money: Money, in base: CurrencyCode, on date: Date) -> (amount: Money, rate: ExchangeRate)? {
        guard money.amount > 0, money.currency != base,
              let rate = rates?.rate(from: money.currency, to: base, on: date) else { return nil }
        return (rate.convert(money), rate)
    }

    func refreshIfNeeded() async {
        if let lastFetch, Date.now.timeIntervalSince(lastFetch) < 6 * 3600, rates != nil { return }
        guard !isFetching, !LaunchOptions.isDemo else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: ECBRates.ninetyDayURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let parsed = ECBRates.parse(data) else { return }
            rates = parsed
            lastFetch = .now
            try? data.write(to: cacheURL, options: .atomic)
        } catch {
            // Offline: keep the cached rates; manual entry always works.
        }
    }
}

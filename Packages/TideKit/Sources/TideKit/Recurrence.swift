import Foundation

/// How often a recurring item repeats.
public enum Cadence: String, CaseIterable, Codable, Sendable, Identifiable {
    case weekly, monthly, yearly

    public var id: String { rawValue }

    public func title(every interval: Int) -> String {
        switch (self, interval) {
        case (.weekly, 1): "Every week"
        case (.weekly, 2): "Every 2 weeks"
        case (.weekly, _): "Every \(interval) weeks"
        case (.monthly, 1): "Every month"
        case (.monthly, 3): "Every quarter"
        case (.monthly, _): "Every \(interval) months"
        case (.yearly, 1): "Every year"
        case (.yearly, _): "Every \(interval) years"
        }
    }
}

/// A repeating schedule, e.g. "the 1st of every month" or "every 2 weeks".
/// Monthly and yearly schedules on the 29th–31st fall on the last day of
/// shorter months (rent on the 31st is paid on 30 April).
public struct Recurrence: Hashable, Sendable {
    public var cadence: Cadence
    public var interval: Int
    /// The first occurrence. Its day (and month, for yearly) anchor the schedule.
    public var start: Date
    public var end: Date?

    public init(cadence: Cadence, interval: Int = 1, start: Date, end: Date? = nil) {
        self.cadence = cadence
        self.interval = max(1, interval)
        self.start = start
        self.end = end
    }

    /// The `index`-th occurrence (0 = start).
    public func occurrence(_ index: Int, calendar: Calendar = .current) -> Date? {
        let step = index * interval
        switch cadence {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * step, to: start)
        case .monthly, .yearly:
            let anchor = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
            let monthsToAdd = cadence == .monthly ? step : 12 * step
            guard let firstOfStartMonth = calendar.date(from: DateComponents(year: anchor.year, month: anchor.month, day: 1)),
                  let firstOfTarget = calendar.date(byAdding: .month, value: monthsToAdd, to: firstOfStartMonth),
                  let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfTarget)?.count
            else { return nil }
            var parts = calendar.dateComponents([.year, .month], from: firstOfTarget)
            parts.day = min(anchor.day ?? 1, daysInMonth)
            parts.hour = anchor.hour
            parts.minute = anchor.minute
            return calendar.date(from: parts)
        }
    }

    /// Occurrences in `from...through` (both inclusive), oldest first.
    public func occurrences(from: Date, through: Date, calendar: Calendar = .current, limit: Int = 500) -> [Date] {
        var result: [Date] = []
        var index = 0
        while index < 10_000, result.count < limit, let date = occurrence(index, calendar: calendar) {
            if date > through { break }
            if let end, date > end { break }
            if date >= from { result.append(date) }
            index += 1
        }
        return result
    }

    /// The first occurrence strictly after `date`.
    public func next(after date: Date, calendar: Calendar = .current) -> Date? {
        var index = 0
        while index < 10_000, let candidate = occurrence(index, calendar: calendar) {
            if let end, candidate > end { return nil }
            if candidate > date { return candidate }
            index += 1
        }
        return nil
    }
}

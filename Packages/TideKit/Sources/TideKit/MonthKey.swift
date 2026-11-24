import Foundation

/// A calendar month, used to key budgets, snapshots and reports.
/// Its `id` ("2026-11") is what gets stored in the database.
public struct MonthKey: Hashable, Codable, Sendable, Comparable, Identifiable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "Month must be 1...12")
        self.year = year
        self.month = month
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year!, month: parts.month!)
    }

    /// Parses "2026-11".
    public init?(id: String) {
        let parts = id.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }

    public var id: String {
        String(format: "%04d-%02d", year, month)
    }

    public var next: MonthKey { adding(months: 1) }
    public var previous: MonthKey { adding(months: -1) }

    public func adding(months: Int) -> MonthKey {
        let index = year * 12 + (month - 1) + months
        let newYear = index >= 0 ? index / 12 : (index - 11) / 12
        return MonthKey(year: newYear, month: index - newYear * 12 + 1)
    }

    public func firstDay(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// Start of the month (inclusive) to start of the next month (exclusive).
    public func interval(calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: firstDay(calendar: calendar), end: next.firstDay(calendar: calendar))
    }

    public func numberOfDays(calendar: Calendar = .current) -> Int {
        calendar.range(of: .day, in: .month, for: firstDay(calendar: calendar))!.count
    }

    /// How far through the month `date` is, 0...1.
    public func progress(at date: Date, calendar: Calendar = .current) -> Double {
        let range = interval(calendar: calendar)
        if date <= range.start { return 0 }
        if date >= range.end { return 1 }
        return date.timeIntervalSince(range.start) / range.duration
    }

    /// Days left including today, minimum 0.
    public func daysRemaining(from date: Date, calendar: Calendar = .current) -> Int {
        let range = interval(calendar: calendar)
        if date < range.start { return numberOfDays(calendar: calendar) }
        if date >= range.end { return 0 }
        let today = calendar.component(.day, from: date)
        return numberOfDays(calendar: calendar) - today + 1
    }

    public static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

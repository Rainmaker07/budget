import Foundation

/// Helpers for the names of places money is spent at ("Rewe", "Blue Door Coffee").
public enum PlaceName {
    /// Trims and collapses whitespace: "  Rewe   City " → "Rewe City".
    public static func clean(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A matching key that ignores case, accents and spacing,
    /// so "REWE", "rewe " and "Réwe" are the same place.
    public static func key(_ name: String) -> String {
        clean(name).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The first letter for a monogram logo.
    public static func initial(_ name: String) -> String {
        guard let first = clean(name).first else { return "?" }
        return String(first).uppercased()
    }

    /// A stable palette index for a name (same name → same color on every device).
    public static func colorIndex(_ name: String, paletteSize: Int) -> Int {
        precondition(paletteSize > 0)
        var hash: UInt32 = 2_166_136_261 // FNV-1a
        for byte in key(name).utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(paletteSize))
    }

    /// Ranks known places for what's been typed: prefix matches first,
    /// then word-prefix matches, then anything containing the text.
    /// Ties keep the input order (callers pass most-used first).
    public static func suggestions(for query: String, in names: [String], limit: Int = 5) -> [String] {
        let needle = key(query)
        guard !needle.isEmpty else { return Array(names.prefix(limit)) }
        func rank(_ name: String) -> Int? {
            let hay = key(name)
            if hay == needle { return 0 }
            if hay.hasPrefix(needle) { return 1 }
            if hay.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 2 }
            if hay.contains(needle) { return 3 }
            return nil
        }
        return names.enumerated()
            .compactMap { index, name in rank(name).map { (rank: $0, index: index, name: name) } }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .prefix(limit)
            .map(\.name)
    }
}

/// Spending statistics for one place.
public struct PlaceStats: Hashable, Sendable {
    public struct Visit: Hashable, Sendable {
        public var date: Date
        /// Base-currency amount. Positive = spent, negative = refund/income.
        public var amount: Decimal

        public init(date: Date, amount: Decimal) {
            self.date = date
            self.amount = amount
        }
    }

    public var total: Decimal
    public var visits: Int
    public var lastVisit: Date?

    public var average: Decimal {
        visits > 0 ? (total / Decimal(visits)).rounded(scale: 2) : 0
    }

    public init(total: Decimal, visits: Int, lastVisit: Date?) {
        self.total = total
        self.visits = visits
        self.lastVisit = lastVisit
    }

    /// Totals for visits within `interval` (nil = all time).
    public static func compute(_ visits: [Visit], in interval: DateInterval? = nil) -> PlaceStats {
        let selected = visits.filter { visit in interval.map { $0.contains(visit.date) && visit.date < $0.end } ?? true }
        return PlaceStats(
            total: selected.reduce(Decimal(0)) { $0 + $1.amount },
            visits: selected.count,
            lastVisit: selected.map(\.date).max()
        )
    }

    /// Spending per month for the `count` months ending with `last`, oldest first.
    public static func monthly(_ visits: [Visit], last: MonthKey, count: Int, calendar: Calendar = .current) -> [(month: MonthKey, total: Decimal)] {
        var totals: [MonthKey: Decimal] = [:]
        for visit in visits {
            totals[MonthKey(date: visit.date, calendar: calendar), default: 0] += visit.amount
        }
        return (0..<count).reversed().map { offset in
            let month = last.adding(months: -offset)
            return (month, totals[month] ?? 0)
        }
    }
}

/// The period switch used by place totals.
public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case month, year, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .month: "This month"
        case .year: "This year"
        case .all: "All time"
        }
    }

    public func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .month: calendar.dateInterval(of: .month, for: date)
        case .year: calendar.dateInterval(of: .year, for: date)
        case .all: nil
        }
    }
}

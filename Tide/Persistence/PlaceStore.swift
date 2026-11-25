import CoreData
import TideKit

/// Finding, creating, merging and summarizing places.
@MainActor
enum PlaceStore {
    static func all(in household: Household, context: NSManagedObjectContext) -> [Place] {
        let request = NSFetchRequest<Place>(entityName: "Place")
        request.predicate = NSPredicate(format: "household == %@", household)
        return (try? context.fetch(request)) ?? []
    }

    static func find(named name: String, in household: Household, context: NSManagedObjectContext) -> Place? {
        let key = PlaceName.key(name)
        guard !key.isEmpty else { return nil }
        return all(in: household, context: context).first { PlaceName.key($0.displayName) == key }
    }

    /// The existing place with this name (ignoring case and accents), or a new one.
    static func findOrCreate(named name: String, in household: Household, context: NSManagedObjectContext) -> Place? {
        let cleaned = PlaceName.clean(name)
        guard !cleaned.isEmpty else { return nil }
        if let existing = find(named: cleaned, in: household, context: context) { return existing }
        let place = Place(context: context)
        place.name = cleaned
        place.household = household
        return place
    }

    /// Links entries that only have a typed place name (from 0.1.0) to Place
    /// records. Safe to run on every launch.
    static func backfill(_ household: Household, context: NSManagedObjectContext) {
        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.predicate = NSPredicate(format: "household == %@ AND place == nil AND payee != nil AND payee != ''", household)
        guard let entries = try? context.fetch(request), !entries.isEmpty else { return }
        var cache: [String: Place] = [:]
        for place in all(in: household, context: context) {
            cache[PlaceName.key(place.displayName)] = place
        }
        for entry in entries {
            guard let payee = entry.payee else { continue }
            let key = PlaceName.key(payee)
            guard !key.isEmpty else { continue }
            if let place = cache[key] {
                entry.place = place
            } else if let place = findOrCreate(named: payee, in: household, context: context) {
                cache[key] = place
                entry.place = place
            }
        }
        if context.hasChanges { try? context.save() }
    }

    /// Places ordered by how often and how recently they're used: most used
    /// first, ties broken by most recent visit.
    static func ranked(in household: Household, context: NSManagedObjectContext) -> [Place] {
        all(in: household, context: context)
            .map { place -> (Place, Int, Date) in
                let entries = place.entryList
                return (place, entries.count, entries.first?.date ?? .distantPast)
            }
            .sorted { ($0.1, $0.2) > ($1.1, $1.2) }
            .map(\.0)
    }

    /// Places used most recently, newest first.
    static func recent(in household: Household, context: NSManagedObjectContext, limit: Int = 8) -> [Place] {
        all(in: household, context: context)
            .compactMap { place in place.entryList.first?.date.map { (place, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// The category last used at this place for this kind of transaction.
    static func usualCategory(for place: Place, kind: EntryKind) -> BudgetCategory? {
        place.entryList.first { $0.kind == kind && $0.category != nil && !($0.category?.isEffectivelyHidden ?? true) }?.category
    }

    /// The category used most often at a place (for its detail page).
    static func mostUsedCategory(for place: Place) -> BudgetCategory? {
        let counts = Dictionary(grouping: place.entryList.compactMap(\.category), by: \.objectID)
        return counts.max { $0.value.count < $1.value.count }?.value.first
    }

    static func visits(for place: Place) -> [PlaceStats.Visit] {
        place.entryList.compactMap { entry in
            guard let date = entry.date, entry.kind != .transfer else { return nil }
            return PlaceStats.Visit(date: date, amount: entry.spendingAmount)
        }
    }

    static func stats(for place: Place, period: StatsPeriod, now: Date = .now) -> PlaceStats {
        PlaceStats.compute(visits(for: place), in: period.interval(containing: now))
    }

    /// Renames a place. Returns the place it collides with, if any, so the UI
    /// can offer a merge instead.
    static func rename(_ place: Place, to name: String, context: NSManagedObjectContext) -> Place? {
        let cleaned = PlaceName.clean(name)
        guard !cleaned.isEmpty, let household = place.household else { return nil }
        if let other = find(named: cleaned, in: household, context: context), other != place {
            return other
        }
        place.name = cleaned
        for entry in place.entryList { entry.payee = cleaned }
        try? context.save()
        return nil
    }

    /// Moves every transaction from `source` to `target` and deletes `source`.
    /// Keeps the target's logo, or takes the source's if the target has none.
    static func merge(_ source: Place, into target: Place, context: NSManagedObjectContext) {
        guard source != target else { return }
        for entry in source.entryList {
            entry.place = target
            entry.payee = target.name
        }
        if target.logoData == nil, target.emoji == nil, target.symbol == nil {
            target.logoData = source.logoData
            target.emoji = source.emoji
            target.symbol = source.symbol
        }
        context.delete(source)
        try? context.save()
    }
}

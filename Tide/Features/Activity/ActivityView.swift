import CoreData
import SwiftUI
import TideKit

/// All transactions, newest first, grouped by day. Search and filters
/// arrive in Milestone 2.
struct ActivityView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerEntry.date, order: .reverse)])
    private var entries: FetchedResults<LedgerEntry>

    var body: some View {
        NavigationStack {
            List {
                ForEach(days, id: \.day) { group in
                    Section {
                        ForEach(group.entries, id: \.objectID) { entry in
                            EntryRow(entry: entry)
                                .listRowBackground(Color.clear)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(entry)
                                        try? context.save()
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            Spacer()
                            Text(model.money(group.spent).formatted())
                                .monospacedDigit()
                        }
                        .font(.footnote.weight(.semibold))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .tideBackground(model.snapshot.summary.health)
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No transactions yet", systemImage: "list.bullet.rectangle",
                                           description: Text("Everything you add shows up here."))
                }
            }
            .navigationTitle("Activity")
        }
    }

    private struct DayGroup {
        let day: Date
        let entries: [LedgerEntry]
        var spent: Decimal {
            entries.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.base }
        }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date ?? .distantPast) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }
}

import CoreData
import SwiftUI
import TideKit

/// Transactions grouped into one card per day, with search and quick
/// filters — or the places money goes, ranked by total spent.
struct ActivityView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case transactions = "Transactions"
        case places = "Places"
        var id: String { rawValue }
    }

    enum Filter: Hashable {
        case all
        case kind(EntryKind)
        case member(NSManagedObjectID)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\LedgerEntry.date, order: .reverse)])
    private var entries: FetchedResults<LedgerEntry>
    @FetchRequest(sortDescriptors: []) private var places: FetchedResults<Place>

    @State private var mode: Mode = LaunchOptions.activityMode
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var period: StatsPeriod = .month
    @State private var editing: ObjectRef<LedgerEntry>?
    @State private var deleting: ObjectRef<LedgerEntry>?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))

                    if mode == .transactions {
                        filterChips
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } else {
                        Picker("Period", selection: $period) {
                            ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                .listSectionSeparator(.hidden)

                switch mode {
                case .transactions: transactionSections
                case .places: placeSection
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .scrollContentBackground(.hidden)
            .tideBackground(model.snapshot.summary.health)
            .searchable(text: $search, prompt: mode == .transactions ? "Search transactions" : "Search places")
            .overlay { emptyState }
            .navigationTitle("Activity")
            .navigationDestination(for: NSManagedObjectID.self) { id in
                if let entry = try? context.existingObject(with: id) as? LedgerEntry {
                    EntryDetailView(entry: entry)
                } else if let place = try? context.existingObject(with: id) as? Place {
                    PlaceDetailView(place: place)
                }
            }
            .sheet(item: $editing) { ref in
                EntryEditorView(mode: .edit(ref.object))
            }
            .confirmationDialog("Delete this transaction?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { ref in
                Button("Delete", role: .destructive) {
                    context.delete(ref.object)
                    try? context.save()
                }
            }
            .task {
                if LaunchOptions.opensLatestEntry, let latest = entries.first, path.isEmpty {
                    path.append(latest.objectID)
                }
            }
        }
    }

    // MARK: - Transactions

    private var filterChips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("All", isOn: filter == .all) { filter = .all }
                    chip("Expenses", isOn: filter == .kind(.expense)) { filter = .kind(.expense) }
                    chip("Income", isOn: filter == .kind(.income)) { filter = .kind(.income) }
                    chip("Transfers", isOn: filter == .kind(.transfer)) { filter = .kind(.transfer) }
                    if model.household.memberList.count > 1 {
                        ForEach(model.household.memberList, id: \.objectID) { member in
                            chip(member.displayName, isOn: filter == .member(member.objectID), member: member) {
                                filter = .member(member.objectID)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, isOn: Bool, member: Member? = nil, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            HStack(spacing: 6) {
                if let member { MemberAvatar(member: member, size: 18) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? .white : .primary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassEffect(isOn ? .regular.tint(TidePalette.accent(for: model.snapshot.summary.health)).interactive() : .regular.interactive(),
                         in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var transactionSections: some View {
        ForEach(days, id: \.day) { group in
            Section {
                ForEach(group.entries, id: \.objectID) { entry in
                    NavigationLink(value: entry.objectID) {
                        EntryRow(entry: entry)
                    }
                    .listRowBackground(Rectangle().fill(.ultraThinMaterial))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleting = ObjectRef(object: entry)
                        }
                        Button("Edit", systemImage: "pencil") {
                            editing = ObjectRef(object: entry)
                        }
                        .tint(.indigo)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(dayTitle(group.day))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if group.spent != 0 {
                        Text(model.money(-group.spent).formatted(signed: true))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .textCase(nil)
                .padding(.horizontal, 4)
            }
        }
    }

    private struct DayGroup {
        let day: Date
        let entries: [LedgerEntry]
        /// Net spending (expenses minus income) for the day header.
        var spent: Decimal { entries.reduce(Decimal(0)) { $0 + $1.spendingAmount } }
    }

    private var filteredEntries: [LedgerEntry] {
        let query = PlaceName.key(search)
        return entries.filter { entry in
            switch filter {
            case .all: break
            case .kind(let kind): if entry.kind != kind { return false }
            case .member(let id): if entry.payer?.objectID != id { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = [entry.title, entry.category?.path ?? "", entry.note ?? "",
                            entry.base.formatted(), entry.original.currency.rawValue]
                .map(PlaceName.key)
                .joined(separator: " ")
            return haystack.contains(query)
        }
    }

    private var days: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { calendar.startOfDay(for: $0.date ?? .distantPast) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, entries: grouped[$0] ?? []) }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return sameYear
            ? day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
            : day.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // MARK: - Places

    private var placeSummaries: [PlaceSummary] {
        let all = PlaceSummary.list(Array(places), period: period)
        guard !search.isEmpty else { return all }
        let names = Set(PlaceName.suggestions(for: search, in: all.map(\.place.displayName), limit: all.count))
        return all.filter { names.contains($0.place.displayName) }
    }

    private var placeSection: some View {
        Section {
            ForEach(placeSummaries) { summary in
                NavigationLink(value: summary.place.objectID) {
                    PlaceSummaryRow(summary: summary, currency: model.currency)
                }
                .listRowBackground(Rectangle().fill(.ultraThinMaterial))
            }
        } header: {
            if !placeSummaries.isEmpty {
                HStack {
                    Text("\(placeSummaries.count) places")
                    Spacer()
                    Text(model.money(placeSummaries.reduce(Decimal(0)) { $0 + $1.stats.total }).formatted())
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch mode {
        case .transactions where entries.isEmpty:
            ContentUnavailableView("No transactions yet", systemImage: "list.bullet.rectangle",
                                   description: Text("Everything you add shows up here."))
        case .transactions where days.isEmpty:
            ContentUnavailableView.search(text: search)
        case .places where placeSummaries.isEmpty:
            ContentUnavailableView("No places \(period == .all ? "yet" : period.title.lowercased())", systemImage: "storefront",
                                   description: Text("Add where you spent money when you log a transaction."))
        default:
            EmptyView()
        }
    }
}

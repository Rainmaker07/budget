import Charts
import CoreData
import PhotosUI
import SwiftUI
import TideKit

/// A place with its totals for a period.
struct PlaceSummary: Identifiable {
    let place: Place
    let stats: PlaceStats
    var id: NSManagedObjectID { place.objectID }

    @MainActor
    static func list(_ places: [Place], period: StatsPeriod, now: Date = .now) -> [PlaceSummary] {
        places
            .map { PlaceSummary(place: $0, stats: PlaceStore.stats(for: $0, period: period, now: now)) }
            .filter { $0.stats.visits > 0 }
            .sorted { ($0.stats.total, $0.stats.visits) > ($1.stats.total, $1.stats.visits) }
    }
}

/// One place in a list: logo, name, visits and average, total.
struct PlaceSummaryRow: View {
    let summary: PlaceSummary
    var currency: CurrencyCode

    var body: some View {
        HStack(spacing: 12) {
            PlaceLogo(place: summary.place, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.place.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money(summary.stats.total, currency).formatted())
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let visits = summary.stats.visits == 1 ? "1 visit" : "\(summary.stats.visits) visits"
        return "\(visits) · \(Money(summary.stats.average, currency).formatted()) avg"
    }
}

/// Places as a standalone screen (from Settings).
struct PlacesScreen: View {
    @Environment(AppModel.self) private var model
    @FetchRequest(sortDescriptors: []) private var places: FetchedResults<Place>
    // Observing entries keeps totals fresh when transactions change.
    @FetchRequest(sortDescriptors: []) private var entries: FetchedResults<LedgerEntry>
    @State private var period: StatsPeriod = .month

    var body: some View {
        let summaries = PlaceSummary.list(Array(places), period: period)
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(summaries) { summary in
                    NavigationLink {
                        PlaceDetailView(place: summary.place)
                    } label: {
                        PlaceSummaryRow(summary: summary, currency: model.currency)
                    }
                }
            }
        }
        .overlay {
            if summaries.isEmpty {
                ContentUnavailableView("No places yet", systemImage: "storefront",
                                       description: Text("Add a place when you log a transaction."))
            }
        }
        .scrollContentBackground(.hidden)
        .background { TideBackground(health: model.snapshot.summary.health) }
        .navigationTitle("Places")
    }
}

/// Everything about one place: totals, monthly chart, transactions,
/// logo, rename and merge.
struct PlaceDetailView: View {
    @ObservedObject var place: Place
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var period: StatsPeriod = .year
    @State private var editingLogo = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var collision: ObjectRef<Place>?
    @State private var choosingMergeTarget = false

    var body: some View {
        let currency = model.currency
        let stats = PlaceStore.stats(for: place, period: period)
        let visits = PlaceStore.visits(for: place)
        let monthly = PlaceStats.monthly(visits, last: MonthKey(date: .now), count: 6)

        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Button {
                        editingLogo = true
                    } label: {
                        PlaceLogo(place: place, size: 88)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, place.color)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change logo")

                    Text(place.displayName)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let category = PlaceStore.mostUsedCategory(for: place) {
                        Label(category.path, systemImage: category.symbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                Picker("Period", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        statTile("Spent", Money(stats.total, currency).formatted(cents: false))
                        statTile("Visits", "\(stats.visits)")
                        statTile("Average", Money(stats.average, currency).formatted(cents: false))
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Last 6 months")
                            .font(.subheadline.weight(.semibold))
                        Chart(monthly, id: \.month) { item in
                            BarMark(
                                x: .value("Month", item.month.firstDay(), unit: .month),
                                y: .value("Spent", item.total.doubleValue)
                            )
                            .foregroundStyle(place.color.gradient)
                            .cornerRadius(6)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .month)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(Money(Decimal(amount), currency).formatted(cents: false))
                                    }
                                }
                            }
                        }
                        .frame(height: 160)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Transactions", detail: "\(place.entryList.count)")
                    GlassCard(padding: 4) {
                        LazyVStack(spacing: 0) {
                            ForEach(place.entryList, id: \.objectID) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    EntryRow(entry: entry, showsDate: true)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .tideBackground(model.snapshot.summary.health)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Change logo", systemImage: "photo.circle") { editingLogo = true }
                    Button("Rename", systemImage: "pencil") {
                        newName = place.displayName
                        renaming = true
                    }
                    Button("Merge with…", systemImage: "arrow.triangle.merge") { choosingMergeTarget = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Place options")
            }
        }
        .sheet(isPresented: $editingLogo) {
            PlaceLogoEditor(place: place)
        }
        .sheet(isPresented: $choosingMergeTarget) {
            MergePlaceSheet(source: place) { dismiss() }
        }
        .alert("Rename place", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let other = PlaceStore.rename(place, to: newName, context: context) {
                    collision = ObjectRef(object: other)
                }
            }
        } message: {
            Text("Renames this place on all its transactions.")
        }
        .alert(
            "“\(collision?.object.displayName ?? "")” already exists",
            isPresented: Binding(get: { collision != nil }, set: { if !$0 { collision = nil } }),
            presenting: collision
        ) { other in
            Button("Cancel", role: .cancel) {}
            Button("Merge") {
                PlaceStore.merge(place, into: other.object, context: context)
                dismiss()
            }
        } message: { other in
            Text("Merge \(place.displayName) into \(other.object.displayName)? All transactions move there.")
        }
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.tideNumber(20, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// Picks another place to merge into.
struct MergePlaceSheet: View {
    @ObservedObject var source: Place
    var onMerged: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var confirming: ObjectRef<Place>?

    var body: some View {
        NavigationStack {
            List {
                ForEach(candidates, id: \.objectID) { place in
                    Button {
                        confirming = ObjectRef(object: place)
                    } label: {
                        HStack(spacing: 12) {
                            PlaceLogo(place: place, size: 36)
                            Text(place.displayName)
                            Spacer()
                            Text("\(place.entryList.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $search, prompt: "Search places")
            .navigationTitle("Merge \(source.displayName) into…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
            .confirmationDialog("Merge places?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { target in
                Button("Merge into \(target.object.displayName)", role: .destructive) {
                    PlaceStore.merge(source, into: target.object, context: context)
                    dismiss()
                    onMerged()
                }
            } message: { target in
                Text("All \(source.entryList.count) transactions from \(source.displayName) move to \(target.object.displayName).")
            }
        }
    }

    private var candidates: [Place] {
        let others = PlaceStore.ranked(in: model.household, context: context).filter { $0 != source }
        let names = PlaceName.suggestions(for: search, in: others.map(\.displayName), limit: others.count)
        return search.isEmpty ? others : names.compactMap { name in others.first { $0.displayName == name } }
    }
}

/// Chooses a place's logo: initial, emoji, symbol or photo, plus its color.
struct PlaceLogoEditor: View {
    @ObservedObject var place: Place
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    enum Style: String, CaseIterable, Identifiable {
        case initial = "Initial", emoji = "Emoji", symbol = "Symbol", photo = "Photo"
        var id: String { rawValue }
    }

    @State private var style: Style = .initial
    @State private var emoji = ""
    @State private var symbol = "cart.fill"
    @State private var colorName = ""
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PlaceLogo(appearance: previewAppearance, size: 96)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Style", selection: $style) {
                        ForEach(Style.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                switch style {
                case .initial:
                    EmptyView()
                case .emoji:
                    Section("Emoji") {
                        TextField("Type or paste one emoji", text: $emoji)
                            .font(.largeTitle)
                            .onChange(of: emoji) {
                                if let last = emoji.last, emoji.count > 1 { emoji = String(last) }
                            }
                    }
                case .symbol:
                    Section("Symbol") {
                        IconPicker(selection: $symbol, color: TidePalette.color(named: colorName.isEmpty ? nil : colorName))
                            .padding(.vertical, 4)
                    }
                case .photo:
                    Section("Photo") {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoData == nil ? "Choose a photo" : "Choose another photo", systemImage: "photo.on.rectangle")
                        }
                    }
                }

                if style != .photo {
                    Section("Color") {
                        ColorSwatchPicker(selection: $colorName)
                            .padding(.vertical, 4)
                        if !colorName.isEmpty {
                            Button("Use automatic color") { colorName = "" }
                        }
                    }
                }
            }
            .navigationTitle(place.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        photoData = LogoImage.thumbnail(from: data)
                    }
                }
            }
        }
    }

    /// The edited logo, before it's saved.
    private var previewAppearance: LogoAppearance {
        LogoAppearance(
            name: place.displayName,
            colorName: colorName.isEmpty ? nil : colorName,
            emoji: style == .emoji && !emoji.isEmpty ? emoji : nil,
            symbol: style == .symbol ? symbol : nil,
            imageData: style == .photo ? photoData : nil
        )
    }

    private func load() {
        colorName = place.colorName ?? ""
        emoji = place.emoji ?? ""
        symbol = place.symbol ?? "cart.fill"
        photoData = place.logoData
        if place.logoData != nil { style = .photo }
        else if place.emoji?.isEmpty == false { style = .emoji }
        else if place.symbol?.isEmpty == false { style = .symbol }
        else { style = .initial }
    }

    private func save() {
        let logo = previewAppearance
        place.colorName = logo.colorName
        place.emoji = logo.emoji
        place.symbol = logo.symbol
        place.logoData = logo.imageData
        try? context.save()
        dismiss()
    }
}

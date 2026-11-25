import CoreData
import SwiftUI
import TideKit

/// Adds a new transaction or edits an existing one.
///
/// The number pad opens only when you tap the amount, so the place, category
/// and details stay visible. Paying abroad? Switch the currency and enter
/// what your bank charged.
struct EntryEditorView: View {
    enum Mode: Identifiable {
        case new
        case edit(LedgerEntry)
        case duplicate(LedgerEntry)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let entry): "edit-\(entry.objectID.uriRepresentation().absoluteString)"
            case .duplicate(let entry): "duplicate-\(entry.objectID.uriRepresentation().absoluteString)"
            }
        }

        var source: LedgerEntry? {
            switch self {
            case .new: nil
            case .edit(let entry), .duplicate(let entry): entry
            }
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Re-render when categories change (e.g. edited from the long-press menu).
    @FetchRequest(sortDescriptors: []) private var allCategories: FetchedResults<BudgetCategory>

    @State private var kind: EntryKind = .expense
    @State private var input = AmountInput(currency: .eur)
    @State private var currency: CurrencyCode = .eur
    @State private var chargedText = ""
    @State private var category: BudgetCategory?
    @State private var categoryChosenByUser = false
    @State private var payer: Member?
    @State private var account: Account?
    @State private var date = Date.now
    @State private var placeText = ""
    @State private var place: Place?
    @State private var note = ""
    @State private var showsPad = false
    @State private var showsCategoryManager = false
    @State private var rankedPlaces: [Place] = []
    @State private var recentPlaces: [Place] = []
    @State private var recentCategoryIDs: [NSManagedObjectID] = []
    @State private var saveCount = 0
    @State private var prepared = false
    @FocusState private var focusedField: Field?
    @AppStorage("quickAdd.lastPayer") private var lastPayerURI = ""

    private enum Field { case charged, place, note }

    private var household: Household { model.household }
    private var baseCurrency: CurrencyCode { household.currency }
    private var isForeign: Bool { currency != baseCurrency }

    private var chargedAmount: Decimal? {
        let normalized = chargedText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private var baseAmount: Decimal? {
        isForeign ? chargedAmount : input.value
    }

    private var canSave: Bool {
        input.value > 0 && category != nil && baseAmount != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Type", selection: $kind) {
                        ForEach(EntryKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    amountDisplay

                    if isForeign {
                        foreignCharge
                    }

                    placeField

                    CategoryChips(
                        categories: orderedCategories,
                        selection: Binding(
                            get: { category },
                            set: { newValue in
                                category = newValue
                                categoryChosenByUser = true
                                hidePad()
                            }
                        ),
                        onManage: { showsCategoryManager = true }
                    )

                    details
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .background {
                    // Tapping empty space closes the number pad.
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { hidePad() }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { hidePad() }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .background { TideBackground(health: model.snapshot.summary.health) }
        .sensoryFeedback(.success, trigger: saveCount)
        .onAppear(perform: prepare)
        .onChange(of: kind) {
            if let category, !kind.categoryKinds.contains(category.kind) {
                self.category = nil
                categoryChosenByUser = false
            }
            if let place, !categoryChosenByUser {
                category = PlaceStore.usualCategory(for: place, kind: kind)
            }
        }
        .onChange(of: currency) {
            input.setMaxFractionDigits(currency.fractionDigits)
        }
        .onChange(of: focusedField) {
            if focusedField != nil { hidePad() }
        }
        .onChange(of: placeText) {
            if let place, PlaceName.key(place.displayName) != PlaceName.key(placeText) {
                self.place = nil
            }
        }
        .sheet(isPresented: $showsCategoryManager) {
            NavigationStack {
                CategoriesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { showsCategoryManager = false }
                        }
                    }
            }
        }
    }

    private var title: String {
        switch mode {
        case .edit: "Edit \(kind.title.lowercased())"
        case .new, .duplicate: "New \(kind.title.lowercased())"
        }
    }

    // MARK: - Amount

    private var amountDisplay: some View {
        VStack(spacing: 8) {
            Button {
                focusedField = nil
                withAnimation(.snappy) { showsPad.toggle() }
            } label: {
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(currency.symbol())
                            .font(.tideNumber(28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(input.displayText())
                            .font(.tideNumber(54, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: input)
                            .foregroundStyle(input.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                    }
                    Text(showsPad ? "Tap Done when finished" : (input.isEmpty ? "Tap to enter amount" : "Tap to change"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Amount \(Money(input.value, currency).formatted())")
            .accessibilityHint("Opens the number pad")

            Menu {
                ForEach(currencyChoices, id: \.self) { code in
                    Button("\(code.rawValue) – \(code.localizedName())") { currency = code }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(currency.rawValue)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
        }
    }

    private var foreignCharge: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Charged by your bank", systemImage: "building.columns")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    HStack(spacing: 2) {
                        Text(baseCurrency.symbol())
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $chargedText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .charged)
                            .frame(maxWidth: 110)
                    }
                    .font(.tideNumber(20, weight: .semibold))
                }
                Text(rateHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rateHint: String {
        guard input.value > 0, let charged = chargedAmount,
              let rate = ExchangeRate.implied(original: Money(input.value, currency), converted: Money(charged, baseCurrency))
        else {
            return "Enter the \(baseCurrency.rawValue) amount from your statement. Budgets and reports use it."
        }
        return "1 \(currency.rawValue) = \(rate.rate.rounded(scale: 4).formatted()) \(baseCurrency.rawValue)"
    }

    // MARK: - Place

    private var placeField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let place {
                    PlaceLogo(place: place, size: 28)
                } else if !PlaceName.clean(placeText).isEmpty {
                    PlaceLogo(appearance: LogoAppearance(name: placeText), size: 28)
                } else {
                    Image(systemName: kind == .income ? "person.crop.circle" : "storefront")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                }
                TextField(kind == .income ? "From (employer, client…)" : "Place (shop, vendor…)", text: $placeText)
                    .font(.body.weight(.medium))
                    .focused($focusedField, equals: .place)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(commitTypedPlace)
                if !placeText.isEmpty {
                    Button {
                        placeText = ""
                        place = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear place")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassEffect(.regular.interactive(), in: .capsule)

            if focusedField == .place {
                placeSuggestions
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: focusedField == .place)
    }

    @ViewBuilder
    private var placeSuggestions: some View {
        let query = PlaceName.clean(placeText)
        if query.isEmpty {
            if !recentPlaces.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(recentPlaces, id: \.objectID) { candidate in
                            Button {
                                select(candidate)
                            } label: {
                                HStack(spacing: 6) {
                                    PlaceLogo(place: candidate, size: 22)
                                    Text(candidate.displayName)
                                        .font(.subheadline.weight(.medium))
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 12)
                                .frame(height: 34)
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        } else {
            let names = PlaceName.suggestions(for: query, in: rankedPlaces.map(\.displayName), limit: 4)
            let matches = names.compactMap { name in rankedPlaces.first { $0.displayName == name } }
                .filter { PlaceName.key($0.displayName) != PlaceName.key(query) || place == nil }
            if !matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.objectID) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            HStack(spacing: 10) {
                                PlaceLogo(place: candidate, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(candidate.displayName)
                                        .font(.subheadline.weight(.semibold))
                                    if let usual = PlaceStore.usualCategory(for: candidate, kind: kind) {
                                        Text(usual.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
    }

    private func select(_ candidate: Place) {
        place = candidate
        placeText = candidate.displayName
        focusedField = nil
        if !categoryChosenByUser || category == nil,
           let usual = PlaceStore.usualCategory(for: candidate, kind: kind) {
            withAnimation(.snappy) { category = usual }
        }
    }

    /// On Return: if the typed name matches a known place, use it.
    private func commitTypedPlace() {
        if place == nil, let match = rankedPlaces.first(where: { PlaceName.key($0.displayName) == PlaceName.key(placeText) }) {
            select(match)
        }
        focusedField = nil
    }

    // MARK: - Details

    /// Date, who paid and account as compact glass chips, plus a note.
    private var details: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()

                Menu {
                    ForEach(household.memberList, id: \.objectID) { member in
                        Button(member.displayName) {
                            payer = member
                            lastPayerURI = member.objectID.uriRepresentation().absoluteString
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        MemberAvatar(member: payer, size: 20)
                        Text(payer?.displayName ?? "Who paid")
                            .lineLimit(1)
                    }
                    .detailChip()
                }
                .accessibilityLabel("Paid by \(payer?.displayName ?? "nobody")")

                Menu {
                    ForEach(spendingAccounts, id: \.objectID) { account in
                        Button(account.displayName, systemImage: account.symbol) { self.account = account }
                    }
                } label: {
                    Image(systemName: account?.symbol ?? "building.columns")
                        .foregroundStyle(account?.color ?? .secondary)
                        .detailChip()
                }
                .accessibilityLabel("Account \(account?.displayName ?? "none")")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .note)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 10) {
            if showsPad {
                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Done") { hidePad() }
                            .font(.headline)
                            .buttonStyle(.glass)
                    }
                    NumberPad { input.press($0) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Button(action: save) {
                Text(saveTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var saveTitle: String {
        guard input.value > 0 else { return "Enter an amount" }
        guard category != nil else { return "Choose a category" }
        if isForeign, chargedAmount == nil { return "Enter the \(baseCurrency.rawValue) amount" }
        let amount = Money(input.value, currency).formatted()
        return mode.isEditing ? "Save \(amount)" : "Add \(amount)"
    }

    private func hidePad() {
        guard showsPad else { return }
        withAnimation(.snappy) { showsPad = false }
    }

    // MARK: - Data

    private var currencyChoices: [CurrencyCode] {
        var codes = CurrencyCode.common
        if !codes.contains(baseCurrency) { codes.insert(baseCurrency, at: 0) }
        if !codes.contains(currency) { codes.append(currency) }
        return codes
    }

    private var spendingAccounts: [Account] {
        household.accountList.filter { [AccountKind.current, .cash, .creditCard, .savings].contains($0.kind) }
    }

    /// Categories for the chosen type, most recently used first. Keeps the
    /// current category even if it was hidden since.
    private var orderedCategories: [BudgetCategory] {
        _ = allCategories.count
        var all = household.pickableCategories(kind.categoryKinds)
        if let category, !all.contains(category), kind.categoryKinds.contains(category.kind) {
            all.insert(category, at: 0)
        }
        let rank = Dictionary(recentCategoryIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return all.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.objectID] ?? Int.max
                let right = rank[rhs.element.objectID] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map(\.element)
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true

        rankedPlaces = PlaceStore.ranked(in: household, context: context)
        recentPlaces = PlaceStore.recent(in: household, context: context)

        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 60
        var seen = Set<NSManagedObjectID>()
        recentCategoryIDs = ((try? context.fetch(request)) ?? []).compactMap { entry in
            guard let id = entry.category?.objectID, seen.insert(id).inserted else { return nil }
            return id
        }

        if let source = mode.source {
            kind = source.kind
            currency = source.original.currency
            input = AmountInput(value: source.original.amount, currency: source.original.currency)
            if source.isForeign {
                chargedText = NSDecimalNumber(decimal: source.base).stringValue
            }
            category = source.category
            categoryChosenByUser = true
            payer = source.payer
            account = source.account ?? spendingAccounts.first
            place = source.place
            placeText = source.placeName ?? ""
            note = source.note ?? ""
            date = mode.isEditing ? (source.date ?? .now) : .now
        } else {
            currency = baseCurrency
            input = AmountInput(currency: baseCurrency)
            account = spendingAccounts.first
            payer = household.memberList.first { $0.objectID.uriRepresentation().absoluteString == lastPayerURI }
                ?? household.memberList.first
        }
    }

    private func save() {
        guard canSave, let baseAmount, let category else { return }
        let entry: LedgerEntry
        if case .edit(let existing) = mode {
            entry = existing
        } else {
            entry = LedgerEntry(context: context)
            entry.household = household
            entry.sourceRaw = EntrySource.manual.rawValue
        }

        let cleanedPlace = PlaceName.clean(placeText)
        let resolvedPlace: Place?
        if cleanedPlace.isEmpty {
            resolvedPlace = nil
        } else if let place, PlaceName.key(place.displayName) == PlaceName.key(cleanedPlace) {
            resolvedPlace = place
        } else {
            resolvedPlace = PlaceStore.findOrCreate(named: cleanedPlace, in: household, context: context)
        }

        entry.kind = kind
        entry.date = date
        entry.originalAmount = input.value.number
        entry.originalCurrency = currency.rawValue
        entry.baseAmount = baseAmount.number
        entry.category = category
        entry.account = account
        entry.payer = payer
        entry.place = resolvedPlace
        entry.payee = resolvedPlace?.name
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmedNote.isEmpty ? nil : trimmedNote
        entry.toAccount = kind == .transfer
            ? ((category.accounts as? Set<Account>)?.first ?? (category.parent?.accounts as? Set<Account>)?.first)
            : nil

        do {
            try context.save()
            saveCount += 1
            dismiss()
        } catch {
            context.rollback()
        }
    }
}

/// Two rows of swipeable category chips. Long-press to manage categories.
private struct CategoryChips: View {
    var categories: [BudgetCategory]
    @Binding var selection: BudgetCategory?
    var onManage: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(rowItems(row), id: \.objectID) { category in
                                chip(category)
                            }
                            if row == 1 {
                                Button(action: onManage) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 40, height: 40)
                                        .glassEffect(.regular.interactive(), in: .circle)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit categories")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }

    /// Splits categories across two rows, keeping the order reading left to right.
    private func rowItems(_ row: Int) -> [BudgetCategory] {
        let half = (categories.count + 1) / 2
        return row == 0 ? Array(categories.prefix(half)) : Array(categories.dropFirst(half))
    }

    private func chip(_ category: BudgetCategory) -> some View {
        let isSelected = selection == category
        return Button {
            withAnimation(.snappy) { selection = category }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.symbol)
                    .foregroundStyle(isSelected ? .white : category.color)
                Text(category.displayName)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassEffect(isSelected ? .regular.tint(category.color).interactive() : .regular.interactive(),
                         in: .capsule)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit categories…", systemImage: "slider.horizontal.3", action: onManage)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func detailChip() -> some View {
        font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        EntryEditorView(mode: .new)
            .environment(AppModel(context: PersistenceController.preview.viewContext))
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}

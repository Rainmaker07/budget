import CoreData
import SwiftUI
import TideKit

/// The Quick Add sheet: pick a type, tap in an amount, choose a category,
/// save. Paying abroad? Switch the currency and enter what the bank charged.
struct QuickAddView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var kind: EntryKind = .expense
    @State private var input = AmountInput(currency: .eur)
    @State private var currency: CurrencyCode = .eur
    @State private var chargedText = ""
    @State private var category: BudgetCategory?
    @State private var payer: Member?
    @State private var account: Account?
    @State private var date = Date.now
    @State private var payee = ""
    @State private var note = ""
    @State private var recentCategoryIDs: [NSManagedObjectID] = []
    @State private var saveCount = 0
    @FocusState private var focusedField: Field?
    @AppStorage("quickAdd.lastPayer") private var lastPayerURI = ""

    private enum Field { case charged, payee, note }

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
                VStack(spacing: 20) {
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

                    CategoryChips(
                        categories: orderedCategories,
                        selection: $category
                    )

                    details
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationTitle("New \(kind.title.lowercased())")
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
            if let category, !kind.categoryKinds.contains(category.kind) { self.category = nil }
        }
        .onChange(of: currency) {
            input.setMaxFractionDigits(currency.fractionDigits)
        }
    }

    // MARK: - Sections

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(currency.symbol())
                    .font(.tideNumber(30, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(input.displayText())
                    .font(.tideNumber(60, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: input)
                    .foregroundStyle(input.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Amount \(Money(input.value, currency).formatted())")

            Menu {
                ForEach(currencyChoices, id: \.self) { code in
                    Button {
                        currency = code
                    } label: {
                        Text("\(code.rawValue) – \(code.localizedName())")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text(currency.rawValue)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
        .padding(.vertical, 8)
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
        let shown = rate.rate.rounded(scale: 4)
        return "1 \(currency.rawValue) = \(shown.formatted()) \(baseCurrency.rawValue)"
    }

    private var details: some View {
        GlassCard(padding: 4) {
            VStack(spacing: 0) {
                detailRow("Date", icon: "calendar") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                Divider().padding(.leading, 48)
                detailRow("Paid by", icon: "person.2.fill") {
                    HStack(spacing: 6) {
                        ForEach(household.memberList, id: \.objectID) { member in
                            Button {
                                payer = member
                                lastPayerURI = member.objectID.uriRepresentation().absoluteString
                            } label: {
                                HStack(spacing: 6) {
                                    MemberAvatar(member: member, size: 20)
                                    Text(member.displayName).font(.subheadline.weight(.medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(payer == member ? member.color.opacity(0.25) : .clear, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Divider().padding(.leading, 48)
                detailRow("Account", icon: "building.columns.fill") {
                    Menu {
                        ForEach(spendingAccounts, id: \.objectID) { account in
                            Button(account.displayName) { self.account = account }
                        }
                    } label: {
                        Text(account?.displayName ?? "Choose")
                            .font(.subheadline.weight(.medium))
                    }
                }
                Divider().padding(.leading, 48)
                detailRow(kind == .income ? "From" : "Where", icon: "mappin.and.ellipse") {
                    TextField(kind == .income ? "Employer, client…" : "Shop, place…", text: $payee)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .payee)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .note }
                }
                Divider().padding(.leading, 48)
                detailRow("Note", icon: "text.alignleft") {
                    TextField("Optional", text: $note)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .note)
                        .submitLabel(.done)
                }
            }
        }
    }

    private func detailRow<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: 12) {
            if focusedField == nil {
                NumberPad { input.press($0) }
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
        .animation(.snappy, value: focusedField == nil)
    }

    private var saveTitle: String {
        guard input.value > 0 else { return "Enter an amount" }
        guard category != nil else { return "Choose a category" }
        if isForeign, chargedAmount == nil { return "Enter the \(baseCurrency.rawValue) amount" }
        return "Add \(Money(input.value, currency).formatted())"
    }

    // MARK: - Data

    private var currencyChoices: [CurrencyCode] {
        var codes = CurrencyCode.common
        if !codes.contains(baseCurrency) { codes.insert(baseCurrency, at: 0) }
        return codes
    }

    private var spendingAccounts: [Account] {
        household.accountList.filter { [AccountKind.current, .cash, .creditCard, .savings].contains($0.kind) }
    }

    /// Categories for the chosen type, most recently used first.
    private var orderedCategories: [BudgetCategory] {
        let all = household.pickableCategories(kind.categoryKinds)
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
        currency = baseCurrency
        input = AmountInput(currency: baseCurrency)
        account = spendingAccounts.first
        payer = household.memberList.first { $0.objectID.uriRepresentation().absoluteString == lastPayerURI }
            ?? household.memberList.first

        let request = NSFetchRequest<LedgerEntry>(entityName: "LedgerEntry")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 60
        var seen = Set<NSManagedObjectID>()
        recentCategoryIDs = ((try? context.fetch(request)) ?? []).compactMap { entry in
            guard let id = entry.category?.objectID, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private func save() {
        guard canSave, let baseAmount, let category else { return }
        let entry = LedgerEntry(context: context)
        entry.kind = kind
        entry.date = date
        entry.originalAmount = input.value.number
        entry.originalCurrency = currency.rawValue
        entry.baseAmount = baseAmount.number
        entry.category = category
        entry.account = account
        entry.payer = payer
        entry.household = household
        entry.sourceRaw = EntrySource.manual.rawValue
        let trimmedPayee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.payee = trimmedPayee.isEmpty ? nil : trimmedPayee
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmedNote.isEmpty ? nil : trimmedNote
        if kind == .transfer {
            entry.toAccount = (category.accounts as? Set<Account>)?.first
                ?? (category.parent?.accounts as? Set<Account>)?.first
        }

        do {
            try context.save()
            saveCount += 1
            dismiss()
        } catch {
            context.rollback()
        }
    }
}

/// Two rows of swipeable category chips.
private struct CategoryChips: View {
    var categories: [BudgetCategory]
    @Binding var selection: BudgetCategory?

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                LazyHGrid(rows: [GridItem(.fixed(40), spacing: 8), GridItem(.fixed(40), spacing: 8)], spacing: 8) {
                    ForEach(categories, id: \.objectID) { category in
                        let isSelected = selection == category
                        Button {
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
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickAddView()
            .environment(AppModel(context: PersistenceController.preview.viewContext))
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}

import SwiftUI
import TideKit

/// Creates or edits a recurring item: what, how much, how often, and
/// whether it's added automatically or waits for confirmation.
struct RecurringEditorView: View {
    enum Target: Identifiable {
        case new
        case from(LedgerEntry)
        case edit(RecurringRule)

        var id: String {
            switch self {
            case .new: "new"
            case .from(let entry): "from-\(entry.objectID.uriRepresentation().absoluteString)"
            case .edit(let rule): rule.objectID.uriRepresentation().absoluteString
            }
        }
    }

    let target: Target

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: EntryKind = .expense
    @State private var amount: Decimal = 0
    @State private var category: BudgetCategory?
    @State private var placeName = ""
    @State private var cadence: Cadence = .monthly
    @State private var interval = 1
    @State private var start = Date.now
    @State private var hasEnd = false
    @State private var end = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var autoPost = true
    @State private var isPaused = false
    @State private var payer: Member?
    @State private var account: Account?
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var existing: RecurringRule? {
        if case .edit(let rule) = target { return rule }
        return nil
    }

    private var canSave: Bool { amount > 0 && category != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Rent, Netflix)", text: $name)
                        .font(.headline)
                    Picker("Type", selection: $kind) {
                        ForEach(EntryKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    AmountTextField(title: "Amount", value: $amount, currency: model.currency)
                    Picker("Category", selection: $category) {
                        Text("Choose").tag(BudgetCategory?.none)
                        ForEach(model.household.pickableCategories(kind.categoryKinds), id: \.objectID) { option in
                            Label(option.path, systemImage: option.symbol).tag(Optional(option))
                        }
                    }
                    TextField(kind == .income ? "From (optional)" : "Place (optional)", text: $placeName)
                        .textInputAutocapitalization(.words)
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $cadence) {
                        Text("Weekly").tag(Cadence.weekly)
                        Text("Monthly").tag(Cadence.monthly)
                        Text("Yearly").tag(Cadence.yearly)
                    }
                    Stepper(cadence.title(every: interval), value: $interval, in: 1...12)
                    DatePicker(existing == nil ? "First date" : "Starts", selection: $start, displayedComponents: .date)
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date)
                    }
                }

                Section {
                    Picker("When it's due", selection: $autoPost) {
                        Text("Add automatically").tag(true)
                        Text("Ask me to confirm").tag(false)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } footer: {
                    Text(autoPost ? "Added to your transactions on its date." : "Shows up on Home to confirm or skip, handy when the amount changes.")
                }

                Section {
                    Picker("Paid by", selection: $payer) {
                        ForEach(model.household.memberList, id: \.objectID) { Text($0.displayName).tag(Optional($0)) }
                    }
                    Picker("Account", selection: $account) {
                        ForEach(model.household.accountList, id: \.objectID) { Text($0.displayName).tag(Optional($0)) }
                    }
                }

                if existing != nil {
                    Section {
                        Toggle("Paused", isOn: $isPaused)
                        Button("Delete recurring item", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("Deleting keeps transactions that were already added.")
                    }
                }
            }
            .navigationTitle(existing == nil ? "New recurring item" : "Edit recurring item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this recurring item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing {
                        RecurringStore.pending(in: model.household, context: context)
                            .filter { $0.recurringRule == existing }
                            .forEach(context.delete)
                        context.delete(existing)
                    }
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear(perform: load)
            .onChange(of: kind) {
                if let category, !kind.categoryKinds.contains(category.kind) { self.category = nil }
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        payer = model.household.memberList.first
        account = model.household.accountList.first
        switch target {
        case .new:
            break
        case .from(let entry):
            name = entry.placeName ?? entry.category?.displayName ?? ""
            kind = entry.kind
            amount = entry.base
            category = entry.category
            placeName = entry.placeName ?? ""
            start = Recurrence(cadence: .monthly, start: entry.date ?? .now).next(after: entry.date ?? .now) ?? .now
            payer = entry.payer ?? payer
            account = entry.account ?? account
        case .edit(let rule):
            name = rule.name ?? ""
            kind = rule.kind
            amount = rule.value
            category = rule.category
            placeName = rule.place?.displayName ?? ""
            cadence = rule.cadence
            interval = max(1, Int(rule.interval))
            start = rule.startDate ?? .now
            hasEnd = rule.endDate != nil
            end = rule.endDate ?? end
            autoPost = rule.autoPost
            isPaused = rule.isPaused
            payer = rule.payer ?? payer
            account = rule.account ?? account
        }
    }

    private func save() {
        let rule = existing ?? RecurringRule(context: context)
        rule.household = model.household
        rule.name = PlaceName.clean(name)
        rule.kind = kind
        rule.amount = amount.number
        rule.currencyCode = model.currency.rawValue
        rule.category = category
        rule.place = PlaceStore.findOrCreate(named: placeName, in: model.household, context: context)
        rule.cadence = cadence
        rule.interval = Int16(interval)
        rule.startDate = start
        rule.endDate = hasEnd ? end : nil
        rule.autoPost = autoPost
        rule.isPaused = isPaused
        rule.payer = payer
        rule.account = account

        // Schedule the next occurrence without re-adding past ones: after the
        // last one already added, or from today for new items.
        if let recurrence = rule.recurrence {
            let posted = ((rule.entries as? Set<LedgerEntry>) ?? []).compactMap(\.date).max()
            let startOfToday = Calendar.current.startOfDay(for: .now)
            if case .from(let entry) = target, let date = entry.date {
                entry.recurringRule = rule
                rule.nextDate = recurrence.next(after: max(date, startOfToday.addingTimeInterval(-1)))
            } else {
                rule.nextDate = recurrence.next(after: posted ?? startOfToday.addingTimeInterval(-1))
            }
        }
        try? context.save()
        RecurringStore.postDue(in: model.household, context: context)
        dismiss()
    }
}

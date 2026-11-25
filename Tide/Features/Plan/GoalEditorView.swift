import SwiftUI
import TideKit

/// Creates or edits a goal: save up, emergency fund, or pay off a debt.
struct GoalEditorView: View {
    enum Target: Identifiable {
        case new
        case edit(SavingsGoal)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let goal): goal.objectID.uriRepresentation().absoluteString
            }
        }
    }

    let target: Target

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: GoalKind = .save
    @State private var amount: Decimal = 0
    @State private var months = 6
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var category: BudgetCategory?
    @State private var startingAmount: Decimal = 0
    @State private var colorName = "teal"
    @State private var icon = "star.fill"
    @State private var confirmingDelete = false
    @State private var loaded = false

    private var existing: SavingsGoal? {
        if case .edit(let goal) = target { return goal }
        return nil
    }

    private var monthlyExpenses: Decimal {
        GoalStore.averageMonthlyExpenses(model.household, context: context)
    }

    private var effectiveTarget: Decimal {
        kind == .emergency ? (monthlyExpenses * Decimal(months)).rounded(scale: -2, mode: .up) : amount
    }

    private var canSave: Bool {
        !PlaceName.clean(name).isEmpty && effectiveTarget > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        GoalJar(progress: preview.fraction, color: TidePalette.color(named: colorName))
                            .frame(width: 30, height: 46)
                        TextField("Goal name", text: $name)
                            .font(.title3.weight(.semibold))
                    }
                    Picker("Type", selection: $kind) {
                        ForEach(GoalKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if kind == .emergency {
                        Stepper("\(months) months of expenses", value: $months, in: 1...24)
                        LabeledContent("Target", value: model.money(effectiveTarget).formatted(cents: false))
                    } else {
                        AmountTextField(title: kind == .payOff ? "Amount owed" : "Target", value: $amount, currency: model.currency)
                    }
                    AmountTextField(title: kind == .payOff ? "Already paid" : "Already saved", value: $startingAmount, currency: model.currency)
                } footer: {
                    if kind == .emergency {
                        Text("Based on your average spending of \(model.money(monthlyExpenses).formatted(cents: false)) a month. The target follows your spending.")
                    }
                }

                Section {
                    Toggle("Target date", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("By", selection: $deadline, in: Date.now..., displayedComponents: .date)
                        if let monthly = preview.monthlyNeeded(from: .now) {
                            LabeledContent("Each month", value: model.money(monthly).formatted(cents: false))
                        }
                    }
                }

                Section {
                    Picker(kind == .payOff ? "Payments to" : "Money moved to", selection: $category) {
                        Text("Not linked").tag(BudgetCategory?.none)
                        ForEach(model.household.pickableCategories(kind.categoryKinds), id: \.objectID) { option in
                            Label(option.path, systemImage: option.symbol).tag(Optional(option))
                        }
                    }
                } footer: {
                    Text("Transfers to this category count toward the goal automatically.")
                }

                Section("Color") {
                    ColorSwatchPicker(selection: $colorName)
                        .padding(.vertical, 4)
                }

                if existing != nil {
                    Section {
                        Button("Delete goal", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New goal" : "Edit goal")
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
            .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { context.delete(existing) }
                    try? context.save()
                    dismiss()
                }
            } message: {
                Text("Your transactions stay; only the goal is removed.")
            }
            .onAppear(perform: load)
            .onChange(of: kind) {
                if let category, !kind.categoryKinds.contains(category.kind) { self.category = nil }
                icon = kind.symbol
            }
        }
    }

    private var preview: GoalProgress {
        let linked = existing.map { GoalStore.saved(for: $0) - $0.saved } ?? 0
        return GoalProgress(target: effectiveTarget, saved: startingAmount + linked,
                            start: existing?.createdAt ?? .now, deadline: hasDeadline ? deadline : nil)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let goal = existing else { return }
        name = goal.displayName
        kind = goal.kind
        amount = goal.target
        months = goal.targetMonths > 0 ? Int(goal.targetMonths) : 6
        hasDeadline = goal.targetDate != nil
        deadline = goal.targetDate ?? deadline
        category = goal.category
        startingAmount = goal.saved
        colorName = goal.colorName ?? "teal"
        icon = goal.symbol
    }

    private func save() {
        let goal = existing ?? SavingsGoal(context: context)
        if existing == nil {
            goal.household = model.household
            goal.sortOrder = Int16(model.household.goalList.count)
        }
        goal.name = PlaceName.clean(name)
        goal.kind = kind
        goal.icon = icon
        goal.colorName = colorName
        goal.targetAmount = effectiveTarget.number
        goal.targetMonths = kind == .emergency ? Int16(months) : 0
        goal.savedAmount = startingAmount.number
        goal.targetDate = hasDeadline ? deadline : nil
        goal.category = category
        try? context.save()
        dismiss()
    }
}

import CoreData
import SwiftUI
import TideKit

/// Sets one category's budget for a month, with suggestions from history.
struct BudgetEditorView: View {
    @ObservedObject var category: BudgetCategory
    let month: MonthKey

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var input = AmountInput(currency: .eur)
    @State private var rollsOver = false
    @State private var lastMonth: Decimal = 0
    @State private var average: Decimal = 0
    @State private var hadBudget = false

    private var line: CategoryBudgetLine? { model.snapshot.lines[category.objectID] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: category.symbol, color: category.color, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.displayName).font(.headline)
                            Text(category.path).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.currency.symbol())
                            .font(.tideNumber(28, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(input.displayText())
                            .font(.tideNumber(54, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: input)
                            .foregroundStyle(input.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                    }
                    .frame(maxWidth: .infinity)

                    suggestions

                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $rollsOver) {
                                Label("Roll over to next month", systemImage: "arrow.uturn.forward.circle")
                            }
                            Text("Unspent money (or overspending) moves into next month's budget for \(category.displayName).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let line, line.carryover != 0 {
                                Text("\(model.money(line.carryover).formatted(signed: true)) carried into this month.")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    NumberPad { input.press($0) }
                    Button(action: save) {
                        Text(input.isEmpty && hadBudget ? "Remove budget" : "Set \(model.money(input.value).formatted(cents: false)) for \(monthName)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(input.isEmpty && !hadBudget)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private var monthName: String {
        month.firstDay().formatted(.dateTime.month(.wide))
    }

    private var suggestions: some View {
        let spent = line?.actual ?? 0
        let options: [(String, Decimal)] = [
            ("Last month", lastMonth),
            ("3-month avg", average),
            ("Spent so far", spent),
        ].filter { $0.1 > 0 }
        return HStack(spacing: 8) {
            ForEach(options, id: \.0) { option in
                Button {
                    input = AmountInput(value: option.1.rounded(scale: 0, mode: .up), currency: model.currency)
                } label: {
                    VStack(spacing: 2) {
                        Text(option.0)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(model.money(option.1).formatted(cents: false))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() {
        let existing = BudgetStore.budget(for: category, month: month, context: context)
        hadBudget = existing != nil
        input = AmountInput(value: existing?.value ?? 0, currency: model.currency)
        rollsOver = existing?.rollsOver ?? (BudgetStore.budget(for: category, month: month.previous, context: context)?.rollsOver ?? false)
        lastMonth = BudgetStore.lastMonthActual(for: category, before: month, context: context)
        average = BudgetStore.average(for: category, before: month, context: context)
    }

    private func save() {
        BudgetStore.setBudget(input.value, rollsOver: rollsOver && !input.isEmpty, for: category, month: month, context: context)
        dismiss()
    }
}

/// Moves budgeted money from one category to another this month.
struct MoveMoneyView: View {
    let month: MonthKey

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var source: BudgetCategory?
    @State private var target: BudgetCategory?
    @State private var amount: Decimal = 0

    private var sources: [BudgetCategory] {
        BudgetStore.budgetableCategories(model.household).filter { (model.snapshot.lines[$0.objectID]?.budgeted ?? 0) > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("From", selection: $source) {
                        Text("Choose").tag(BudgetCategory?.none)
                        ForEach(sources, id: \.objectID) { category in
                            Text("\(category.displayName) · \(available(category)) left").tag(Optional(category))
                        }
                    }
                    Picker("To", selection: $target) {
                        Text("Choose").tag(BudgetCategory?.none)
                        ForEach(BudgetStore.budgetableCategories(model.household).filter { $0 != source }, id: \.objectID) { category in
                            Text(category.path).tag(Optional(category))
                        }
                    }
                    AmountTextField(title: "Amount", value: $amount, currency: model.currency)
                } footer: {
                    Text("Lowers one budget and raises the other by the same amount, so your total stays the same.")
                }
            }
            .navigationTitle("Move money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move", systemImage: "checkmark") {
                        if let source, let target {
                            BudgetStore.move(amount, from: source, to: target, month: month, context: context)
                        }
                        dismiss()
                    }
                    .disabled(source == nil || target == nil || amount <= 0)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func available(_ category: BudgetCategory) -> String {
        model.money(model.snapshot.lines[category.objectID]?.remaining ?? 0).formatted(cents: false)
    }
}

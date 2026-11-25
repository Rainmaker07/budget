import CoreData
import SwiftUI
import TideKit

/// The Plan tab: this month's budgets per category, goals, and recurring
/// items. In Every Euro mode the header shows what's left to assign.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context

    @State private var editingBudget: ObjectRef<BudgetCategory>?
    @State private var goalTarget: GoalEditorView.Target?
    @State private var recurringTarget: RecurringEditorView.Target?
    @State private var movingMoney = false
    @State private var confirmingClear = false
    @State private var notice: String?

    private var snapshot: MonthSnapshot { model.snapshot }
    private var month: MonthKey { model.month }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MonthStepper()
                    PlanHeader(summary: snapshot.summary, currency: model.currency)

                    if !hasBudgets {
                        quickStartCard
                    }

                    goalsSection

                    ForEach(CategoryKind.assignable) { kind in
                        let tops = model.household.topCategories(kind)
                        if !tops.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: kind.title, detail: sectionDetail(tops))
                                ForEach(tops, id: \.objectID) { top in
                                    CategoryBudgetCard(top: top, snapshot: snapshot, currency: model.currency) { category in
                                        editingBudget = ObjectRef(object: category)
                                    }
                                }
                            }
                        }
                    }

                    recurringSection

                    Text(AppInfo.fullVersion)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .tideBackground(snapshot.summary.health)
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { planMenu }
            }
            .sheet(item: $editingBudget) { ref in
                BudgetEditorView(category: ref.object, month: month)
            }
            .sheet(item: $goalTarget) { target in
                GoalEditorView(target: target)
            }
            .sheet(item: $recurringTarget) { target in
                RecurringEditorView(target: target)
            }
            .sheet(isPresented: $movingMoney) {
                MoveMoneyView(month: month)
            }
            .confirmationDialog("Clear all budgets for \(monthName)?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear budgets", role: .destructive) {
                    BudgetStore.clear(month, household: model.household, context: context)
                }
            }
            .alert(notice ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var hasBudgets: Bool {
        snapshot.lines.values.contains { $0.budgeted > 0 }
    }

    private var monthName: String {
        month.firstDay().formatted(.dateTime.month(.wide).year())
    }

    private func sectionDetail(_ tops: [BudgetCategory]) -> String? {
        let lines = tops.flatMap(\.subtree).compactMap { snapshot.lines[$0.objectID] }
        let budgeted = lines.reduce(Decimal(0)) { $0 + $1.budgeted }
        guard budgeted > 0 else { return nil }
        return "\(model.money(budgeted).formatted(cents: false)) budgeted"
    }

    private var planMenu: some View {
        @Bindable var model = model
        return Menu {
            Section {
                Button("Copy last month", systemImage: "doc.on.doc", action: copyLastMonth)
                Button("Fill with 3-month averages", systemImage: "chart.bar.fill", action: fillAverages)
                Button("Move money", systemImage: "arrow.left.arrow.right") { movingMoney = true }
            }
            Section {
                Picker("Budgeting style", selection: $model.budgetMode) {
                    ForEach(BudgetMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Button("Clear this month", systemImage: "trash", role: .destructive) { confirmingClear = true }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Plan options")
    }

    private var quickStartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Set your budgets for \(monthName)", systemImage: "sparkles")
                    .font(.headline)
                Text("Tap any category below to set its budget, or start from your history:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Copy last month", action: copyLastMonth)
                        .buttonStyle(.glass)
                    Button("Use averages", action: fillAverages)
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func copyLastMonth() {
        let count = BudgetStore.copyPreviousMonth(into: month, household: model.household, context: context)
        notice = count == 0 ? "Last month has no budgets to copy (or they're already set)." : "Copied \(count) budgets from last month."
    }

    private func fillAverages() {
        let count = BudgetStore.fillWithAverages(month, household: model.household, context: context)
        notice = count == 0 ? "Not enough history yet: averages need spending in the last 3 months." : "Set \(count) budgets from your 3-month averages."
    }

    // MARK: - Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Goals")
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(model.household.goalList, id: \.objectID) { goal in
                            Button {
                                goalTarget = .edit(goal)
                            } label: {
                                GoalCard(goal: goal, currency: model.currency)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            goalTarget = .new
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.title2.weight(.semibold))
                                Text("New goal")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .frame(width: 120, height: 96)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }

    // MARK: - Recurring

    private var recurringSection: some View {
        let rules = RecurringStore.all(in: model.household, context: context)
        let monthly = rules.filter { !$0.isPaused }.reduce(Decimal(0)) { total, rule in
            guard rule.kind == .expense else { return total }
            switch rule.cadence {
            case .monthly: return total + rule.value / Decimal(max(1, Int(rule.interval)))
            case .weekly: return total + rule.value * Decimal(52) / Decimal(12 * max(1, Int(rule.interval)))
            case .yearly: return total + rule.value / Decimal(12 * max(1, Int(rule.interval)))
            }
        }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Recurring",
                          detail: monthly > 0 ? "≈ \(model.money(monthly).formatted(cents: false))/mo out" : nil)
            GlassCard(padding: 4) {
                VStack(spacing: 0) {
                    ForEach(rules, id: \.objectID) { rule in
                        Button {
                            recurringTarget = .edit(rule)
                        } label: {
                            RecurringRow(rule: rule, currency: model.currency)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 64)
                    }
                    Button {
                        recurringTarget = .new
                    } label: {
                        Label("Add recurring item", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Salary, rent and subscriptions are added on their date: automatically, or waiting for you to confirm on Home.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

/// Previous / next month with the month name.
struct MonthStepper: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button {
                withAnimation(.snappy) { model.month = model.month.previous }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Previous month")

            Spacer()
            VStack(spacing: 0) {
                Text(model.month.firstDay().formatted(.dateTime.month(.wide)))
                    .font(.title3.weight(.semibold))
                Text(model.month.firstDay().formatted(.dateTime.year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentTransition(.numericText())
            Spacer()

            Button {
                withAnimation(.snappy) { model.month = model.month.next }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Next month")
        }
    }
}

/// Limits: budgeted / spent / left. Every Euro: ready to assign.
private struct PlanHeader: View {
    var summary: MonthSummary
    var currency: CurrencyCode

    var body: some View {
        GlassCard(tint: TidePalette.accent(for: summary.health)) {
            switch summary.mode {
            case .limits:
                HStack(alignment: .top) {
                    stat("Budgeted", summary.expenseBudgeted)
                    stat("Spent", summary.expenseSpent)
                    stat("Left", summary.expenseBudgeted - summary.expenseSpent)
                }
                if summary.upcomingBills > 0 {
                    Label("\(Money(summary.upcomingBills, currency).formatted(cents: false)) in bills still to come this month",
                          systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            case .everyDollar:
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.headlineTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    AmountText(money: Money(summary.headline, currency), cents: false)
                        .font(.tideNumber(44, weight: .bold))
                        .foregroundStyle(summary.headline < 0 ? TidePalette.accent(for: .over) : .primary)
                    Text(summary.headline > 0 ? "Give it a job: tap a category below."
                         : summary.headline < 0 ? "More is assigned than you've received. Lower a budget."
                         : "Every euro has a job.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AmountText(money: Money(value, currency), cents: false)
                .font(.tideNumber(22, weight: .bold))
                .foregroundStyle(value < 0 ? TidePalette.accent(for: .over) : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One category with its subcategories' budgets.
private struct CategoryBudgetCard: View {
    let top: BudgetCategory
    let snapshot: MonthSnapshot
    let currency: CurrencyCode
    var onSelect: (BudgetCategory) -> Void

    var body: some View {
        let children = top.childList
        let rows = children.isEmpty ? [top] : children
        let total = rows.compactMap { snapshot.lines[$0.objectID] }
        let available = total.reduce(Decimal(0)) { $0 + $1.available }
        let actual = total.reduce(Decimal(0)) { $0 + $1.actual }

        GlassCard(padding: 4) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconBadge(systemName: top.symbol, color: top.color, size: 34)
                    Text(top.displayName)
                        .font(.headline)
                    Spacer()
                    if available > 0 || actual > 0 {
                        Text("\(Money(actual, currency).formatted(cents: false)) of \(Money(available, currency).formatted(cents: false))")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)

                ForEach(rows, id: \.objectID) { category in
                    Divider().padding(.leading, 12)
                    Button {
                        onSelect(category)
                    } label: {
                        BudgetRow(category: category, line: snapshot.lines[category.objectID],
                                  rollsOver: snapshot.rollsOver.contains(category.objectID), currency: currency,
                                  showsName: !children.isEmpty)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct BudgetRow: View {
    let category: BudgetCategory
    let line: CategoryBudgetLine?
    let rollsOver: Bool
    let currency: CurrencyCode
    var showsName = true

    var body: some View {
        let line = self.line ?? CategoryBudgetLine(kind: category.kind, budgeted: 0, actual: 0)
        let color = TidePalette.status(line.status, base: category.color)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if showsName {
                    Image(systemName: category.symbol)
                        .font(.footnote)
                        .foregroundStyle(category.color)
                        .frame(width: 20)
                    Text(category.displayName)
                        .font(.subheadline.weight(.medium))
                } else {
                    Text("Budget")
                        .font(.subheadline.weight(.medium))
                }
                if rollsOver {
                    Image(systemName: "arrow.uturn.forward.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Rolls over")
                }
                Spacer()
                Text(rightText(line))
                    .font(.subheadline.weight(line.isBudgeted ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(line.status == .over ? color : (line.isBudgeted ? .primary : .secondary))
            }
            if line.isBudgeted {
                ProgressCapsule(progress: line.progress, color: color, height: 6)
                HStack {
                    Text("\(Money(line.actual, currency).formatted(cents: false)) \(category.kind == .expense ? "spent" : "moved")")
                    if line.carryover != 0 {
                        Text("· \(Money(line.carryover, currency).formatted(cents: false, signed: true)) carried over")
                    }
                    Spacer()
                    Text("\(Money(line.available, currency).formatted(cents: false)) budget")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit budget")
    }

    private func rightText(_ line: CategoryBudgetLine) -> String {
        guard line.isBudgeted else {
            return line.actual > 0 ? "\(Money(line.actual, currency).formatted(cents: false)) · no budget" : "Set budget"
        }
        let remaining = Money(abs(line.remaining), currency).formatted(cents: false)
        return line.remaining >= 0 ? "\(remaining) left" : "\(remaining) over"
    }
}

/// A goal with its jar, progress and pace.
struct GoalCard: View {
    @ObservedObject var goal: SavingsGoal
    var currency: CurrencyCode

    var body: some View {
        let progress = GoalStore.progress(for: goal)
        HStack(spacing: 14) {
            GoalJar(progress: progress.fraction, color: goal.color)
                .frame(width: 34, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(Money(progress.saved, currency).formatted(cents: false)) of \(Money(progress.target, currency).formatted(cents: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(paceText(progress))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(paceColor(progress))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .glassEffect(.regular.tint(goal.color.opacity(0.08)).interactive(), in: .rect(cornerRadius: 24))
    }

    private func paceText(_ progress: GoalProgress) -> String {
        let monthly = progress.monthlyNeeded(from: .now).map { Money($0, currency).formatted(cents: false) }
        switch progress.pace(at: .now) {
        case .done: return "Reached 🎉"
        case .ahead: return monthly.map { "Ahead · \($0)/mo" } ?? "Ahead"
        case .onPace: return monthly.map { "On pace · \($0)/mo" } ?? "On pace"
        case .behind: return monthly.map { "Behind · \($0)/mo needed" } ?? "Behind"
        case .noDeadline: return "\(Int(progress.fraction * 100))% there"
        }
    }

    private func paceColor(_ progress: GoalProgress) -> Color {
        switch progress.pace(at: .now) {
        case .behind: TidePalette.accent(for: .watch)
        case .noDeadline: .secondary
        default: goal.color
        }
    }
}

private struct RecurringRow: View {
    @ObservedObject var rule: RecurringRule
    var currency: CurrencyCode

    var body: some View {
        HStack(spacing: 12) {
            PlaceLogo(place: rule.place, fallbackSymbol: rule.category?.symbol ?? "repeat",
                      fallbackColor: rule.category?.color ?? .gray, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(amount)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(rule.kind == .income ? TidePalette.income : .primary)
                Image(systemName: rule.autoPost ? "bolt.fill" : "hand.tap.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(rule.autoPost ? "Added automatically" : "Asks to confirm")
            }
        }
        .opacity(rule.isPaused ? 0.5 : 1)
    }

    private var detail: String {
        if rule.isPaused { return "Paused · \(rule.scheduleTitle)" }
        let next = rule.nextDate.map { "Next \($0.formatted(.dateTime.day().month(.abbreviated)))" }
        return [rule.scheduleTitle, next].compactMap { $0 }.joined(separator: " · ")
    }

    private var amount: String {
        let money = Money(rule.value, currency)
        switch rule.kind {
        case .income: return money.formatted(signed: true)
        case .expense: return (-money).formatted(signed: true)
        case .transfer: return money.formatted()
        }
    }
}

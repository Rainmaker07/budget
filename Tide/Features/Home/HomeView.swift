import SwiftUI
import TideKit

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var snapshot: MonthSnapshot { model.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HeroSummary(summary: snapshot.summary, currency: model.currency)

                    if !snapshot.expenseCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Budgets", detail: spentDetail)
                            CategoryGrid(items: snapshot.expenseCategories, currency: model.currency)
                        }
                    }

                    if !snapshot.transferCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Saving & paying off",
                                          detail: model.money(snapshot.summary.totalTransferred).formatted(cents: false))
                            TransferStrip(items: snapshot.transferCategories, currency: model.currency)
                        }
                    }

                    if !snapshot.goals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Goals")
                            GoalStrip(goals: snapshot.goals, currency: model.currency)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Recent")
                        RecentList(entries: snapshot.recentEntries)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .tideBackground(snapshot.summary.health)
            .navigationTitle(monthTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    MonthSwitcher()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HouseholdButton()
                }
            }
        }
    }

    private var monthTitle: String {
        snapshot.month.firstDay().formatted(.dateTime.month(.wide))
    }

    private var spentDetail: String {
        let spent = model.money(snapshot.summary.expenseSpent).formatted(cents: false)
        let budget = model.money(snapshot.summary.expenseBudgeted).formatted(cents: false)
        return "\(spent) of \(budget)"
    }
}

/// The headline: safe to spend (Limits) or ready to assign (Every Euro).
private struct HeroSummary: View {
    var summary: MonthSummary
    var currency: CurrencyCode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.headlineTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            AmountText(money: Money(summary.headline, currency), cents: false)
                .font(.tideNumber(64, weight: .bold))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(summary.headline < 0 ? TidePalette.accent(for: .over) : .primary)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if summary.mode == .limits, summary.expenseBudgeted > 0 {
                ProgressCapsule(progress: summary.spentFraction, color: TidePalette.accent(for: summary.health))
                    .padding(.top, 6)
                    .accessibilityLabel("\(Int(summary.spentFraction * 100)) percent of budget spent")
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        switch summary.mode {
        case .limits:
            if let daily = summary.dailyAllowance {
                return "about \(Money(daily, currency).formatted(cents: false)) a day for the rest of the month"
            }
            return summary.headline < 0 ? "Time to slow down a little" : "left this month"
        case .everyDollar:
            let income = Money(summary.incomeReceived, currency).formatted(cents: false)
            let assigned = Money(summary.totalAssigned, currency).formatted(cents: false)
            return "\(assigned) assigned of \(income) received"
        }
    }
}

/// Two-column grid of glass tiles, one per expense category.
private struct CategoryGrid: View {
    var items: [MonthSnapshot.CategoryProgress]
    var currency: CurrencyCode

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    CategoryTile(item: item, currency: currency)
                }
            }
        }
    }
}

private struct CategoryTile: View {
    var item: MonthSnapshot.CategoryProgress
    var currency: CurrencyCode

    var body: some View {
        let line = item.line
        let color = TidePalette.status(line.status, base: item.category.color)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconBadge(systemName: item.category.symbol, color: item.category.color)
                Spacer()
                ProgressRing(progress: line.progress, color: color, lineWidth: 5)
                    .frame(width: 30, height: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.category.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Group {
                    if line.available > 0 {
                        Text(remainingText(line))
                    } else {
                        Text("\(Money(line.actual, currency).formatted(cents: false)) spent")
                    }
                }
                .font(.caption)
                .foregroundStyle(line.status == .over ? color : .secondary)
                .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(item.category.color.opacity(0.08)).interactive(), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func remainingText(_ line: CategoryBudgetLine) -> String {
        let remaining = Money(abs(line.remaining), currency).formatted(cents: false)
        return line.remaining >= 0 ? "\(remaining) left" : "\(remaining) over"
    }
}

/// Savings, investments and debt payments made this month.
private struct TransferStrip: View {
    var items: [MonthSnapshot.CategoryProgress]
    var currency: CurrencyCode

    var body: some View {
        GlassCard(padding: 4) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        IconBadge(systemName: item.category.symbol, color: item.category.color, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.category.displayName).font(.subheadline.weight(.semibold))
                            Text(item.category.kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            AmountText(money: Money(item.line.actual, currency), cents: false)
                                .font(.subheadline.weight(.semibold))
                            if item.line.budgeted > 0 {
                                Text("of \(Money(item.line.budgeted, currency).formatted(cents: false))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(12)
                    if index < items.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
        }
    }
}

/// Horizontally scrolling goal cards with a filling "jar".
private struct GoalStrip: View {
    var goals: [SavingsGoal]
    var currency: CurrencyCode

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(goals, id: \.objectID) { goal in
                        GoalCard(goal: goal, currency: currency)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -16)
    }
}

private struct GoalCard: View {
    var goal: SavingsGoal
    var currency: CurrencyCode

    var body: some View {
        HStack(spacing: 14) {
            GoalJar(progress: goal.progress, color: goal.color)
                .frame(width: 34, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Label(goal.displayName, systemImage: goal.symbol)
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleOnly)
                Text("\(Money(goal.saved, currency).formatted(cents: false)) of \(Money(goal.target, currency).formatted(cents: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let monthly = goal.monthlyNeeded() {
                    Text("\(Money(monthly, currency).formatted(cents: false))/mo to stay on track")
                        .font(.caption2)
                        .foregroundStyle(goal.color)
                }
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .glassEffect(.regular.tint(goal.color.opacity(0.08)), in: .rect(cornerRadius: 24))
    }
}

/// A small capsule that fills with liquid as a goal progresses.
struct GoalJar: View {
    var progress: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .top, endPoint: .bottom))
                    .frame(height: max(6, proxy.size.height * progress))
                    .shadow(color: color.opacity(0.5), radius: 4)
            }
            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
        }
        .animation(.spring(duration: 1, bounce: 0.25), value: progress)
    }
}

private struct RecentList: View {
    var entries: [LedgerEntry]

    var body: some View {
        GlassCard(padding: 4) {
            if entries.isEmpty {
                ContentUnavailableView("No transactions yet", systemImage: "drop",
                                       description: Text("Tap Add transaction to log your first one."))
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.objectID) { index, entry in
                        EntryRow(entry: entry)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        if index < entries.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }
}

/// Picks the month shown on Home.
private struct MonthSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(0..<12, id: \.self) { offset in
                let month = MonthKey(date: .now).adding(months: -offset)
                Button(month.firstDay().formatted(.dateTime.month(.wide).year())) {
                    model.month = month
                }
            }
        } label: {
            Image(systemName: "calendar")
        }
        .accessibilityLabel("Choose month")
    }
}

/// Shows who shares the budget and lets you switch budgeting mode.
private struct HouseholdButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Section(model.household.name ?? "Household") {
                ForEach(model.household.memberList, id: \.objectID) { member in
                    Label(member.displayName, systemImage: "person.fill")
                }
            }
            Picker("Budgeting style", selection: $model.budgetMode) {
                ForEach(BudgetMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            HStack(spacing: -6) {
                ForEach(model.household.memberList.prefix(2), id: \.objectID) { member in
                    MemberAvatar(member: member, size: 26)
                }
            }
        }
        .accessibilityLabel("Household and budgeting style")
    }
}

#Preview {
    HomeView()
        .environment(AppModel(context: PersistenceController.preview.viewContext))
}

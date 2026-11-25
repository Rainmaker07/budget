import SwiftUI
import TideKit

/// A single transaction: big logo and amount, its details, how much has
/// been spent at that place, and Edit / Duplicate / Delete.
struct EntryDetailView: View {
    @ObservedObject var entry: LedgerEntry
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editorMode: EntryEditorView.Mode?
    @State private var recurringTarget: RecurringEditorView.Target?
    @State private var confirmingDelete = false

    var body: some View {
        let currency = model.currency
        ScrollView {
            VStack(spacing: 20) {
                header(currency: currency)
                detailsCard
                if entry.isPending {
                    pendingCard
                }
                if let place = entry.place {
                    placeCard(place, currency: currency)
                }
                recurringCard
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .tideBackground(model.snapshot.summary.health)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editorMode = .edit(entry) }
            }
        }
        .sheet(item: $editorMode) { mode in
            EntryEditorView(mode: mode)
        }
        .sheet(item: $recurringTarget) { target in
            RecurringEditorView(target: target)
        }
        .confirmationDialog("Delete this transaction?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                dismiss()
                context.delete(entry)
                try? context.save()
            }
        }
    }

    private func header(currency: CurrencyCode) -> some View {
        VStack(spacing: 10) {
            EntryLogo(entry: entry, size: 80)
                .padding(.top, 8)
            Text(entry.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(amountText(currency))
                .font(.tideNumber(44, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(entry.kind == .income ? TidePalette.income : .primary)
            if entry.isForeign {
                Text(entry.original.formatted())
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let date = entry.date {
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var detailsCard: some View {
        GlassCard(padding: 4) {
            VStack(spacing: 0) {
                row("Type", value: entry.kind.title, icon: "arrow.left.arrow.right")
                if let category = entry.category {
                    divider
                    HStack(spacing: 12) {
                        IconBadge(systemName: category.symbol, color: category.color, size: 28)
                        Text("Category").foregroundStyle(.secondary)
                        Spacer()
                        Text(category.path).multilineTextAlignment(.trailing)
                    }
                    .padding(12)
                }
                if let account = entry.account {
                    divider
                    row(entry.kind == .transfer ? "From" : "Account", value: account.displayName, icon: account.symbol)
                }
                if entry.kind == .transfer, let to = entry.toAccount {
                    divider
                    row("To", value: to.displayName, icon: to.symbol)
                }
                if let payer = entry.payer {
                    divider
                    HStack(spacing: 12) {
                        MemberAvatar(member: payer, size: 28)
                        Text(entry.kind == .income ? "Received by" : "Paid by").foregroundStyle(.secondary)
                        Spacer()
                        Text(payer.displayName)
                    }
                    .padding(12)
                }
                if entry.isForeign, let rate = exchangeRate {
                    divider
                    row("Exchange rate", value: rate, icon: "globe")
                }
                if let note = entry.note, !note.isEmpty {
                    divider
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Note", systemImage: "text.alignleft")
                            .foregroundStyle(.secondary)
                        Text(note)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
            }
            .font(.subheadline)
        }
    }

    private func placeCard(_ place: Place, currency: CurrencyCode) -> some View {
        let stats = PlaceStore.stats(for: place, period: .year)
        let visits = stats.visits == 1 ? "1 visit" : "\(stats.visits) visits"
        return NavigationLink {
            PlaceDetailView(place: place)
        } label: {
            HStack(spacing: 12) {
                PlaceLogo(place: place, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Money(stats.total, currency).formatted(cents: false)) spent here this year")
                        .font(.subheadline.weight(.semibold))
                    Text(visits)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    private var pendingCard: some View {
        GlassCard(padding: 14, tint: TidePalette.accent(for: .watch)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for you to confirm")
                        .font(.subheadline.weight(.semibold))
                    Text("Change the amount with Edit if it differs this time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Confirm") { RecurringStore.confirm(entry, context: context) }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    @ViewBuilder
    private var recurringCard: some View {
        if let rule = entry.recurringRule {
            Button {
                recurringTarget = .edit(rule)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "repeat")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repeats · \(rule.displayName)")
                            .font(.subheadline.weight(.semibold))
                        Text([rule.scheduleTitle, rule.nextDate.map { "next \($0.formatted(.dateTime.day().month(.abbreviated)))" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            }
            .buttonStyle(.plain)
        }
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if entry.recurringRule == nil {
                    Button {
                        recurringTarget = .from(entry)
                    } label: {
                        Label("Repeat", systemImage: "repeat")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }

                Button {
                    editorMode = .duplicate(entry)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(.red)
            }
        }
    }

    private var divider: some View {
        Divider().padding(.leading, 52)
    }

    private func row(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(12)
    }

    private func amountText(_ currency: CurrencyCode) -> String {
        let money = Money(entry.base, currency)
        switch entry.kind {
        case .income: return money.formatted(signed: true)
        case .expense: return (-money).formatted(signed: true)
        case .transfer: return money.formatted()
        }
    }

    private var exchangeRate: String? {
        let base = Money(entry.base, entry.household?.currency ?? .eur)
        guard let rate = ExchangeRate.implied(original: entry.original, converted: base) else { return nil }
        return "1 \(rate.from.rawValue) = \(rate.rate.rounded(scale: 4).formatted()) \(rate.to.rawValue)"
    }
}

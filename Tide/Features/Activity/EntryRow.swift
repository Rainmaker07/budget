import SwiftUI
import TideKit

/// One transaction: place logo (with who paid), place name, time and
/// category, amount (and the original amount when paid abroad).
struct EntryRow: View {
    @ObservedObject var entry: LedgerEntry
    /// Show the date instead of the time (for lists not grouped by day).
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            EntryLogo(entry: entry, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    if let payer = entry.payer, (entry.household?.memberList.count ?? 0) > 1 {
                        MemberAvatar(member: payer, size: 18)
                            .offset(x: 3, y: 3)
                    }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                if entry.isForeign {
                    Text(entry.original.formatted())
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var currency: CurrencyCode { entry.household?.currency ?? .eur }

    private var subtitle: String {
        let when = entry.date.map { showsDate ? $0.formatted(.dateTime.day().month(.abbreviated).year()) : $0.formatted(date: .omitted, time: .shortened) }
        var parts = [when].compactMap { $0 }
        // The category is the title when there's no place; don't repeat it.
        if entry.placeName != nil, let category = entry.category {
            parts.append(category.displayName)
        } else if entry.placeName == nil, let parent = entry.category?.parent {
            parts.append(parent.displayName)
        }
        if entry.isPending { parts.append("To confirm") }
        return parts.joined(separator: " · ")
    }

    private var amountText: String {
        let money = Money(entry.base, currency)
        switch entry.kind {
        case .income: return money.formatted(signed: true)
        case .expense: return (-money).formatted(signed: true)
        case .transfer: return money.formatted()
        }
    }

    private var amountColor: Color {
        switch entry.kind {
        case .income: TidePalette.income
        case .expense: .primary
        case .transfer: entry.category?.color ?? .secondary
        }
    }
}

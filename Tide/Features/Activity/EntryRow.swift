import SwiftUI
import TideKit

/// One transaction: icon, payee, category, who paid, amount.
struct EntryRow: View {
    @ObservedObject var entry: LedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: entry.category?.symbol ?? "questionmark",
                      color: entry.category?.color ?? .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry.category?.path ?? entry.kind.title)
                    if entry.isForeign {
                        Text("· \(entry.original.formatted())")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
                if entry.payer != nil {
                    MemberAvatar(member: entry.payer, size: 16)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currency: CurrencyCode { entry.household?.currency ?? .eur }

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

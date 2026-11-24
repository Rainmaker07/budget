import SwiftUI
import TideKit

/// A glass number pad. Uses the locale's decimal separator.
struct NumberPad: View {
    var onKey: (AmountInput.Key) -> Void

    private let rows: [[AmountInput.Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.separator, .digit(0), .delete],
    ]

    @State private var taps = 0

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(rows[row], id: \.self) { key in
                            Button {
                                taps += 1
                                onKey(key)
                            } label: {
                                label(for: key)
                                    .font(.tideNumber(26, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                            .accessibilityLabel(accessibilityLabel(for: key))
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    @ViewBuilder
    private func label(for key: AmountInput.Key) -> some View {
        switch key {
        case .digit(let digit):
            Text("\(digit)")
        case .separator:
            Text(Locale.current.decimalSeparator ?? ".")
        case .delete:
            Image(systemName: "delete.left")
                .font(.title3.weight(.medium))
        }
    }

    private func accessibilityLabel(for key: AmountInput.Key) -> String {
        switch key {
        case .digit(let digit): "\(digit)"
        case .separator: "Decimal point"
        case .delete: "Delete"
        }
    }
}

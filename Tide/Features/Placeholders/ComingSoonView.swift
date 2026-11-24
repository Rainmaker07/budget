import SwiftUI

/// Placeholder for tabs built in later milestones, listing what's coming.
struct ComingSoonView: View {
    enum Feature {
        case plan, wealth, reports

        var title: String {
            switch self {
            case .plan: "Plan"
            case .wealth: "Wealth"
            case .reports: "Reports"
            }
        }

        var icon: String {
            switch self {
            case .plan: "chart.pie.fill"
            case .wealth: "building.columns.fill"
            case .reports: "chart.xyaxis.line"
            }
        }

        var milestone: String {
            switch self {
            case .plan: "Milestone 2"
            case .wealth: "Milestone 3"
            case .reports: "Milestone 4"
            }
        }

        var items: [(String, String)] {
            switch self {
            case .plan: [
                ("Monthly budgets per category", "slider.horizontal.3"),
                ("Limits or Every Euro mode", "arrow.triangle.branch"),
                ("Goals with monthly targets", "target"),
                ("Recurring bills & income", "repeat"),
            ]
            case .wealth: [
                ("Monthly net worth history", "chart.line.uptrend.xyaxis"),
                ("Savings & investment trends", "banknote.fill"),
                ("Debt payoff planner", "calendar.badge.checkmark"),
                ("Month-end balance check-in", "checkmark.seal.fill"),
            ]
            case .reports: [
                ("Year overview", "calendar"),
                ("Where money comes from & goes", "arrow.left.arrow.right"),
                ("Cash flow report", "water.waves"),
                ("Trends & ways to improve", "lightbulb.fill"),
            ]
            }
        }
    }

    var feature: Feature
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(TidePalette.accent(for: model.snapshot.summary.health))
                        .frame(width: 96, height: 96)
                        .glassEffect(.regular, in: .circle)
                        .padding(.top, 40)

                    Text("Coming in \(feature.milestone)")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(feature.items, id: \.0) { item in
                                Label(item.0, systemImage: item.1)
                                    .font(.body.weight(.medium))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .tideBackground(model.snapshot.summary.health)
            .navigationTitle(feature.title)
        }
    }
}

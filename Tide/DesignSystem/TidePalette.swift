import SwiftUI
import TideKit

/// Named colors stored on categories, members, accounts and goals.
enum TidePalette {
    static let names = ["blue", "indigo", "purple", "pink", "red", "orange", "yellow",
                        "green", "mint", "teal", "cyan", "brown", "gray"]

    static func color(named name: String?) -> Color {
        switch name {
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "brown": .brown
        case "gray": .gray
        default: .blue
        }
    }

    /// Accent for each budget mood.
    static func accent(for health: BudgetHealth) -> Color {
        switch health {
        case .calm: Color(red: 0.36, green: 0.86, blue: 0.86)
        case .watch: Color(red: 1.0, green: 0.72, blue: 0.30)
        case .over: Color(red: 1.0, green: 0.45, blue: 0.42)
        }
    }

    /// Ring color for a single category line.
    static func status(_ status: BudgetStatus, base: Color) -> Color {
        switch status {
        case .onTrack: base
        case .nearLimit: accent(for: .watch)
        case .over: accent(for: .over)
        }
    }

    static let income = Color(red: 0.35, green: 0.85, blue: 0.55)
}

extension Font {
    /// Big rounded numbers, used for headline amounts.
    static func tideNumber(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

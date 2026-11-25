import Foundation
import TideKit

/// Launch arguments used for demos and CI screenshots, e.g.
/// `-demo YES -tab activity -quickadd YES -mode everyDollar -activity places
/// -detail YES -sheet settings`.
/// Launch arguments land in UserDefaults' argument domain automatically.
enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    /// Use an in-memory store filled with demo data.
    static var isDemo: Bool { defaults.bool(forKey: "demo") }

    static var initialTab: AppTab {
        defaults.string(forKey: "tab").flatMap(AppTab.init(rawValue:)) ?? .home
    }

    static var opensQuickAdd: Bool { defaults.bool(forKey: "quickadd") }

    /// `-activity places` opens Activity on the Places view.
    static var activityMode: ActivityView.Mode {
        defaults.string(forKey: "activity") == "places" ? .places : .transactions
    }

    /// `-detail YES` opens the newest transaction's detail page in Activity.
    static var opensLatestEntry: Bool { defaults.bool(forKey: "detail") }

    /// `-sheet settings` or `-sheet categories` opens that screen on launch.
    static var sheet: String? { defaults.string(forKey: "sheet") }

    static var budgetMode: BudgetMode? {
        defaults.string(forKey: "mode").flatMap(BudgetMode.init(rawValue:))
    }
}

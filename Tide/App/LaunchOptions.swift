import Foundation
import TideKit

/// Launch arguments used for demos and CI screenshots, e.g.
/// `-demo YES -tab activity -quickadd YES -mode everyDollar`.
/// Launch arguments land in UserDefaults' argument domain automatically.
enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    /// Use an in-memory store filled with demo data.
    static var isDemo: Bool { defaults.bool(forKey: "demo") }

    static var initialTab: AppTab {
        defaults.string(forKey: "tab").flatMap(AppTab.init(rawValue:)) ?? .home
    }

    static var opensQuickAdd: Bool { defaults.bool(forKey: "quickadd") }

    static var budgetMode: BudgetMode? {
        defaults.string(forKey: "mode").flatMap(BudgetMode.init(rawValue:))
    }
}

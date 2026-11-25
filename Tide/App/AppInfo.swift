import Foundation

/// The app's version, shown in Settings and at the bottom of Home.
/// Set in the Xcode project: MARKETING_VERSION and CURRENT_PROJECT_VERSION.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// "Tide 0.1.1 (2)"
    static var fullVersion: String { "Tide \(version) (\(build))" }
}

// swift-tools-version: 6.0
import PackageDescription

// TideKit holds Tide's pure, UI-free logic: money, currencies, months,
// category kinds and the budget math. It has no dependency on Core Data or
// SwiftUI so it can be unit-tested quickly with `swift test`.
let package = Package(
    name: "TideKit",
    platforms: [
        .iOS("27.0"),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TideKit", targets: ["TideKit"]),
    ],
    targets: [
        .target(name: "TideKit"),
        .testTarget(name: "TideKitTests", dependencies: ["TideKit"]),
    ]
)

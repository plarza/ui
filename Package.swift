// swift-tools-version: 6.4
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "AzaUI",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "AzaUI", targets: ["AzaUI"]),
        .library(name: "UITestSupport", targets: ["UITestSupport"]),
    ],
    targets: [
        .target(
            name: "AzaUI",
            // aza.chromelayout: `bun web/cli.ts assets/aza.svg --only layout --out Sources/AzaUI/Resources`.
            // Studios: `bun web/studios.ts`.
            resources: [.copy("Resources/aza.chromelayout"), .copy("Resources/Studios")],
            swiftSettings: settings
        ),
        // XCTestCase's methods are nonisolated, so the test helpers can't default to the main actor.
        .target(name: "UITestSupport", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

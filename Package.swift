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
        .target(name: "AzaUI", swiftSettings: settings),
        // XCTestCase's methods are nonisolated, so the test helpers can't default to the main actor.
        .target(name: "UITestSupport", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "AzaUI",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AzaUI", targets: ["AzaUI"]),
        .library(name: "AzaUITesting", targets: ["AzaUITesting"]),
    ],
    targets: [
        .target(name: "AzaUI", swiftSettings: settings),
        .target(name: "AzaUITesting", swiftSettings: settings),
    ]
)

// swift-tools-version: 6.4
import Foundation
import PackageDescription

let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

// AzaKit, the aza client library, from the protocol repository: released, or a local checkout of
// it with `AZA_PROTOCOL_PATH=<protocol>`.
let protocolPath = Context.environment["AZA_PROTOCOL_PATH"]
let azaKit: Package.Dependency = protocolPath.map { .package(path: $0) }
    ?? .package(url: "https://github.com/plarza/protocol", from: "0.1.0")
// A package's identity is the last component of its URL or folder.
let protocolIdentity = protocolPath.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? "protocol"

let package = Package(
    name: "AzaUI",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "AzaUI", targets: ["AzaUI"]),
        .library(name: "UITestSupport", targets: ["UITestSupport"]),
    ],
    dependencies: [azaKit],
    targets: [
        .target(
            name: "AzaUI",
            dependencies: [.product(name: "AzaKit", package: protocolIdentity)],
            // aza.chromelayout: `bun web/cli.ts assets/aza.svg --only layout --out Sources/AzaUI/Resources`.
            // Studios: `bun web/studios.ts`.
            resources: [.copy("Resources/aza.chromelayout"), .copy("Resources/Studios")],
            swiftSettings: settings
        ),
        // XCTestCase's methods are nonisolated, so the test helpers can't default to the main actor.
        .target(name: "UITestSupport", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

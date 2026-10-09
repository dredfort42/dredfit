// swift-tools-version: 6.2
import PackageDescription

// The app's own Codable sources, compiled as they are: Sources/SwiftBackupProbe
// holds SYMLINKS to ios/Dredfit/*.swift, never copies, so the probe can only
// ever speak the format the app speaks. Swift settings mirror the app target
// (Swift 6, MainActor default isolation, approachable concurrency, member
// import visibility) — the same files must compile the same way.
let package = Package(
    name: "swift-backup-probe",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../../ios/DredfitCore")
    ],
    targets: [
        .executableTarget(
            name: "SwiftBackupProbe",
            dependencies: [.product(name: "DredfitCore", package: "DredfitCore")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

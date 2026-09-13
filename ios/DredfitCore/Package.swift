// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DredfitCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DredfitCore", targets: ["DredfitCore"])
    ],
    targets: [
        .target(
            name: "DredfitCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DredfitCoreTests",
            dependencies: ["DredfitCore"],
            resources: [.process("Fixtures")]
        )
    ]
)

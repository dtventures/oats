// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Oats",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Shared business logic — no SwiftUI or AppKit
        .target(
            name: "OatsCore",
            path: "Sources/OatsCore"
        ),
        // macOS floating-panel GUI
        .executableTarget(
            name: "Oats",
            dependencies: ["OatsCore"],
            path: "Sources/GranolaFloat",
            resources: [.process("Resources")]
        ),
        // Terminal CLI
        .executableTarget(
            name: "OatsCLI",
            dependencies: [
                "OatsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OatsCLI"
        ),
        .testTarget(
            name: "OatsCoreTests",
            dependencies: ["OatsCore"],
            path: "Tests/OatsCoreTests"
        ),
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClaudeUsageKit", targets: ["ClaudeUsageKit"])
    ],
    targets: [
        .target(name: "ClaudeUsageKit", path: "Sources/ClaudeUsageKit"),
        .testTarget(
            name: "ClaudeUsageKitTests",
            dependencies: ["ClaudeUsageKit"],
            path: "Tests/ClaudeUsageKitTests"
        )
    ]
)

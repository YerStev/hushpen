// swift-tools-version: 6.2
import PackageDescription

// Keep the SDK pinned; review network surfaces before updating it.

let package = Package(
    name: "hushpen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", exact: "3.5.0")
    ],
    targets: [
        .executableTarget(
            name: "hushpen",
            dependencies: [.product(name: "Voz", package: "desert-ant-core")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

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
        // llama.cpp for the optional text cleanup, pinned to the release the
        // evaluation in eval/cleanup used. MIT licensed; no network code.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11429/llama-b11429-xcframework.zip",
            checksum: "e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174"
        ),
        .executableTarget(
            name: "hushpen",
            dependencies: [.product(name: "Voz", package: "desert-ant-core"), "llama"],
            resources: [.copy("Prompts")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "hushpenTests",
            dependencies: ["hushpen", .product(name: "Voz", package: "desert-ant-core")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

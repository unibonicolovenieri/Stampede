// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EagleFoot",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EagleFootCore", targets: ["EagleFootCore"]),
        .executable(name: "eaglefoot", targets: ["eaglefoot"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "EagleFootCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "eaglefoot",
            dependencies: [
                "EagleFootCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

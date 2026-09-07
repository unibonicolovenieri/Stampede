// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stampede",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StampedeCore", targets: ["StampedeCore"]),
        .executable(name: "stampede", targets: ["stampede"]),
        .executable(name: "StampedeApp", targets: ["StampedeApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "StampedeCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "stampede",
            dependencies: [
                "StampedeCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "StampedeApp",
            dependencies: ["StampedeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

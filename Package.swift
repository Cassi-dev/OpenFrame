// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenFrame",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenFrame", targets: ["OpenFrame"]),
        .library(name: "OpenFrameCore", targets: ["OpenFrameCore"]),
    ],
    targets: [
        .target(
            name: "OpenFrameCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "OpenFrame",
            dependencies: ["OpenFrameCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OpenFrameCoreTests",
            dependencies: ["OpenFrameCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

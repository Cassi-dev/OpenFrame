// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenCut",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpenCut", targets: ["OpenCut"]),
        .library(name: "OpenCutCore", targets: ["OpenCutCore"]),
    ],
    targets: [
        .target(
            name: "OpenCutCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "OpenCut",
            dependencies: ["OpenCutCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OpenCutCoreTests",
            dependencies: ["OpenCutCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)

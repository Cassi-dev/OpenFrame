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
        // whisper.cpp vendorizado (scripts/vendorizar-whisper.sh), para as legendas automáticas.
        // CPU com Accelerate, BLAS do Accelerate e Metal com os shaders embutidos.
        .target(
            name: "CWhisper",
            exclude: ["LICENSE", "VERSAO.md", "ggml/src/ggml-cpu/arch"],
            cSettings: [
                .headerSearchPath("ggml/src"),
                .headerSearchPath("ggml/src/ggml-cpu"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_METAL"),
                .define("GGML_USE_BLAS"),
                .define("GGML_METAL_EMBED_LIBRARY"),
                .define("GGML_METAL_NDEBUG"),
                .define("GGML_USE_ACCELERATE"),
                .define("GGML_BLAS_USE_ACCELERATE"),
                .define("ACCELERATE_NEW_LAPACK"),
                .define("ACCELERATE_LAPACK_ILP64"),
                .define("GGML_SCHED_MAX_COPIES", to: "4"),
                .define("_DARWIN_C_SOURCE"),
                .define("_XOPEN_SOURCE", to: "600"),
                .define("WHISPER_VERSION", to: "\"1.9.5\""),
                .define("NDEBUG"),
                // Otimizado também no build de depuração (testes): sem isso a CPU fica lenta demais.
                .unsafeFlags(["-O3", "-w", "-fno-objc-arc"]),
            ],
            cxxSettings: [
                .headerSearchPath("ggml/src"),
                .headerSearchPath("ggml/src/ggml-cpu"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_METAL"),
                .define("GGML_USE_BLAS"),
                .define("GGML_METAL_EMBED_LIBRARY"),
                .define("GGML_METAL_NDEBUG"),
                .define("GGML_USE_ACCELERATE"),
                .define("GGML_BLAS_USE_ACCELERATE"),
                .define("ACCELERATE_NEW_LAPACK"),
                .define("ACCELERATE_LAPACK_ILP64"),
                .define("GGML_SCHED_MAX_COPIES", to: "4"),
                .define("_DARWIN_C_SOURCE"),
                .define("_XOPEN_SOURCE", to: "600"),
                .define("WHISPER_VERSION", to: "\"1.9.5\""),
                .define("NDEBUG"),
                .unsafeFlags(["-O3", "-w"]),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
            ]
        ),
        .target(
            name: "OpenFrameCore",
            dependencies: ["CWhisper"],
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
    ],
    cxxLanguageStandard: .cxx17
)

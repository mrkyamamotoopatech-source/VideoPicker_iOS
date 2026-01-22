// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoPickerScoring",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "VideoPickerScoring",
            targets: ["VideoPickerScoring"]
        )
    ],
    targets: [
        .target(
            name: "VideoPickerScoringCore",
            path: "Sources/VideoPickerScoringCore",
            publicHeadersPath: "include",
            sources: [
                "vp_analyzer.cpp",
                "vp_metrics.cpp",
                "vp_analyzer_stub.c"
            ],
            cxxSettings: [
                .headerSearchPath("include"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "VideoPickerScoring",
            dependencies: ["VideoPickerScoringCore"],
            path: "Sources/VideoPickerScoring",
            linkerSettings: [
                .linkedLibrary("c++")
            ]
        )
    ]
)

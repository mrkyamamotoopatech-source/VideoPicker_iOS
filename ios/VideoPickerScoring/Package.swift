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
            sources: [
                "vp_analyzer.cpp",
                "vp_metrics.cpp",
                "vp_analyzer_stub.c"
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("../ios/opencv2.framework/Headers"),
                .unsafeFlags(["-std=c++17"])
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("opencv2", .when(platforms: [.iOS]))
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

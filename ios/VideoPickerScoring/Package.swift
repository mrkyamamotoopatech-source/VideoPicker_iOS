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
        .binaryTarget(
            name: "opencv2",
            path: "ThirdParty/opencv2.xcframework"
        ),
        .target(
            name: "VideoPickerScoringCore",
            dependencies: ["opencv2"],
            path: "Sources/VideoPickerScoringCore",
            sources: [
                "vp_analyzer.cpp",
                "vp_metrics.cpp",
                "vp_analyzer_stub.c"
            ],
            publicHeadersPath: "include",
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
            path: "Sources/VideoPickerScoring"
        )
    ]
)


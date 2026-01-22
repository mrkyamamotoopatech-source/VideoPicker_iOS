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
            publicHeadersPath: "include"
        ),
        .target(
            name: "VideoPickerScoring",
            dependencies: ["VideoPickerScoringCore"],
            path: "Sources/VideoPickerScoring"
        )
    ]
)

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Development Commands

## Language Rules
- すべての回答は日本語で行う
- コードコメントも日本語で説明する
- 変更理由も日本語で説明する

### iOS App (Main Target)
```bash
# Build the iOS app
xcodebuild -workspace VideoPicker.xcworkspace -scheme VideoPicker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild test -workspace VideoPicker.xcworkspace -scheme VideoPicker -destination 'platform=iOS Simulator,name=iPhone 16'

# Build for device
xcodebuild -workspace VideoPicker.xcworkspace -scheme VideoPicker -configuration Release -destination 'generic/platform=iOS' build
```

### Core C++ Library
```bash
# Build the core scoring library (from core/ directory)
cd core
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Debug ..
make

# Build CLI tool for testing
make vp_cli

# Test with CLI
./vp_cli /path/to/video.mp4
```

### Swift Package (VideoPickerScoring)
```bash
# Build Swift package (from ios/VideoPickerScoring/)
cd ios/VideoPickerScoring
swift build

# Run package tests
swift test
```

## Architecture Overview

### Three-Layer Architecture

**1. Core C++ Library (`core/`)**
- **C ABI Interface**: `vp_analyzer.h` provides C-compatible interface for cross-platform use
- **Video Analysis Engine**: `vp_analyzer.cpp` orchestrates frame analysis and metric aggregation
- **Metrics System**: `vp_metrics.h/cpp` implements extensible video quality metrics:
  - Sharpness detection (Laplacian variance)
  - Exposure clipping analysis
  - Motion blur estimation
  - Noise level estimation
  - Person blur detection (placeholder for OpenCV integration)
- **Modular Design**: New metrics can be added by implementing compute functions and updating the metrics array

**2. Swift Package Layer (`ios/VideoPickerScoring/`)**
- **C++ Bridge**: `VideoPickerScoring.swift` wraps C ABI with Swift-friendly interface
- **Memory Management**: Handles CVPixelBuffer lifecycle and unsafe pointer conversions
- **Dual Analysis Modes**: 
  - Built-in scoring using core C++ metrics
  - External person blur scores from OpenCV integration
- **Error Handling**: Swift-native error types for common failure cases

**3. iOS Application (`VideoPicker/`)**
- **SwiftUI Interface**: Modern declarative UI with `ContentView.swift` as root
- **Video Processing Pipeline**: 
  - `VideoLibraryViewModel.swift`: Photo library access and video discovery
  - `VideoScoringViewModel.swift`: Orchestrates frame extraction and quality analysis
  - `VideoDetailViewModel.swift`: Individual video analysis and editing
- **Photo Library Integration**: Uses Photos framework for access to user's video library
- **Real-time Analysis**: Background processing with progress updates

### Key Integration Points

**OpenCV Framework**: 
- Located at `ios/Frameworks/opencv2.framework/`
- Used for person detection and blur analysis in person mode
- Framework must be embedded and signed in Xcode project settings
- Requires `FRAMEWORK_SEARCH_PATHS` configuration

**Scoring Modes**:
- **Person Mode**: Uses OpenCV for person detection + core metrics for technical quality
- **Scenery Mode**: Uses only core C++ metrics (sharpness, exposure, etc.)

**Frame Processing Flow**:
1. `VideoDetailViewModel` extracts frames from video using AVFoundation
2. Frames converted to `FrameInput` (CVPixelBuffer + timestamp)
3. `VideoPickerScoring` converts to C struct format (`VpFrame`)
4. Core C++ library processes frames and returns aggregated metrics
5. Results displayed in SwiftUI interface with scoring visualization

### Configuration and Extensibility

**VpConfig Structure**: Controls analysis parameters:
- `max_frames`: Limit processing for performance
- `fps`: Sampling rate for frame extraction  
- `normalize`: Target resolution for consistent metrics
- `thresholds[]`: Good/bad boundaries for each metric type

**Adding New Metrics**: 
1. Add enum value to `VpMetricId` in `vp_analyzer.h`
2. Implement compute function in `vp_metrics.cpp`
3. Add to metrics array with appropriate threshold values
4. Swift layer automatically handles new metrics via dynamic result parsing

## Development Notes

- **Bundle Identifier**: `opatech.VideoPicker`
- **iOS Deployment Target**: iOS 14.0+
- **C++ Standard**: C++17
- **OpenCV Dependency**: Required for person blur detection, must be manually configured in Xcode
- **Testing**: Use CLI tool (`vp_cli`) for core library testing before iOS integration
- **Memory Management**: Core library uses RAII, Swift layer manages CVPixelBuffer locks carefully
- **Performance**: Frame processing happens on background queues, UI updates on main thread

## ECC（ecc@ecc プラグイン）

### 使い方
- **計画**: 機能追加・リファクタリングは `ecc:planner` エージェントで計画を作成し、承認を得てから実装する
- **実装**: `ecc:tdd-workflow` スキルに従う。テスト対象はロジック層のみ（`VideoPickerTests/`）。UI層（SwiftUI の View、`VideoPickerUITests/`）は対象外
- **ビルドエラー**: Swift は `ecc:swift-build-resolver`、C++（`core/`）は `ecc:cpp-build-resolver` で最小限の修正を行う
- **レビュー**: 実装後、Swift は `ecc:swift-reviewer`、C++ は `ecc:cpp-reviewer` と、共通で `ecc:code-reviewer` を使い、指摘を報告する
- **検証**: 完了報告の前に `ecc:verification-loop` スキルで検証する。ビルド・テストは冒頭の「Build and Development Commands」のコマンドを使う
- **小さな修正**（1〜2ファイル程度）: 計画とレビュー以外のステップは省略してよい

### リスク対策
- **コスト**: `orch-*`、`multi-*`、`gan-*`、`loop-*`、`santa-*` など、複数エージェントを連続で動かすコマンド・スキルは、明示的に指示された場合のみ使う
- **ファイル**: `docs/`、ADR、コードマップなどのドキュメントファイルは、承認なしに新規作成しない
- **設定**: リンター・フォーマッター・ビルド設定（Build Settings、署名、Podfile、Package.swift の依存、CMake のオプションなど）は変更せず、理由を説明して提案する。新規ファイルをターゲットや CMakeLists.txt に登録するための最小限の変更は可
- **規約**: ECC のルールとこの CLAUDE.md が矛盾する場合は、この CLAUDE.md を優先する。グローバルの ECC ルール（`~/.claude/rules/ecc/`）のうち、このセクションに書かれていない手順（カバレッジ80%、E2Eテスト、`security-reviewer` などのエージェント自動起動、実装前の GitHub・レジストリ検索、PRD などの計画ドキュメント生成、並列エージェント実行）は、明示的に指示された場合のみ行う
- **依存**: 新しいライブラリやパッケージの追加は提案にとどめ、承認を得る
- **報告**: 使用した `ecc:` エージェント・スキルを、作業の最後に一覧で報告する

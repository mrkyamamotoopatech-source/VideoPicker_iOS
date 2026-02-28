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
xcodebuild -project VideoPicker.xcodeproj -scheme VideoPicker -configuration Debug build

# Run tests
xcodebuild test -project VideoPicker.xcodeproj -scheme VideoPicker -destination 'platform=iOS Simulator,name=iPhone 15'

# Build for device
xcodebuild -project VideoPicker.xcodeproj -scheme VideoPicker -configuration Release -destination 'generic/platform=iOS' build
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
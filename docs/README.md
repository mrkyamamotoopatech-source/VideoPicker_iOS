# VideoPicker Scoring Library

## A) 設計

### 1. リポジトリ構成

```
core/
  include/
    vp_analyzer.h
  src/
    vp_analyzer.cpp
    vp_ffmpeg_decoder.cpp
    vp_ffmpeg_decoder.h
    vp_metrics.cpp
    vp_metrics.h
  tools/
    vp_cli.cpp
  CMakeLists.txt
ios/
  VideoPickerScoring/
    VideoPickerScoring.swift
android/
  videopicker-scoring/
    build.gradle.kts
    src/main/java/.../VideoPickerScoring.kt
    src/main/cpp/
      CMakeLists.txt
      vp_jni.cpp
samples/
  ios/
    VideoPickerScoringSample.swift
  android/
    VideoPickerScoringSample.kt
docs/
  README.md
```

### 2. C ABIヘッダ (vp_analyzer.h) とデータ構造

- `VpConfig`: fps/max_frames と各指標の `VpThreshold (good/bad)` を保持。
- `VpAggregateResult`: 各指標の mean/worst を別配列で保持。
- `VpItemResult`: `id`, `id_str`, `raw`, `score` を持ち、raw と score を両方返す。
- `VpMetricId`: 4項目は enum 化。
- `vp_create / vp_analyze_video_file / vp_destroy` を C ABI で公開。
- エラーは `VpErrorCode` の int 値で返却。

### 3. “項目追加”しやすい設計

- `MetricDefinition` に `id/threshold/compute` をまとめ、配列で保持。
- `vp_metrics.cpp` に指標の実装を分離し、
  - 新指標は compute 関数を追加して `metrics_` に追加するだけ。
- `VpAggregateResult` は `VP_MAX_ITEMS` 上限の配列なので、新規指標追加も破壊的変更を避ける。

### 4. FFmpegデコード層と解析層の分離

- `FfmpegDecoder` が動画オープンとフレーム抽出を担当。
- `AnalyzerImpl` がフレームの指標計算と集約を担当。
- デコード結果は `DecodedFrame(gray)` だけ渡すため、解析側は FFmpeg に依存しない。

## B) コア実装 (C++/FFmpeg)

### 5. FFmpegで動画を開き、指定fpsでフレーム抽出

- `FfmpegDecoder::open()` で動画ストリームを検出。
- `decode()` で `fps` 間隔で Gray フレームをサンプル。
- `max_frames` に達したら終了。

### 6. RGBA(or Gray)へ変換し、raw→score を計算

- `libswscale` を使い `GRAY8` へ変換。
- raw 指標は `vp_metrics.cpp` にまとめ、`normalize_score()` で 0..1 に正規化。

### 7. mean/worst集約

- mean: raw/score の平均。
- worst: score 最小のフレームを採用。

### 8. VpConfigで fps/max_frames/閾値を変更

- `vp_default_config` でデフォルトを埋め、アプリ側で上書き可能。
- `VpThreshold.good/bad` のみで正規化を制御。

### 9. デバッグ用CLI

- `core/tools/vp_cli.cpp` で動画入力→集約結果表示。

## C) iOS (Swift)

### 10. XCFramework生成手順 (例)

```bash
xcodebuild -create-xcframework \
  -library build/Release-iphoneos/libvp_scoring.a \
  -headers core/include \
  -output VideoPickerScoring.xcframework
```

### 11. Swiftラッパ

- `VideoPickerScoring.analyze(url:)` で C ABI を呼び出し。
- `VideoQualityAggregate` に変換して返却。

### 12. SwiftUI最小サンプル

- `samples/ios/VideoPickerScoringSample.swift` に最小 View を用意。

## D) Android (Kotlin/JNI)

### 13. JNIラッパ

- `VideoPickerScoring.analyzeVideo(filePath: String)` を JNI で実装。

### 14. CMake/Gradle例

- `android/videopicker-scoring/src/main/cpp/CMakeLists.txt`
- `android/videopicker-scoring/build.gradle.kts`

### 15. content:// → filePath ユーティリティ

- `VideoPickerScoring.copyContentUriToFile` を用意。

### 16. 最小サンプル

- `samples/android/VideoPickerScoringSample.kt` を用意。

## E) ドキュメント

### 17. iOS/Androidの組み込み手順

- iOS: XCFramework を作成し、アプリ側に追加。Cヘッダを Swift から参照。
- Android: NDK + CMake で JNI をビルドし AAR 化。

### 18. API利用例

- iOS: `VideoPickerScoring().analyze(url:)`
- Android: `VideoPickerScoring().analyzeVideo(filePath)`

### 19. よくある落とし穴

- iOS: バンドルの動画パスや権限チェック。
- Android: `content://` を必ず `filePath` に変換。
- FFmpeg: バイナリサイズが大きくなるため、不要 codec を削る。
- 実機動作: 低メモリ端末では `max_frames` を抑える。

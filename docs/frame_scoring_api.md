# Frame-based Scoring API (Proposal)

## 目的

- 動画ファイル依存を外し、フレーム画像入力へ切り替える。
- iOS/Android の標準APIで抽出したフレームを使い、コーデック/コンテナ差分の不安定さを回避する。
- スコアリングロジックの共通化・再利用性を高める。

## 基本方針

1. **入力はフレーム画像 (UIImage/Bitmap/Raw pixel)**
2. **前処理で解像度・色空間を正規化**
3. **2段階評価**
   - Stage 1: 軽量評価 (アプリ内)
   - Stage 2: 詳細評価 (ライブラリ)

## API 形

### 1. Core C API (frame input)

```c
// core/include/vp_analyzer.h

typedef struct {
  int width;
  int height;
  int stride_bytes;
  VpPixelFormat format; // VP_PIXEL_GRAY8 / VP_PIXEL_RGBA8888 / VP_PIXEL_BGRA8888 など
  const uint8_t *data;
} VpFrame;

typedef struct {
  int max_frames;
  float fps; // optional, for metadata only
  VpNormalize normalize;
  VpThreshold thresholds[VP_MAX_ITEMS];
} VpConfig;

VP_API VpHandle *vp_create(const VpConfig *config);
VP_API VpErrorCode vp_analyze_frames(
  VpHandle *handle,
  const VpFrame *frames,
  int frame_count,
  VpAggregateResult *out_result
);
VP_API void vp_destroy(VpHandle *handle);
```

**ポイント**
- `VpFrame` はバッファ情報だけを持つ (コピー不要)。
- Pixel format は最小限に絞り、アプリ側で変換・正規化を推奨。
- 連続バッファだけでなく、stride を許容する。

### 2. iOS Swift API

```swift
public struct FrameInput {
  public let pixelBuffer: CVPixelBuffer
  public let timestamp: CMTime
}

public func analyze(frames: [FrameInput]) throws -> VideoQualityAggregate
```

**iOS 側でのフレーム抽出**
- `AVAssetReader` + `AVAssetReaderTrackOutput`
- `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` から `vImage` で RGB/Gray へ変換
- 解像度を固定 (例: 短辺 360px, 長辺スケール)

### 3. Android Kotlin API

```kotlin
data class FrameInput(
  val image: Image, // MediaCodec or ImageReader
  val timestampUs: Long
)

fun analyze(frames: List<FrameInput>): VideoQualityAggregate
```

**Android 側でのフレーム抽出**
- `MediaExtractor` + `MediaCodec`
- `ImageReader` 経由で `Image` を取得
- `YUV_420_888` を `RenderScript` / `ScriptIntrinsicYuvToRGB` or `libyuv` で変換

## 2段階評価設計

### Stage 1 (アプリ内軽量評価)

- 例: シャープネス、露出、ブレ簡易評価
- N フレームの中から上位 K を選別

### Stage 2 (ライブラリ内詳細評価)

- Stage 1 で選ばれた K 枚だけを詳細スコアリング
- `vp_analyze_frames` で統一評価

## 推奨正規化

| 項目 | 推奨 | 理由 |
| --- | --- | --- |
| 色空間 | sRGB | iOS/Android で安定 | 
| 解像度 | 短辺 360/480 | 計算コスト抑制 |
| ピクセル | GRAY8 or RGBA | 単純化 |

## 期待される効果

- iPhoneのHEVC/HDRの非互換問題を回避
- Android/iOS共通化が容易
- スコアリング部分だけに集中可能

## 今後の検討事項

- `VpFrame` の lifetime とバッファ所有権 (zero-copy vs copy)
- HDR/10bit 入力の扱い (sRGB 変換 or 16bit Gray)
- GPU/Metal/RenderScript を使った前処理の高速化
- Stage 1 の共通ロジックをライブラリ側に持たせるかどうか

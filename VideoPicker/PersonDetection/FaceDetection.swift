//
//  FaceDetection.swift
//  VideoPicker
//

import CoreGraphics
import CoreVideo
import MediaPipeTasksVision
import UIKit

/// 検出した顔。boundingBoxは保存されている画素データ（回転適用前）の左上を原点とする正規化座標（0〜1）
struct DetectedFace: Equatable, Sendable {
    let boundingBox: CGRect
    let confidence: Float
}

/// 顔検出の抽象。テストでは固定値を返す実装に差し替える
protocol FaceDetecting: Sendable {
    /// 動作確認用のログに出す実装名
    var engineName: String { get }
    /// 画像の向きはimageOrientationから読み取る
    func detectFaces(in image: UIImage) throws -> [DetectedFace]
    /// 32BGRA形式のピクセルバッファを受け取る。orientationには表示時の向き（縦向き動画なら.rightなど）を渡す
    func detectFaces(in pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) throws -> [DetectedFace]
}

enum FaceDetectorError: Error {
    case modelNotFound(String)
}

/// MediaPipe Face Detector（BlazeFace short-range）による顔検出
final class MediaPipeFaceDetector: FaceDetecting, @unchecked Sendable {
    static let bundledModelName = "blaze_face_short_range"
    static let bundledModelExtension = "tflite"
    static let defaultMinDetectionConfidence: Float = 0.5

    private static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    let engineName = "MediaPipe Face Detector (\(MediaPipeFaceDetector.bundledModelName))"

    private let detector: FaceDetector
    // 採点は複数タスクから並列に呼ばれるため、検出器へのアクセスを直列化する
    private let lock = NSLock()

    init(modelPath: String, minDetectionConfidence: Float = MediaPipeFaceDetector.defaultMinDetectionConfidence) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw FaceDetectorError.modelNotFound(modelPath)
        }
        let options = FaceDetectorOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.minDetectionConfidence = minDetectionConfidence
        detector = try FaceDetector(options: options)
    }

    /// アプリに同梱したモデルで検出器を作る
    static func makeBundled(bundle: Bundle = .main) throws -> MediaPipeFaceDetector {
        guard let path = bundle.path(forResource: bundledModelName, ofType: bundledModelExtension) else {
            throw FaceDetectorError.modelNotFound("\(bundledModelName).\(bundledModelExtension)")
        }
        return try MediaPipeFaceDetector(modelPath: path)
    }

    func detectFaces(in image: UIImage) throws -> [DetectedFace] {
        guard let cgImage = image.cgImage else { return [] }
        return try detect(
            MPImage(uiImage: image),
            storedPixelSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
    }

    func detectFaces(in pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) throws -> [DetectedFace] {
        try detect(
            MPImage(pixelBuffer: pixelBuffer, orientation: orientation),
            storedPixelSize: CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
        )
    }

    /// - Parameter storedPixelSize: 回転適用前の画素データの寸法。MediaPipeは検出結果をこの座標系の
    ///   ピクセル値で返すが、MPImageのwidth/heightは向き適用後の寸法になるため、正規化には使えない
    private func detect(_ image: MPImage, storedPixelSize: CGSize) throws -> [DetectedFace] {
        let result = try lock.withLock { try detector.detect(image: image) }
        guard storedPixelSize.width > 0, storedPixelSize.height > 0 else { return [] }

        return result.detections.compactMap { detection in
            // 正規化し、画像の外にはみ出た分は切り落とす
            let normalized = CGRect(
                x: detection.boundingBox.minX / storedPixelSize.width,
                y: detection.boundingBox.minY / storedPixelSize.height,
                width: detection.boundingBox.width / storedPixelSize.width,
                height: detection.boundingBox.height / storedPixelSize.height
            ).intersection(Self.unitRect)
            guard !normalized.isNull, !normalized.isEmpty else { return nil }
            return DetectedFace(
                boundingBox: normalized,
                confidence: detection.categories.first?.score ?? 0
            )
        }
    }
}

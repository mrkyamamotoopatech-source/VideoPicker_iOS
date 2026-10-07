//
//  PersonBlurScorer.swift
//  VideoPicker
//

import CoreVideo
import os
import UIKit
import VideoToolbox

/// 顔の鮮明さを採点用の値に変換する計算
enum PersonScoring {
    /// 顔領域（64×64に揃えた後）のラプラシアン分散に対する閾値（悪い／良い）。
    /// 実機計測（顔あり6775フレーム）の分布から決めた値で、20未満は0.1%、200以上は約3割だった。
    /// 画面全体を評価するC++コアのperson_blur閾値（2／20）とは尺度が違うため別に持つ
    static let sharpnessBadThreshold: Float = 20
    static let sharpnessGoodThreshold: Float = 200
    /// 顔が写っていないフレームの人物スコア上限
    static let noFaceScoreCeiling = 0.5
    /// 顔が写っているフレームの人物スコア下限
    static let faceScoreFloor = 0.5

    /// ラプラシアン分散を0〜1に正規化する
    static func normalizedSharpness(_ raw: Float) -> Double {
        let ratio = (raw - sharpnessBadThreshold) / (sharpnessGoodThreshold - sharpnessBadThreshold)
        return Double(min(1, max(0, ratio)))
    }

    /// 人物モードの人物スコア（0〜1）。顔があれば顔の鮮明さ、なければ従来の推定値を上限付きで使う
    static func presenceScore(faceSharpness: Float?, heuristicScore: Double) -> Double {
        guard let faceSharpness else {
            return min(heuristicScore, noFaceScoreCeiling)
        }
        return faceScoreFloor + (1 - faceScoreFloor) * normalizedSharpness(faceSharpness)
    }
}

/// 1フレーム分の顔解析結果
struct FrameFaceAnalysis: Equatable, Sendable {
    let hasFace: Bool
    let faceSharpness: Float?

    static let noFace = FrameFaceAnalysis(hasFace: false, faceSharpness: nil)
}

/// 動作確認用: 顔の鮮明さ（ラプラシアン分散）がどの範囲に分布しているかの集計。採点の閾値調整に使う
struct SharpnessDistribution: Equatable, Sendable {
    /// バケットの境界値。採点の閾値（20と200）を含み、その前後の広がりも見られるようにしている
    static let bucketBounds: [Float] = [2, 20, 50, 100, 200, 500]
    static let empty = SharpnessDistribution(
        count: 0,
        minimum: nil,
        maximum: nil,
        sum: 0,
        bucketCounts: [Int](repeating: 0, count: bucketBounds.count + 1)
    )

    let count: Int
    let minimum: Float?
    let maximum: Float?
    let sum: Double
    /// bucketBoundsで区切った各範囲の件数（境界値未満、…、最後の境界値以上）
    let bucketCounts: [Int]

    var mean: Double? {
        count > 0 ? sum / Double(count) : nil
    }

    /// 値を1件加えた新しい集計を返す
    func adding(_ value: Float) -> SharpnessDistribution {
        let bucketIndex = Self.bucketBounds.firstIndex { value < $0 } ?? Self.bucketBounds.count
        let updatedBuckets = bucketCounts.enumerated().map { index, bucketCount in
            index == bucketIndex ? bucketCount + 1 : bucketCount
        }
        return SharpnessDistribution(
            count: count + 1,
            minimum: min(minimum ?? value, value),
            maximum: max(maximum ?? value, value),
            sum: sum + Double(value),
            bucketCounts: updatedBuckets
        )
    }

    /// ログ出力用の文字列
    var summaryText: String {
        guard let minimum, let maximum, let mean else { return "顔の検出なし" }
        let bounds = Self.bucketBounds.map { String(format: "%.0f", $0) }
        let labels = ["〜\(bounds[0])"]
            + zip(bounds, bounds.dropFirst()).map { "\($0)〜\($1)" }
            + ["\(bounds[bounds.count - 1])〜"]
        let buckets = zip(labels, bucketCounts).map { "\($0): \($1)件" }.joined(separator: ", ")
        return String(format: "n=%d 最小%.1f / 平均%.1f / 最大%.1f | ", count, minimum, mean, maximum) + buckets
    }
}

/// 動作確認用: 顔検出と鮮明さ評価が実際に呼ばれた回数を数える。複数タスクから同時に記録される
final class PersonDetectionStats: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        /// 顔検出が成功裏に完了した回数（顔の有無は問わない）
        let detections: Int
        /// そのうち顔が1つ以上見つかった回数
        let framesWithFace: Int
        /// 鮮明さ（ラプラシアン分散）を計算できた回数
        let sharpnessEvaluations: Int
        /// 検出や画像変換に失敗した回数
        let failures: Int

        static let zero = Snapshot(detections: 0, framesWithFace: 0, sharpnessEvaluations: 0, failures: 0)
    }

    private let lock = NSLock()
    private var current = Snapshot.zero
    private var faceSharpness = SharpnessDistribution.empty

    func snapshot() -> Snapshot {
        lock.withLock { current }
    }

    /// 顔が見つかったフレームの鮮明さの分布
    func faceSharpnessDistribution() -> SharpnessDistribution {
        lock.withLock { faceSharpness }
    }

    func recordFaceSharpness(_ value: Float) {
        lock.withLock { faceSharpness = faceSharpness.adding(value) }
    }

    /// 検出1回分を記録し、記録後の集計を返す
    @discardableResult
    func recordDetection(foundFace: Bool, evaluatedSharpness: Bool) -> Snapshot {
        lock.withLock {
            current = Snapshot(
                detections: current.detections + 1,
                framesWithFace: current.framesWithFace + (foundFace ? 1 : 0),
                sharpnessEvaluations: current.sharpnessEvaluations + (evaluatedSharpness ? 1 : 0),
                failures: current.failures
            )
            return current
        }
    }

    func recordFailure() {
        lock.withLock {
            current = Snapshot(
                detections: current.detections,
                framesWithFace: current.framesWithFace,
                sharpnessEvaluations: current.sharpnessEvaluations,
                failures: current.failures + 1
            )
        }
    }
}

/// 顔検出と顔領域の鮮明さ評価を組み合わせて、人物モードの採点材料を作る
struct PersonBlurScorer: Sendable {
    private static let logger = Logger(subsystem: "VideoPicker", category: "PersonDetection")
    /// 顔を検出したときの詳細ログを出す回数の上限（毎フレーム出すとログが埋まるため）
    private static let detailLogLimit = 5

    let detector: FaceDetecting
    let evaluator: FaceSharpnessEvaluator
    let stats = PersonDetectionStats()

    /// アプリ全体で共有するインスタンス。モデルの読み込みは初回アクセス時の1回だけ行う
    static let shared: PersonBlurScorer? = makeDefault()

    /// 同梱モデルで構成する。モデルを読めない場合はnilを返し、呼び出し側は従来の判定で採点を続ける
    static func makeDefault() -> PersonBlurScorer? {
        do {
            let scorer = PersonBlurScorer(
                detector: try MediaPipeFaceDetector.makeBundled(),
                evaluator: FaceSharpnessEvaluator(laplacian: OpenCVLaplacianVariance())
            )
            logger.notice("[PersonDetection] 初期化成功: 顔検出=\(scorer.detector.engineName, privacy: .public) / 鮮明さ評価=\(scorer.evaluator.laplacian.engineName, privacy: .public)")
            if OpenCVLaplacianVariance.linkedVersion != OpenCVLaplacianVariance.headerVersion {
                logger.error("[PersonDetection] OpenCVのヘッダ(\(OpenCVLaplacianVariance.headerVersion, privacy: .public))と実体(\(OpenCVLaplacianVariance.linkedVersion, privacy: .public))のバージョンが不一致。scripts/fetch_opencv_headers.sh のバージョンを合わせること")
            }
            return scorer
        } catch {
            logger.error("顔検出器の初期化に失敗したため従来の人物判定を使用: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// フレーム画像に顔があるか、あればその鮮明さを返す。
    /// 検出自体に失敗した場合はnilを返し、呼び出し側は従来の判定だけで採点する（「顔なし」とは区別する）
    func analyze(_ image: UIImage) -> FrameFaceAnalysis? {
        guard let cgImage = image.cgImage,
              let faces = detectedFaces({ try detector.detectFaces(in: image) }) else {
            return nil
        }
        guard !faces.isEmpty else {
            stats.recordDetection(foundFace: false, evaluatedSharpness: false)
            return .noFace
        }
        let sharpness = evaluator.sharpness(of: faces, in: cgImage)
        let recorded = stats.recordDetection(foundFace: true, evaluatedSharpness: sharpness != nil)
        logDetection(faces: faces, sharpness: sharpness, recorded: recorded)
        return FrameFaceAnalysis(hasFace: true, faceSharpness: sharpness)
    }

    /// C++コアへ渡すperson_blurの生値（大きいほど鮮明）。顔がなければフレーム全体で評価する。
    /// 動画フレームは画素データが回転していないため、表示時の向きをorientationで受け取る。
    /// 画像変換や検出に失敗した場合はnilを返す（0は「最もぼけている」を意味するため返さない）
    func personBlurRawScore(for pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) -> Float? {
        var converted: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &converted)
        guard status == noErr, let cgImage = converted else {
            Self.logger.error("ピクセルバッファの画像変換に失敗: status=\(status)")
            stats.recordFailure()
            return nil
        }
        guard let faces = detectedFaces({ try detector.detectFaces(in: pixelBuffer, orientation: orientation) }) else {
            return nil
        }
        let sharpness = evaluator.sharpness(of: faces, in: cgImage)
            ?? evaluator.sharpness(ofRegion: FaceSharpnessEvaluator.wholeFrame, in: cgImage)
        let recorded = stats.recordDetection(foundFace: !faces.isEmpty, evaluatedSharpness: sharpness != nil)
        if !faces.isEmpty {
            logDetection(faces: faces, sharpness: sharpness, recorded: recorded)
        }
        return sharpness
    }

    /// 動作確認用: どのエンジンが何回呼ばれたかを出力する。採点の区切りで呼ぶ
    func logSummary(context: String) {
        let total = stats.snapshot()
        Self.logger.notice("[PersonDetection] 集計（\(context, privacy: .public)終了時・起動後の累計）: \(detector.engineName, privacy: .public) 検出\(total.detections)回 / 顔あり\(total.framesWithFace)フレーム / \(evaluator.laplacian.engineName, privacy: .public) 鮮明さ評価\(total.sharpnessEvaluations)回 / 失敗\(total.failures)回")
        Self.logger.notice("[PersonDetection] 顔の鮮明さの分布（起動後の累計）: \(stats.faceSharpnessDistribution().summaryText, privacy: .public)")
    }

    /// 顔の鮮明さを分布に記録し、最初の数回だけ検出結果と鮮明さの値を出力する
    private func logDetection(faces: [DetectedFace], sharpness: Float?, recorded: PersonDetectionStats.Snapshot) {
        if let sharpness {
            stats.recordFaceSharpness(sharpness)
        }
        guard recorded.framesWithFace <= Self.detailLogLimit else { return }
        let confidence = faces.map(\.confidence).max() ?? 0
        let sharpnessText = sharpness.map { String(format: "%.1f", $0) } ?? "評価不能"
        Self.logger.notice("[PersonDetection] 顔を検出 #\(recorded.framesWithFace): \(detector.engineName, privacy: .public) が\(faces.count)件検出（信頼度\(confidence, format: .fixed(precision: 2))）→ \(evaluator.laplacian.engineName, privacy: .public) の鮮明さ=\(sharpnessText, privacy: .public)")
    }

    /// 検出結果を返す。検出が例外を投げた場合はログを残してnilを返す
    private func detectedFaces(_ detect: () throws -> [DetectedFace]) -> [DetectedFace]? {
        do {
            return try detect()
        } catch {
            Self.logger.error("顔検出に失敗したため従来の人物判定を使用: \(String(describing: error), privacy: .public)")
            stats.recordFailure()
            return nil
        }
    }
}

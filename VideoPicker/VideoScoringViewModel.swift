//
//  VideoScoringViewModel.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import AVFoundation
import Photos
import UIKit
#if canImport(VideoPickerScoring)
import VideoPickerScoring
#endif

struct ScoredFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let time: CMTime
    let score: Int
    var isSegmentBest: Bool = false // 区間内最高得点フラグ

    var timeLabel: String {
        formatTimestamp(time)
    }
    
    var category: String {
        guard isSegmentBest else { return "" }
        switch score {
        case 90...100: return "🏆" // 金メダル
        case 75...89:  return "🥈" // 銀メダル  
        case 60...74:  return "🥉" // 銅メダル
        default:       return ""
        }
    }
    
    // 区間ベストフラグを設定するヘルパー
    func withSegmentBest(_ isBest: Bool) -> ScoredFrame {
        var frame = self
        frame.isSegmentBest = isBest
        return frame
    }
}

enum ScoringMode {
    case person
    case scenery
}

@MainActor
final class VideoScoringViewModel: ObservableObject {
    @Published var isScoring = false
    @Published var scoredFrames: [ScoredFrame] = []
    @Published var currentProgress: Float = 0.0 // 進捗率 (0.0 - 1.0)
    @Published var currentTime: String = "0:00" // 現在の採点時間
    @Published var totalDuration: String = "0:00" // 動画の全長

    private(set) var scoringMode: ScoringMode = .person
    private var scoringTask: Task<Void, Never>?
    private var weightedScore: Int?
#if canImport(VideoPickerScoring)
    private var weightedScoreTask: Task<Int?, Never>?
#endif

    private let asset: PHAsset
    private let assetLoader: VideoAssetLoader
    private(set) var avAsset: AVAsset?
    private(set) var videoTransform: CGAffineTransform = .identity
    var highestScore: Int {
        scoredFrames.map(\.score).max() ?? 0
    }

    init(asset: PHAsset, assetLoader: VideoAssetLoader = VideoAssetLoader()) {
        self.asset = asset
        self.assetLoader = assetLoader
#if canImport(VideoPickerScoring)
        NSLog("VideoPickerScoring canImport = true")
#else
        NSLog("VideoPickerScoring canImport = false")
#endif
    }

    func rescore(for mode: ScoringMode) {
        guard mode != scoringMode else { return }
        cancelScoring()
        scoringMode = mode
        scoredFrames = []
        startScoring()
    }

    func startScoring() {
        guard scoringTask == nil, scoredFrames.isEmpty else { return }
        scoringTask = Task { [weak self] in
            guard let self else { return }
            await self.performScoring()
        }
    }

    func cancelScoring() {
        scoringTask?.cancel()
        scoringTask = nil
#if canImport(VideoPickerScoring)
        weightedScoreTask?.cancel()
        weightedScoreTask = nil
#endif
        weightedScore = nil
        isScoring = false
    }

    private func performScoring() async {
        guard !isScoring, scoredFrames.isEmpty else {
            scoringTask = nil
            return
        }
        isScoring = true
        defer {
            isScoring = false
            scoringTask = nil
            // 採点完了時に進捗を100%に
            currentProgress = 1.0
            currentTime = totalDuration
        }

        let avAsset = await assetLoader.loadAVAsset(for: asset)
        guard !Task.isCancelled else { return }
        
        // AVAssetを保存
        await MainActor.run {
            self.avAsset = avAsset
        }
        
        await scoreFrames(from: avAsset)
    }

    private func scoreFrames(from asset: AVAsset) async {
        if Task.isCancelled { return }
        
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }
        
        // 動画の全長を取得
        let duration = (try? await asset.load(.duration)) ?? asset.duration
        let totalSeconds = CMTimeGetSeconds(duration)
        
        // ビデオの向きを取得して保存
        let transform = (try? await track.load(.preferredTransform)) ?? CGAffineTransform.identity
        await MainActor.run {
            self.videoTransform = transform
            self.totalDuration = Self.formatDuration(totalSeconds)
            self.currentProgress = 0.0
            self.currentTime = "0:00"
        }
        
        do {
            let reader = try AVAssetReader(asset: asset)
            
            // サムネイルサイズで処理（メモリ効率化）
            let thumbnailSize: CGFloat = 128
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: thumbnailSize,
                kCVPixelBufferHeightKey as String: thumbnailSize
            ]
            
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            
            guard reader.startReading() else { return }
            
            startWeightedScoreLoad(for: asset)
            
            // 早期スキップ戦略の状態管理
            var adaptiveFrameSkip = 1 // フレームスキップ間隔
            var lowScoreStreak = 0   // 連続低スコア回数
            var framesProcessedSinceSkip = 0 // スキップ後の処理フレーム数
            
            // パフォーマンス統計
            let processingStartTime = Date()
            var totalFramesRead = 0
            var totalFramesProcessed = 0
            var totalFramesSkipped = 0
            var fastPersonSkipCount = 0
            
            print("🚀 [高速化開始] モード: \(scoringMode == .person ? "人物" : "風景") - 早期スキップ戦略有効")
            
            // メモリ効率的なバッチ処理
            let batchSize = 20
            var frameIndex = 0
            var topFrames: [ScoredFrame] = [] // 上位フレームを保持
            let maxKeepFrames = 200 // 最大保持フレーム数（大幅に増加）
            
            var currentBatch: [(UIImage, CMTime)] = []
            currentBatch.reserveCapacity(batchSize)
            
            while reader.status == .reading {
                if Task.isCancelled {
                    reader.cancelReading()
                    return
                }
                
                // autoreleasepoolからasync操作を移動
                let sampleBufferData: (CMSampleBuffer, CMTime, CVPixelBuffer)? = autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer(),
                          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        return nil
                    }
                    
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    return (sampleBuffer, timestamp, pixelBuffer)
                }
                
                guard let (sampleBuffer, timestamp, pixelBuffer) = sampleBufferData else {
                    continue
                }
                
                totalFramesRead += 1
                
                // 進捗更新（定期的に）
                if totalFramesRead % 30 == 0 { // 30フレームごとに更新
                    let currentSeconds = CMTimeGetSeconds(timestamp)
                    await MainActor.run {
                        if totalSeconds > 0 {
                            self.currentProgress = Float(currentSeconds / totalSeconds)
                            self.currentTime = Self.formatDuration(currentSeconds)
                        }
                    }
                }
                
                // 早期スキップ戦略: フレーム間隔調整
                if frameIndex % adaptiveFrameSkip != 0 {
                    frameIndex += 1
                    totalFramesSkipped += 1
                    continue
                }
                
                // PixelBufferからUIImageに変換（サムネイルサイズ）
                if let image = pixelBufferToUIImage(pixelBuffer, transform: transform) {
                    currentBatch.append((image, timestamp))
                }
                
                frameIndex += 1
                framesProcessedSinceSkip += 1
                
                // バッチが満杯になったら処理
                if currentBatch.count >= batchSize {
                    totalFramesProcessed += currentBatch.count
                    
                    let (processedBatch, skipInfo) = await processBatchWithEarlySkip(
                        currentBatch, 
                        topFrames: &topFrames, 
                        maxKeep: maxKeepFrames,
                        lowScoreStreak: lowScoreStreak,
                        fastPersonSkipCount: &fastPersonSkipCount
                    )
                    
                    // スキップ戦略の更新とログ
                    let oldSkip = adaptiveFrameSkip
                    lowScoreStreak = skipInfo.lowScoreStreak
                    adaptiveFrameSkip = skipInfo.adaptiveFrameSkip
                    
                    if oldSkip != adaptiveFrameSkip {
                        print("⚡ [フレームスキップ変更] \(oldSkip) → \(adaptiveFrameSkip) (低スコア連続: \(lowScoreStreak))")
                    }
                    
                    framesProcessedSinceSkip = 0
                    currentBatch.removeAll(keepingCapacity: true)
                }
            }
            
            // 残りのバッチを処理
            if !currentBatch.isEmpty {
                totalFramesProcessed += currentBatch.count
                let (_, _) = await processBatchWithEarlySkip(
                    currentBatch, 
                    topFrames: &topFrames, 
                    maxKeep: maxKeepFrames,
                    lowScoreStreak: lowScoreStreak,
                    fastPersonSkipCount: &fastPersonSkipCount
                )
            }
            
            // 最終統計ログ
            let processingTime = Date().timeIntervalSince(processingStartTime)
            let skipRate = totalFramesRead > 0 ? Double(totalFramesSkipped) / Double(totalFramesRead) * 100 : 0
            let fastSkipRate = totalFramesProcessed > 0 ? Double(fastPersonSkipCount) / Double(totalFramesProcessed) * 100 : 0
            
            print("📊 [高速化統計]")
            print("  処理時間: \(String(format: "%.2f", processingTime))秒")
            print("  総読み込み: \(totalFramesRead)フレーム")
            print("  実際処理: \(totalFramesProcessed)フレーム")
            print("  間隔スキップ: \(totalFramesSkipped)フレーム (\(String(format: "%.1f", skipRate))%)")
            print("  人物なしスキップ: \(fastPersonSkipCount)フレーム (\(String(format: "%.1f", fastSkipRate))%)")
            print("  処理効率: \(String(format: "%.1f", Double(totalFramesProcessed) / processingTime))fps")
            
            // 最終結果の確認と補完（リアルタイム更新で既に設定されているものを保持）
            await MainActor.run {
                // リアルタイム更新で蓄積されたscoredFramesに、まだ含まれていないtopFramesの要素を追加
                var allFrames = self.scoredFrames
                let existingTimes = Set(self.scoredFrames.map { $0.time })
                
                for frame in topFrames {
                    if frame.score >= 60 && !existingTimes.contains(frame.time) {
                        allFrames.append(frame)
                    }
                }
                
                // 時間順でソートして最終結果を設定
                let sortedFrames = allFrames.sorted { CMTimeCompare($0.time, $1.time) < 0 }
                
                // 最終的に区間ベストフラグを設定
                print("🔧 [最終処理] 区間ベストフラグを設定中: \(sortedFrames.count)枚")
                let maxKeepFrames = 200 // 明示的に200枚制限
                self.scoredFrames = self.selectTimeBalancedFrames(sortedFrames, maxCount: min(maxKeepFrames, sortedFrames.count))
                
                // デバッグ: 星がついたフレーム数をカウント
                let starredCount = self.scoredFrames.filter { $0.isSegmentBest }.count
                print("⭐ [最終結果] 星付きフレーム数: \(starredCount)枚")
                
                // 最低限1つは表示
                if self.scoredFrames.isEmpty && !topFrames.isEmpty {
                    let bestFrame = topFrames.max { $0.score < $1.score }!.withSegmentBest(true)
                    self.scoredFrames.append(bestFrame)
                }
            }
            
        } catch {
            NSLog("Frame scoring failed: %@", "\(error)")
        }
    }
    
    // 早期スキップ戦略情報
    private struct SkipStrategyInfo {
        let lowScoreStreak: Int
        let adaptiveFrameSkip: Int
    }
    
    /// 時間軸バランスを考慮したフレーム選択
    private func selectTimeBalancedFrames(_ frames: [ScoredFrame], maxCount: Int) -> [ScoredFrame] {
        guard frames.count > maxCount else { return frames }
        
        // 動画の開始時間と終了時間を取得
        guard let firstTime = frames.first?.time.seconds,
              let lastTime = frames.last?.time.seconds else {
            // フォールバック: 単純に高スコア順で選択
            return Array(frames.sorted { $0.score > $1.score }.prefix(maxCount))
        }
        
        let totalDuration = lastTime - firstTime
        let segmentCount = min(10, maxCount / 10) // 最大10区間、最低各区間10枚
        let segmentDuration = totalDuration / Double(segmentCount)
        let framesPerSegment = maxCount / segmentCount
        let extraFrames = maxCount % segmentCount
        
        var result: [ScoredFrame] = []
        
        print("🎯 [時間軸バランス選択] 総フレーム数: \(frames.count) → \(maxCount)枚に制限")
        print("   区間数: \(segmentCount), 区間あたり: \(framesPerSegment)枚")
        
        for i in 0..<segmentCount {
            let segmentStart = firstTime + Double(i) * segmentDuration
            let segmentEnd = firstTime + Double(i + 1) * segmentDuration
            
            // 各区間のフレームを抽出
            let segmentFrames = frames.filter { frame in
                let frameTime = frame.time.seconds
                return frameTime >= segmentStart && frameTime < segmentEnd
            }
            
            // 区間内で高スコア順にソート
            let sortedSegmentFrames = segmentFrames.sorted { $0.score > $1.score }
            
            // 各区間から指定枚数を選択（最後の区間は余剰分も追加）
            let countForThisSegment = framesPerSegment + (i < extraFrames ? 1 : 0)
            let selectedFromSegment = Array(sortedSegmentFrames.prefix(countForThisSegment))
            
            // 区間内の最高得点フレームにフラグを設定
            if let bestFrame = selectedFromSegment.first {
                let bestFrameWithFlag = bestFrame.withSegmentBest(true)
                result.append(bestFrameWithFlag)
                result.append(contentsOf: selectedFromSegment.dropFirst())
                
                print("   ⭐ 区間\(i+1)のベスト: \(bestFrame.score)点 (\(formatTimestamp(bestFrame.time))) - isSegmentBest=\(bestFrameWithFlag.isSegmentBest)")
            } else {
                result.append(contentsOf: selectedFromSegment)
            }
            
            if !selectedFromSegment.isEmpty {
                let segmentMinutes = Int(segmentStart / 60)
                let segmentSeconds = Int(segmentStart.truncatingRemainder(dividingBy: 60))
                print("   区間\(i+1) (\(segmentMinutes):\(String(format: "%02d", segmentSeconds))~): \(selectedFromSegment.count)枚選択 (最高\(selectedFromSegment.first?.score ?? 0)点)")
            }
        }
        
        // 時間順でソートして返却
        let finalResult = result.sorted { CMTimeCompare($0.time, $1.time) < 0 }
        
        print("📊 [選択完了] 最終的に\(finalResult.count)枚を時間軸バランスで選択")
        return finalResult
    }
    
    /// 時間軸バランスを考慮したフレーム選択（区間ベストフラグなし版）
    private func selectTimeBalancedFramesWithoutFlag(_ frames: [ScoredFrame], maxCount: Int) -> [ScoredFrame] {
        guard frames.count > maxCount else { return frames }
        
        // 動画の開始時間と終了時間を取得
        guard let firstTime = frames.first?.time.seconds,
              let lastTime = frames.last?.time.seconds else {
            // フォールバック: 単純に高スコア順で選択
            return Array(frames.sorted { $0.score > $1.score }.prefix(maxCount))
        }
        
        let totalDuration = lastTime - firstTime
        let segmentCount = min(10, maxCount / 10) // 最大10区間、最低各区間10枚
        let segmentDuration = totalDuration / Double(segmentCount)
        let framesPerSegment = maxCount / segmentCount
        let extraFrames = maxCount % segmentCount
        
        var result: [ScoredFrame] = []
        
        for i in 0..<segmentCount {
            let segmentStart = firstTime + Double(i) * segmentDuration
            let segmentEnd = firstTime + Double(i + 1) * segmentDuration
            
            // 各区間のフレームを抽出
            let segmentFrames = frames.filter { frame in
                let frameTime = frame.time.seconds
                return frameTime >= segmentStart && frameTime < segmentEnd
            }
            
            // 区間内で高スコア順にソート
            let sortedSegmentFrames = segmentFrames.sorted { $0.score > $1.score }
            
            // 各区間から指定枚数を選択（フラグ設定なし）
            let countForThisSegment = framesPerSegment + (i < extraFrames ? 1 : 0)
            let selectedFromSegment = Array(sortedSegmentFrames.prefix(countForThisSegment))
            
            result.append(contentsOf: selectedFromSegment)
        }
        
        // 時間順でソートして返却
        return result.sorted { CMTimeCompare($0.time, $1.time) < 0 }
    }
    
    private func processBatchWithEarlySkip(
        _ batch: [(UIImage, CMTime)], 
        topFrames: inout [ScoredFrame], 
        maxKeep: Int,
        lowScoreStreak: Int,
        fastPersonSkipCount: inout Int
    ) async -> (processedFrames: [ScoredFrame], skipInfo: SkipStrategyInfo) {
        var currentLowScoreStreak = lowScoreStreak
        var newAdaptiveFrameSkip = 1
        var processedFrames: [ScoredFrame] = []
        
        // MainActorプロパティを先にキャプチャ
        let currentWeightedScore = weightedScore
        let currentScoringMode = scoringMode
        
        var localFastPersonSkipCount = 0
        
        await withTaskGroup(of: (frame: ScoredFrame?, isFastSkip: Bool).self) { group in
            // バッチ内の各フレームを並列処理
            for (image, time) in batch {
                group.addTask { [weak self] in
                    guard let self = self else { return (frame: nil, isFastSkip: false) }
                    return autoreleasepool {
                        // 早期スキップ戦略: 人物モードで人物がいない場合は50点で即リターン
                        if currentScoringMode == .person && !self.hasPersonLikeContent(image) {
                            let timestamp = CMTimeGetSeconds(time)
                            print("🏃‍♀️ [人物なしスキップ] \(String(format: "%.2f", timestamp))秒 → 50点")
                            return (frame: ScoredFrame(image: image, time: time, score: 50), isFastSkip: true)
                        }
                        
                        let score = self.score(for: image, weightedScore: currentWeightedScore, mode: currentScoringMode)
                        return (frame: ScoredFrame(image: image, time: time, score: score), isFastSkip: false)
                    }
                }
            }
            
            // 結果を収集してリアルタイムで表示
            for await result in group {
                if let frame = result.frame {
                    processedFrames.append(frame)
                    
                    // 高速スキップカウンターを更新
                    if result.isFastSkip {
                        localFastPersonSkipCount += 1
                    }
                    
                    // 早期スキップ戦略: スコアに基づくフレーム間隔調整
                    if frame.score < 70 {
                        currentLowScoreStreak += 1
                        // 連続3回低スコアの場合は0.5秒スキップ（30fps想定で15フレーム）
                        if currentLowScoreStreak >= 3 && newAdaptiveFrameSkip == 1 {
                            let timestamp = CMTimeGetSeconds(frame.time)
                            print("🐌 [低スコア検出] \(String(format: "%.2f", timestamp))秒 - 連続\(currentLowScoreStreak)回低スコア → フレームスキップ15")
                            newAdaptiveFrameSkip = 15
                        }
                    } else {
                        if currentLowScoreStreak > 0 && newAdaptiveFrameSkip > 1 {
                            let timestamp = CMTimeGetSeconds(frame.time)
                            print("🚀 [高スコア復帰] \(String(format: "%.2f", timestamp))秒 - スコア\(frame.score) → 全フレーム処理再開")
                        }
                        currentLowScoreStreak = 0
                        newAdaptiveFrameSkip = 1 // 高スコア時は全フレーム処理
                    }
                    
                    // 60点以上のフレームのみ保持
                    if frame.score >= 60 {
                        topFrames.append(frame)
                        
                        // リアルタイムでUIを更新（区間ベストフラグはなし）
                        await MainActor.run {
                            // 既存のscoredFramesに新しいフレームを追加
                            var currentFrames = self.scoredFrames
                            // フラグを無効化したフレームを追加
                            var frameWithoutFlag = frame
                            frameWithoutFlag.isSegmentBest = false
                            currentFrames.append(frameWithoutFlag)
                            
                            // 時間の昇順でソート
                            let sortedFrames = currentFrames.sorted { CMTimeCompare($0.time, $1.time) < 0 }
                            
                            // フレーム数を制限（区間ベストフラグは設定しない）
                            if sortedFrames.count > maxKeep {
                                // 時間軸バランスを保った選択（フラグなし版）
                                self.scoredFrames = self.selectTimeBalancedFramesWithoutFlag(sortedFrames, maxCount: maxKeep)
                            } else {
                                self.scoredFrames = sortedFrames
                            }
                        }
                    }
                    
                    // topFramesも同様にメモリ制限を適用（念のため）
                    if topFrames.count > maxKeep * 2 { // scoredFramesより多めに保持
                        // 高スコアのフレームを優先的に保持
                        topFrames.sort { $0.score > $1.score }
                        topFrames = Array(topFrames.prefix(maxKeep * 2))
                    }
                }
            }
        }
        
        // グローバルカウンターに追加
        fastPersonSkipCount += localFastPersonSkipCount
        
        return (
            processedFrames: processedFrames,
            skipInfo: SkipStrategyInfo(
                lowScoreStreak: currentLowScoreStreak,
                adaptiveFrameSkip: newAdaptiveFrameSkip
            )
        )
    }
    
    private func processBatch(_ batch: [(UIImage, CMTime)], topFrames: inout [ScoredFrame], maxKeep: Int) async {
        // MainActorプロパティを先にキャプチャ
        let currentWeightedScore = weightedScore
        let currentScoringMode = scoringMode
        
        await withTaskGroup(of: ScoredFrame?.self) { group in
            // バッチ内の各フレームを並列処理
            for (image, time) in batch {
                group.addTask { [weak self] in
                    guard let self = self else { return nil }
                    return autoreleasepool {
                        let score = self.score(for: image, weightedScore: currentWeightedScore, mode: currentScoringMode)
                        return ScoredFrame(image: image, time: time, score: score)
                    }
                }
            }
            
            // 結果を収集してリアルタイムで表示
            for await result in group {
                if let frame = result {
                    // 60点以上のフレームのみ保持
                    if frame.score >= 60 {
                        topFrames.append(frame)
                        
                        // リアルタイムでUIを更新（区間ベストフラグはなし）
                        await MainActor.run {
                            // 既存のscoredFramesに新しいフレームを追加
                            var currentFrames = self.scoredFrames
                            // フラグを無効化したフレームを追加
                            var frameWithoutFlag = frame
                            frameWithoutFlag.isSegmentBest = false
                            currentFrames.append(frameWithoutFlag)
                            
                            // 時間の昇順でソート
                            let sortedFrames = currentFrames.sorted { CMTimeCompare($0.time, $1.time) < 0 }
                            
                            // フレーム数を制限（区間ベストフラグは設定しない）
                            if sortedFrames.count > maxKeep {
                                // 時間軸バランスを保った選択（フラグなし版）
                                self.scoredFrames = self.selectTimeBalancedFramesWithoutFlag(sortedFrames, maxCount: maxKeep)
                            } else {
                                self.scoredFrames = sortedFrames
                            }
                        }
                    }
                    
                    // topFramesも同様にメモリ制限を適用（念のため）
                    if topFrames.count > maxKeep * 2 { // scoredFramesより多めに保持
                        // 高スコアのフレームを優先的に保持
                        topFrames.sort { $0.score > $1.score }
                        topFrames = Array(topFrames.prefix(maxKeep * 2))
                    }
                }
            }
        }
    }
    
    private nonisolated func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer, transform: CGAffineTransform) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        // ビデオのtransformに基づいて適切なUIImage.Orientationを決定
        let orientation = Self.imageOrientation(from: transform)
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
    
    private nonisolated static func imageOrientation(from transform: CGAffineTransform) -> UIImage.Orientation {
        // CGAffineTransformからUIImage.Orientationに変換
        let angle = atan2(transform.b, transform.a) * 180.0 / .pi
        
        switch Int(angle) {
        case 90:
            return .right
        case -90, 270:
            return .left
        case 180:
            return .down
        default:
            return .up
        }
    }
    
    // オリジナル解像度のフレーム画像を生成（簡易版）
    func generateOriginalFrameImage(at time: CMTime) async -> UIImage? {
        guard let avAsset = self.avAsset else { return nil }
        
        do {
            let imageGenerator = AVAssetImageGenerator(asset: avAsset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
            
            let cgImage = try await imageGenerator.image(at: time).image
            return UIImage(cgImage: cgImage)
        } catch {
            NSLog("オリジナル画像生成エラー: %@", "\(error)")
            return nil
        }
    }
    

    private func startWeightedScoreLoad(for asset: AVAsset) {
#if canImport(VideoPickerScoring)
        weightedScoreTask?.cancel()
        weightedScore = nil
        let mode = scoringMode
        let task = Task.detached { [asset] in
            await Self.computeWeightedScore(from: asset, mode: mode)
        }
        weightedScoreTask = task
        Task { [weak self] in
            guard let self else { return }
            let score = await task.value
            if Task.isCancelled { return }
            await MainActor.run {
                self.weightedScore = score
            }
        }
#endif
    }


    private nonisolated func score(for image: UIImage, weightedScore: Int?, mode: ScoringMode) -> Int {
        let frameScore = fallbackScore(for: image, mode: mode)
        guard let weightedScore else { return frameScore }
        let blended = (Double(weightedScore) * 0.7 + Double(frameScore) * 0.3).rounded()
        return min(100, max(0, Int(blended)))
    }

    private nonisolated func fallbackScore(for image: UIImage, mode: ScoringMode) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let targetSize = 32
        let bytesPerPixel = 4
        let bytesPerRow = targetSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: targetSize * targetSize * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: targetSize,
            height: targetSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        var luminance = [Double](repeating: 0, count: targetSize * targetSize)
        var sum = Double(0)
        var sumSquares = Double(0)
        for index in 0..<targetSize * targetSize {
            let offset = index * bytesPerPixel
            let red = Double(pixels[offset]) / 255.0
            let green = Double(pixels[offset + 1]) / 255.0
            let blue = Double(pixels[offset + 2]) / 255.0
            let value = red * 0.2126 + green * 0.7152 + blue * 0.0722
            luminance[index] = value
            sum += value
            sumSquares += value * value
        }

        let count = Double(luminance.count)
        let average = sum / count
        let variance = max(0, (sumSquares / count) - (average * average))
        let contrast = min(variance / 0.05, 1)

        // より厳密なエッジ検出（ラプラシアンフィルタベース）
        var laplacianSum = Double(0)
        var laplacianCount = Double(0)
        
        for y in 1..<(targetSize - 1) {
            for x in 1..<(targetSize - 1) {
                let center = y * targetSize + x
                let current = luminance[center]
                
                // ラプラシアンフィルタ（8近傍）
                let neighbors = [
                    luminance[center - targetSize - 1], luminance[center - targetSize], luminance[center - targetSize + 1],
                    luminance[center - 1], luminance[center + 1],
                    luminance[center + targetSize - 1], luminance[center + targetSize], luminance[center + targetSize + 1]
                ]
                
                let laplacian = abs(8.0 * current - neighbors.reduce(0, +))
                laplacianSum += laplacian
                laplacianCount += 1
            }
        }
        
        let laplacianAverage = laplacianCount > 0 ? laplacianSum / laplacianCount : 0
        let edge = min(laplacianAverage / 0.3, 1) // より高い閾値でシャープネスを厳格判定

        // 白飛び検出（高輝度ピクセルの割合）
        let overexposurePenalty = calculateOverexposurePenalty(luminance: luminance)
        
        // ボケ検出（エッジの鮮明度）- より厳密な基準
        let sharpnessScore = min(edge / 0.25, 1.0) // より高い閾値でボケ画像を厳しく判定
        
        // 人物検出のヒューリスティック（改良版）
        let centerPersonScore = calculatePersonHeuristic(luminance: luminance, targetSize: targetSize)
        
        let quality: Double
        switch mode {
        case .person:
            // 人物モード: シャープネスを最重要視（ボケ画像を厳しく評価）
            let baseQuality = (0.10 * average) + (0.15 * contrast) + (0.55 * sharpnessScore) + (0.20 * centerPersonScore)
            quality = baseQuality * (1.0 - overexposurePenalty) // 白飛びでペナルティ
        case .scenery:
            // 風景モード: 全体品質を重視
            quality = (0.4 * average) + (0.4 * contrast) + (0.2 * sharpnessScore)
        }
        
        let score = 55 + Int((quality * 45).rounded())
        return min(100, max(0, score))
    }
    
    private nonisolated func calculateOverexposurePenalty(luminance: [Double]) -> Double {
        // 白飛び（過露出）を検出
        let overexposedCount = luminance.filter { $0 > 0.9 }.count
        let overexposedRatio = Double(overexposedCount) / Double(luminance.count)
        
        // 20%以上が白飛びしている場合は大きなペナルティ
        if overexposedRatio > 0.2 {
            return min(overexposedRatio, 0.8) // 最大80%のペナルティ
        } else if overexposedRatio > 0.1 {
            return overexposedRatio * 0.5 // 軽微なペナルティ
        }
        return 0.0
    }
    
    // 早期スキップ用の軽量人物検出（16x16で高速チェック）
    private nonisolated func hasPersonLikeContent(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        // 超高速チェック用の小さなサイズ
        let quickSize = 16
        let bytesPerPixel = 4
        let bytesPerRow = quickSize * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: quickSize * quickSize * bytesPerPixel)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: quickSize,
            height: quickSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false // 人物なしと判定
        }
        
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: quickSize, height: quickSize))
        
        var luminance = [Double](repeating: 0, count: quickSize * quickSize)
        for index in 0..<quickSize * quickSize {
            let offset = index * bytesPerPixel
            let red = Double(pixels[offset]) / 255.0
            let green = Double(pixels[offset + 1]) / 255.0
            let blue = Double(pixels[offset + 2]) / 255.0
            let value = red * 0.2126 + green * 0.7152 + blue * 0.0722
            luminance[index] = value
        }
        
        // 中央部分の分散をチェック（人物らしいかどうかの簡易判定）
        let centerX = quickSize / 2
        let centerY = quickSize / 2
        let radius = quickSize / 4
        
        var centerSum = 0.0
        var validPixels = 0
        
        for y in (centerY - radius)..<(centerY + radius) {
            for x in (centerX - radius)..<(centerX + radius) {
                if y >= 0 && y < quickSize && x >= 0 && x < quickSize {
                    let index = y * quickSize + x
                    let value = luminance[index]
                    
                    // 白飛びや真っ黒でないピクセル
                    if value > 0.1 && value < 0.9 {
                        centerSum += value
                        validPixels += 1
                    }
                }
            }
        }
        
        // 有効なピクセルが半分以上ある場合のみ人物候補とみなす
        let totalCenterPixels = (radius * 2) * (radius * 2)
        let hasPersonContent = validPixels > totalCenterPixels / 2
        
        // デバッグ用: 10%の確率でログ出力（大量ログを避けるため）
        if Int.random(in: 1...10) == 1 {
            let validRatio = Double(validPixels) / Double(totalCenterPixels) * 100
            print("👁️ [軽量人物検出] 有効ピクセル: \(validPixels)/\(totalCenterPixels) (\(String(format: "%.1f", validRatio))%) → \(hasPersonContent ? "人物あり" : "人物なし")")
        }
        
        return hasPersonContent
    }
    
    /// 秒数を分:秒形式にフォーマット
    private static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    private nonisolated func calculatePersonHeuristic(luminance: [Double], targetSize: Int) -> Double {
        // 中央部分に人物がいる可能性をヒューリスティックに計算（改良版）
        let centerX = targetSize / 2
        let centerY = targetSize / 2
        let radius = targetSize / 4
        
        var centerVariance = 0.0
        var centerSum = 0.0
        var centerCount = 0
        var validPixels = 0 // 白飛びしていないピクセル数
        
        // 中央部の輝度分散を計算（白飛びピクセルを除外）
        for y in (centerY - radius)..<(centerY + radius) {
            for x in (centerX - radius)..<(centerX + radius) {
                if y >= 0 && y < targetSize && x >= 0 && x < targetSize {
                    let index = y * targetSize + x
                    let value = luminance[index]
                    
                    // 白飛び（>0.9）や真っ黒（<0.1）なピクセルは除外
                    if value > 0.1 && value < 0.9 {
                        centerSum += value
                        validPixels += 1
                    }
                    centerCount += 1
                }
            }
        }
        
        // 有効なピクセルが少なすぎる場合は低評価
        if validPixels < centerCount / 2 {
            return 0.1
        }
        
        if validPixels > 0 {
            let centerMean = centerSum / Double(validPixels)
            var sumSquares = 0.0
            
            for y in (centerY - radius)..<(centerY + radius) {
                for x in (centerX - radius)..<(centerX + radius) {
                    if y >= 0 && y < targetSize && x >= 0 && x < targetSize {
                        let index = y * targetSize + x
                        let value = luminance[index]
                        
                        if value > 0.1 && value < 0.9 {
                            let diff = value - centerMean
                            sumSquares += diff * diff
                        }
                    }
                }
            }
            centerVariance = sumSquares / Double(validPixels)
            
            // 適度な分散（0.02-0.08）が人物らしい
            if centerVariance >= 0.02 && centerVariance <= 0.08 {
                return min(centerVariance / 0.05, 1.0)
            }
        }
        
        return 0.2 // デフォルト低評価
    }

#if canImport(VideoPickerScoring)
    private nonisolated static func computeWeightedScore(from asset: AVAsset, mode: ScoringMode) async -> Int? {
        if Task.isCancelled { return nil }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        do {
            let reader = try AVAssetReader(asset: asset)
            let maxDimension: CGFloat = 128
            let outputSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: maxDimension,
                kCVPixelBufferHeightKey as String: maxDimension
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else {
                return nil
            }

            var config = VideoPickerScoring.defaultConfig()
            config.log_frame_details = 1
            let scorer = try VideoPickerScoring(config: config)
            print("📊 [VideoScoring] OpenCVによる動画採点を開始: モード=\(mode == .person ? "人物検出" : "風景")")

            let chunkSize = 12
            var frames: [FrameInput] = []
            frames.reserveCapacity(chunkSize)
            var totalFrames = 0
            var scoreSums: [String: Float] = [:]
            var rawSums: [String: Float] = [:]
            let targetSampleCount = Int.max
            let duration = (try? await asset.load(.duration)) ?? asset.duration
            let durationSeconds = CMTimeGetSeconds(duration)
            let nominalFrameRate = (try? await track.load(.nominalFrameRate)) ?? track.nominalFrameRate
            let frameRate = max(nominalFrameRate, 1)
            let estimatedFrames = durationSeconds.isFinite ? durationSeconds * Double(frameRate) : Double(targetSampleCount)
            let sampleStride = 1
            var frameIndex = 0

            func merge(_ result: VideoQualityAggregate, frameCount: Int) {
                let weight = Float(frameCount)
                totalFrames += frameCount
                for item in result.mean {
                    scoreSums[item.id, default: 0] += item.score * weight
                    rawSums[item.id, default: 0] += item.raw * weight
                }
            }

            func analyzeChunk() throws {
                guard !frames.isEmpty else { return }
                let result: VideoQualityAggregate
                switch mode {
                case .person:
                    let personBlurScores = frames.map { frame in
                        Self.heuristicPersonBlurScore(from: frame.pixelBuffer)
                    }
                    NSLog(
                        "VideoPickerScoring person mode: using heuristic person-blur scores. count=%d",
                        personBlurScores.count
                    )
                    result = try scorer.analyze(frames: frames, personBlurScores: personBlurScores)
                    print("🎯 [PersonMode] フレーム\(frames.count)枚の採点完了 - person_blur含む総合採点")
                case .scenery:
                    result = try scorer.analyze(frames: frames)
                    print("🌅 [SceneryMode] フレーム\(frames.count)枚の採点完了 - OpenCVなしの基本採点")
                }
                
                // 採点結果の詳細ログ
                print("📈 [採点結果] 平均スコア:")
                for item in result.mean {
                    print("  - \(item.id): score=\(String(format: "%.3f", item.score)), raw=\(String(format: "%.3f", item.raw))")
                }
                
                merge(result, frameCount: frames.count)
                frames.removeAll(keepingCapacity: true)
            }

            while reader.status == .reading {
                if Task.isCancelled {
                    reader.cancelReading()
                    return nil
                }
                autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer(),
                          let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        return
                    }
                    defer { frameIndex += 1 }
                    guard frameIndex % sampleStride == 0 else { return }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    frames.append(FrameInput(pixelBuffer: pixelBuffer, timestamp: timestamp))
                }
                if frames.count >= chunkSize {
                    try analyzeChunk()
                }
            }

            if reader.status == .failed {
                return nil
            }

            try analyzeChunk()

            guard totalFrames > 0 else {
                NSLog("VideoPickerScoring skipped: no frames extracted")
                return nil
            }

            let orderedIds = scoreSums.keys.sorted()
            let meanItems = orderedIds.map { id -> VideoQualityItem in
                let meanScore = (scoreSums[id] ?? 0) / Float(totalFrames)
                let meanRaw = (rawSums[id] ?? 0) / Float(totalFrames)
                return VideoQualityItem(id: id, score: meanScore, raw: meanRaw)
            }
            NSLog("VideoPickerScoring analyze succeeded: meanCount=%d", meanItems.count)
            let score = Self.weightedScore(from: meanItems, mode: mode)
            
            // OpenCV使用状況の最終ログ
            let hasPersonBlur = meanItems.contains { $0.id == "person_blur" }
            print("✅ [動画採点完了] モード: \(mode == .person ? "人物検出" : "風景"), 総フレーム数: \(totalFrames)")
            print("🔍 [OpenCV状況] person_blur指標: \(hasPersonBlur ? "有効" : "無効") - OpenCV\(hasPersonBlur ? "使用中" : "未使用")")
            print("🏆 [最終スコア] 加重スコア: \(score ?? 0)")
            
            Self.logScoringDetails(items: meanItems, weightedScore: score, mode: mode)
            return score
        } catch {
            if case let VideoPickerScoringError.analyzeFailed(code) = error {
                let message = Self.videoPickerScoringErrorMessage(for: code)
                NSLog(
                    "VideoPickerScoring analyze failed: code=%d (%@)",
                    code,
                    message
                )
            } else {
                NSLog("VideoPickerScoring analyze failed: %@", "\(error)")
            }
            return nil
        }
    }
#endif

#if canImport(VideoPickerScoring)
    private nonisolated static func weightedScore(from items: [VideoQualityItem], mode: ScoringMode) -> Int? {
        let weights: [String: Float]
        switch mode {
        case .person:
            weights = [
                "sharpness": 0.15,
                "motion_blur": 0.20,
                "exposure": 0.10,
                "noise": 0.05,
                "person_blur": 0.50
            ]
        case .scenery:
            weights = [
                "sharpness": 0.40,
                "motion_blur": 0.10,
                "exposure": 0.40,
                "noise": 0.08,
                "person_blur": 0.02
            ]
        }
        let scores = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.score) })
        let requiredKeys = ["sharpness", "motion_blur", "exposure", "noise", "person_blur"]
        guard requiredKeys.allSatisfy({ scores[$0] != nil }) else { return nil }

        let total = weights.reduce(Float(0)) { partial, item in
            let score = max(0, min(scores[item.key] ?? 0, 1))
            return partial + score * item.value
        }
        return Int((total * 100).rounded())
    }

    private nonisolated static func logScoringDetails(items: [VideoQualityItem], weightedScore: Int?, mode: ScoringMode) {
        let detailString = items
            .map {
                let scoreText = String(format: "%.3f", $0.score)
                let rawText = String(format: "%.3f", $0.raw)
                return "\($0.id)=\(scoreText) raw=\(rawText)"
            }
            .joined(separator: ", ")
        let scoreText = weightedScore.map(String.init) ?? "nil"
        NSLog("VideoPickerScoring details (mode=%@): %@ weightedScore=%@", "\(mode)", detailString, scoreText)
    }

    private nonisolated static func videoPickerScoringErrorMessage(for code: Int32) -> String {
        switch code {
        case 1:
            return "invalid argument"
        case 2:
            return "allocation failure"
        case 3:
            return "ffmpeg error"
        case 4:
            return "decode error"
        case 5:
            return "unsupported frame input"
        default:
            return "unknown error"
        }
    }

    private nonisolated static func heuristicPersonBlurScore(from pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let sampleStride = max(1, min(width, height) / 64)

        var count = 0
        var mean = 0.0
        var m2 = 0.0
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in stride(from: 0, to: height, by: sampleStride) {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: sampleStride) {
                let pixel = row.advanced(by: x * 4)
                let b = Double(pixel[0])
                let g = Double(pixel[1])
                let r = Double(pixel[2])
                let luma = 0.114 * b + 0.587 * g + 0.299 * r
                count += 1
                let delta = luma - mean
                mean += delta / Double(count)
                let delta2 = luma - mean
                m2 += delta * delta2
            }
        }

        guard count > 1 else { return 0 }
        let variance = m2 / Double(count - 1)
        return Float(sqrt(variance) * 4.0)
    }
#endif
}

private func formatTimestamp(_ time: CMTime) -> String {
    let totalSeconds = max(time.seconds, 0)
    let totalMilliseconds = Int((totalSeconds * 1000).rounded(.down))
    let minutes = totalMilliseconds / 60000
    let seconds = (totalMilliseconds % 60000) / 1000
    let milliseconds = totalMilliseconds % 1000
    return InfoPlistStrings.formatted("VP_Format_Timestamp", minutes, seconds, milliseconds)
}

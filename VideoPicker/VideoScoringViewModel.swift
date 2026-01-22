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

    var timeLabel: String {
        formatTimestamp(time)
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

    private(set) var scoringMode: ScoringMode = .person
    private var scoringTask: Task<Void, Never>?
#if canImport(VideoPickerScoring)
    private var weightedScoreTask: Task<ScoringSummary?, Never>?
#endif

    private let asset: PHAsset
    private let assetLoader: VideoAssetLoader
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
        }

        let avAsset = await assetLoader.loadAVAsset(for: asset)
        guard !Task.isCancelled else { return }
        await scoreFrames(from: avAsset)
    }

    private func scoreFrames(from asset: AVAsset) async {
        if Task.isCancelled { return }
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sampleCount = 18
        var bestFrame: ScoredFrame?
        let weightedScore = await loadWeightedScore(from: asset)

        for index in 0..<sampleCount {
            if Task.isCancelled { return }
            let seconds = durationSeconds * Double(index + 1) / Double(sampleCount + 1)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? await generateImage(with: generator, at: time) {
                if Task.isCancelled { return }
                let score = score(for: image, weightedScore: weightedScore)
                let frame = ScoredFrame(image: image, time: time, score: score)
                if frame.score >= 60 {
                    scoredFrames.append(frame)
                }
                if bestFrame == nil || frame.score > (bestFrame?.score ?? 0) {
                    bestFrame = frame
                }
            }
        }

        if scoredFrames.isEmpty, let bestFrame {
            scoredFrames.append(bestFrame)
        }
    }

    private func generateImage(with generator: AVAssetImageGenerator, at time: CMTime) async throws -> UIImage {
        try Task.checkCancellation()
        let cgImage = try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "ImageGenerator", code: 1))
                }
            }
        }
        try Task.checkCancellation()
        return UIImage(cgImage: cgImage)
    }

    private func score(for image: UIImage, weightedScore: Int?) -> Int {
        let frameScore = fallbackScore(for: image)
        guard let weightedScore else { return frameScore }
        let blended = (Double(weightedScore) * 0.7 + Double(frameScore) * 0.3).rounded()
        return min(100, max(0, Int(blended)))
    }

    private func fallbackScore(for image: UIImage) -> Int {
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

        var edgeSum = Double(0)
        var edgeCount = Double(0)
        for y in 0..<targetSize {
            for x in 0..<targetSize {
                let index = y * targetSize + x
                let current = luminance[index]
                if x + 1 < targetSize {
                    edgeSum += abs(current - luminance[index + 1])
                    edgeCount += 1
                }
                if y + 1 < targetSize {
                    edgeSum += abs(current - luminance[index + targetSize])
                    edgeCount += 1
                }
            }
        }
        let edgeAverage = edgeCount > 0 ? edgeSum / edgeCount : 0
        let edge = min(edgeAverage / 0.2, 1)

        let quality = (0.3 * average) + (0.4 * contrast) + (0.3 * edge)
        let score = 55 + Int((quality * 45).rounded())
        return min(100, max(0, score))
    }

    private func loadWeightedScore(from asset: AVAsset) async -> Int? {
#if canImport(VideoPickerScoring)
        let mode = scoringMode
        let summaryTask = Task.detached { () async -> ScoringSummary? in
            if Task.isCancelled { return nil }
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }
            do {
                let reader = try AVAssetReader(asset: asset)
                let outputSettings: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
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

                let chunkSize = 24
                var frames: [FrameInput] = []
                frames.reserveCapacity(chunkSize)
                var totalFrames = 0
                var scoreSums: [String: Float] = [:]
                var rawSums: [String: Float] = [:]

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
                    let result = try scorer.analyze(frames: frames)
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
                return ScoringSummary(items: meanItems, score: score)
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
        weightedScoreTask = summaryTask
        let summary = await summaryTask.value
        weightedScoreTask = nil

        if Task.isCancelled { return nil }
        guard let summary else {
            return nil
        }
        logScoringDetails(items: summary.items, weightedScore: summary.score, mode: mode)
        return summary.score
#else
        return nil
#endif
    }

#if canImport(VideoPickerScoring)
    private struct ScoringSummary {
        let items: [VideoQualityItem]
        let score: Int?
    }
#endif

#if canImport(VideoPickerScoring)
    private nonisolated static func weightedScore(from items: [VideoQualityItem], mode: ScoringMode) -> Int? {
        let weights: [String: Float]
        switch mode {
        case .person:
            weights = [
                "sharpness": 0.15,
                "motion_blur": 0.45,
                "exposure": 0.30,
                "noise": 0.10
            ]
        case .scenery:
            weights = [
                "sharpness": 0.35,
                "motion_blur": 0.20,
                "exposure": 0.30,
                "noise": 0.15
            ]
        }
        let scores = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.score) })
        let requiredKeys = ["sharpness", "motion_blur", "exposure", "noise"]
        guard requiredKeys.allSatisfy({ scores[$0] != nil }) else { return nil }

        let total = weights.reduce(Float(0)) { partial, item in
            let score = max(0, min(scores[item.key] ?? 0, 1))
            return partial + score * item.value
        }
        return Int((total * 100).rounded())
    }

    private func logScoringDetails(items: [VideoQualityItem], weightedScore: Int?, mode: ScoringMode) {
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

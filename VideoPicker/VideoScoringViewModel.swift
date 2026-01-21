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

    private let asset: PHAsset
    private let assetLoader: VideoAssetLoader
    var highestScore: Int {
        scoredFrames.map(\.score).max() ?? 0
    }

    init(asset: PHAsset, assetLoader: VideoAssetLoader = VideoAssetLoader()) {
        self.asset = asset
        self.assetLoader = assetLoader
    }

    func rescore(for mode: ScoringMode) async {
        guard mode != scoringMode else { return }
        guard !isScoring else { return }
        scoringMode = mode
        scoredFrames = []
        await startScoring()
    }

    func startScoring() async {
        guard !isScoring, scoredFrames.isEmpty else { return }
        isScoring = true
        defer { isScoring = false }

        let avAsset = await assetLoader.loadAVAsset(for: asset)
        await scoreFrames(from: avAsset)
    }

    private func scoreFrames(from asset: AVAsset) async {
        let duration = (try? await asset.load(.duration)) ?? .zero
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sampleCount = 18
        var bestFrame: ScoredFrame?

        for index in 0..<sampleCount {
            let seconds = durationSeconds * Double(index + 1) / Double(sampleCount + 1)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? await generateImage(with: generator, at: time) {
                let score = await libraryScore(for: asset, at: time) ?? 0
                let frame = ScoredFrame(image: image, time: time, score: score)
                if frame.score >= 75 {
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
        let cgImage = try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                if let cgImage {
                    continuation.resume(returning: cgImage)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "ImageGenerator", code: 1))
                }
            }
        }
        return UIImage(cgImage: cgImage)
    }

    private func libraryScore(for asset: AVAsset, at time: CMTime) async -> Int? {
#if canImport(VideoPickerScoring)
        guard let urlAsset = asset as? AVURLAsset else { return nil }
        do {
            var config = VideoPickerScoring.defaultConfig()
            config.start_time_sec = Float(time.seconds)
            config.max_frames = 3
            config.fps = 3.0
            let scorer = try VideoPickerScoring(config: config)
            let result = try scorer.analyze(url: urlAsset.url)
            return weightedScore(from: result.mean, mode: scoringMode)
        } catch {
            return nil
        }
#else
        return nil
#endif
    }

#if canImport(VideoPickerScoring)
    private func weightedScore(from items: [VideoQualityItem], mode: ScoringMode) -> Int? {
        let weights: [String: Float]
        switch mode {
        case .person:
            weights = [
                "person_blur": 0.35,
                "motion_blur": 0.35,
                "exposure": 0.20,
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
        var total = Float(0)
        var weightSum = Float(0)
        for (key, weight) in weights {
            guard let score = scores[key] else { continue }
            total += max(0, min(score, 1)) * weight
            weightSum += weight
        }
        guard weightSum > 0 else { return nil }
        return Int(((total / weightSum) * 100).rounded())
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

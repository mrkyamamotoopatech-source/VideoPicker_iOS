//
//  VideoScoringViewModel.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import AVFoundation
import CoreMedia
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
#if canImport(VideoPickerScoring)
        NSLog("VideoPickerScoring canImport = true")
#else
        NSLog("VideoPickerScoring canImport = false")
#endif
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
        let weightedScore = await loadWeightedScore(from: asset)

        for index in 0..<sampleCount {
            let seconds = durationSeconds * Double(index + 1) / Double(sampleCount + 1)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? await generateImage(with: generator, at: time) {
                let score = score(for: image, weightedScore: weightedScore)
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
        guard let urlAsset = asset as? AVURLAsset else {
            NSLog("VideoPickerScoring skipped: AVAsset is not AVURLAsset")
            return nil
        }
        do {
            let scorer = try VideoPickerScoring()
            let meanItems = try await analyzeVideo(for: urlAsset, scorer: scorer)
            NSLog("VideoPickerScoring analyze succeeded: meanCount=%d", meanItems.count)
            let score = weightedScore(from: meanItems, mode: scoringMode)
            logScoringDetails(items: meanItems, weightedScore: score, mode: scoringMode)
            return score
        } catch {
            if case let VideoPickerScoringError.analyzeFailed(code) = error {
                let message = videoPickerScoringErrorMessage(for: code)
                NSLog(
                    "VideoPickerScoring analyze failed: code=%d (%@) url=%@",
                    code,
                    message,
                    urlAsset.url.path
                )
            } else {
                NSLog("VideoPickerScoring analyze failed: %@", "\(error)")
            }
            return nil
        }
#else
        return nil
#endif
    }

#if canImport(VideoPickerScoring)
    private func analyzeVideo(for asset: AVURLAsset, scorer: VideoPickerScoring) async throws -> [VideoQualityItem] {
        await logAssetDetails(asset, context: "initial")
        if let exportURL = try await exportToH264IfNeeded(asset: asset, force: false) {
            defer { try? FileManager.default.removeItem(at: exportURL) }
            NSLog("VideoPickerScoring analyze uses transcoded asset: %@", exportURL.path)
            do {
                return try scorer.analyze(url: exportURL).mean
            } catch {
                NSLog("VideoPickerScoring analyze failed on transcoded asset: %@ error=%@", exportURL.path, "\(error)")
                throw error
            }
        }

        do {
            return try scorer.analyze(url: asset.url).mean
        } catch {
            NSLog("VideoPickerScoring analyze failed on original asset: %@ error=%@", asset.url.path, "\(error)")
            if case let VideoPickerScoringError.analyzeFailed(code) = error, code == 5,
               let exportURL = try? await exportToH264IfNeeded(asset: asset, force: true) {
                defer { try? FileManager.default.removeItem(at: exportURL) }
                NSLog("VideoPickerScoring analyze retry with transcoded asset: %@", exportURL.path)
                do {
                    return try scorer.analyze(url: exportURL).mean
                } catch {
                    NSLog(
                        "VideoPickerScoring analyze failed after transcode retry: %@ error=%@",
                        exportURL.path,
                        "\(error)"
                    )
                    throw error
                }
            }
            throw error
        }
    }

    private func exportToH264IfNeeded(asset: AVAsset, force: Bool) async throws -> URL? {
        if !force, !(try await needsTranscode(asset: asset)) {
            return nil
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "VideoPicker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Export session failed"])
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("videopicker-transcode-\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        do {
            if #available(iOS 18, *) {
                try await exportSession.export(to: outputURL, as: .mp4)
            } else {
                try await exportLegacy(exportSession)
            }
        } catch {
            let status = exportSession.status.rawValue
            let errorDescription = exportSession.error?.localizedDescription ?? "unknown"
            NSLog(
                "VideoPickerScoring export failed: status=%d error=%@ output=%@",
                status,
                errorDescription,
                outputURL.path
            )
            throw error
        }

        return outputURL
    }

    private func needsTranscode(asset: AVAsset) async throws -> Bool {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            return false
        }
        let formatDescriptions = try await track.load(.formatDescriptions)
        guard let formatDescription = formatDescriptions.first else {
            return false
        }
        let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
        return codecType != kCMVideoCodecType_H264
    }

    @available(iOS, deprecated: 18.0)
    private func exportLegacy(_ exportSession: AVAssetExportSession) async throws {
        struct ExportSessionBox: @unchecked Sendable {
            let session: AVAssetExportSession
        }
        let sessionBox = ExportSessionBox(session: exportSession)

        try await withCheckedThrowingContinuation { continuation in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(throwing: sessionBox.session.error ?? NSError(domain: "VideoPicker", code: 3))
                case .cancelled:
                    continuation.resume(throwing: NSError(domain: "VideoPicker", code: 4))
                default:
                    continuation.resume(throwing: NSError(domain: "VideoPicker", code: 5))
                }
            }
        }
    }

    private func logAssetDetails(_ asset: AVURLAsset, context: String) async {
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let duration = (try? await asset.load(.duration)) ?? .zero
        NSLog(
            "VideoPickerScoring asset details (%@): url=%@ duration=%.2fs videoTracks=%d audioTracks=%d",
            context,
            asset.url.path,
            duration.seconds,
            videoTracks.count,
            audioTracks.count
        )

        if let track = videoTracks.first {
            let formatDescriptions = (try? await track.load(.formatDescriptions)) ?? []
            if let formatDescription = formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                let fourCC = fourCCString(for: codecType)
                let dimensions = (try? await track.load(.naturalSize)) ?? .zero
                let nominalFrameRate = (try? await track.load(.nominalFrameRate)) ?? 0
                NSLog(
                    "VideoPickerScoring asset details (%@): codec=%@ size=%.0fx%.0f fps=%.2f",
                    context,
                    fourCC,
                    dimensions.width,
                    dimensions.height,
                    nominalFrameRate
                )
            } else {
                NSLog("VideoPickerScoring asset details (%@): formatDescription missing", context)
            }
        } else {
            NSLog("VideoPickerScoring asset details (%@): no video track", context)
        }
    }

    private func fourCCString(for codecType: FourCharCode) -> String {
        let chars: [CChar] = [
            CChar((codecType >> 24) & 0xFF),
            CChar((codecType >> 16) & 0xFF),
            CChar((codecType >> 8) & 0xFF),
            CChar(codecType & 0xFF),
            0
        ]
        return String(cString: chars)
    }
#endif

#if canImport(VideoPickerScoring)
    private func weightedScore(from items: [VideoQualityItem], mode: ScoringMode) -> Int? {
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
            .map { "\($0.id)=\($0.score)" }
            .joined(separator: ", ")
        let scoreText = weightedScore.map(String.init) ?? "nil"
        NSLog("VideoPickerScoring details (mode=%@): %@ weightedScore=%@", "\(mode)", detailString, scoreText)
    }

    private func videoPickerScoringErrorMessage(for code: Int32) -> String {
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
            return "unsupported video or codec"
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

//
//  VideoScoringView.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import AVFoundation
import Photos
import SwiftUI
import UIKit
#if canImport(VideoPickerScoring)
import VideoPickerScoring
#endif

struct VideoScoringView: View {
    let item: VideoItem

    @StateObject private var viewModel: VideoScoringViewModel
    @State private var isPersonScoring = true

    init(item: VideoItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: VideoScoringViewModel(asset: item.asset))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isScoring {
                ProgressView("採点中…")
                    .padding(.top, 24)
            }

            if viewModel.scoredFrames.isEmpty && !viewModel.isScoring {
                Text("該当するフレームがありません")
                    .foregroundStyle(.secondary)
                    .padding(.top, 32)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(viewModel.scoredFrames.enumerated()), id: \.element.id) { index, frame in
                            NavigationLink {
                                FrameDetailView(frames: viewModel.scoredFrames, selectedIndex: index)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: frame.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110)
                                        .frame(height: 110)
                                        .clipped()

                                    Text(frame.timeLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                        .padding(6)
                                }
                                .background(Color.black.opacity(0.05))
                                .overlay(alignment: .topLeading) {
                                    if frame.score == viewModel.highestScore {
                                        Image(systemName: "star.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.yellow)
                                            .padding(6)
                                            .background(Circle().fill(Color.black.opacity(0.65)))
                                            .padding(6)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("採点結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 6) {
                    Text(isPersonScoring ? "人物" : "景色")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Toggle("", isOn: $isPersonScoring)
                        .labelsHidden()
                }
                .padding(.trailing, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("採点モード")
                .accessibilityValue(isPersonScoring ? "人物" : "景色")
            }
        }
        .task {
            await viewModel.startScoring()
        }
        .onChange(of: isPersonScoring) { _, newValue in
            Task {
                await viewModel.rescore(for: newValue ? .person : .scenery)
            }
        }
    }
}

struct FrameDetailView: View {
    let frames: [ScoredFrame]
    let selectedIndex: Int

    @State private var selection: Int
    @State private var showsSaveToast = false

    init(frames: [ScoredFrame], selectedIndex: Int) {
        self.frames = frames
        self.selectedIndex = selectedIndex
        _selection = State(initialValue: selectedIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(frames.indices, id: \.self) { index in
                    VStack {
                        Image(uiImage: frames[index].image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 16)

                        Text("採点結果: \(frames[index].score)/100")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Button("戻る") {
                    selection = max(selection - 1, 0)
                }
                .buttonStyle(.bordered)
                .disabled(selection == 0)

                Spacer()

                Button {
                    Task {
                        if await saveFrame(frames[selection].image) {
                            await showSaveToast()
                        }
                    }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 112, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("フレームを保存")

                Spacer()

                Button("進む") {
                    selection = min(selection + 1, frames.count - 1)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == frames.count - 1)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .navigationTitle("フレーム表示")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(saveToastOverlay, alignment: .bottom)
    }

    private var saveToastOverlay: some View {
        Group {
            if showsSaveToast {
                Text("保存しました")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .foregroundColor(.white)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsSaveToast)
    }

    private func showSaveToast() async {
        await MainActor.run {
            showsSaveToast = true
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            showsSaveToast = false
        }
    }

    private func saveFrame(_ image: UIImage) async -> Bool {
        guard await requestPhotoLibraryAccess() else { return false }
        do {
            try await saveImageToLibrary(image)
            return true
        } catch {
            return false
        }
    }

    private func requestPhotoLibraryAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { updatedStatus in
                    continuation.resume(returning: updatedStatus)
                }
            }
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    private func saveImageToLibrary(_ image: UIImage) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "PhotoSave", code: 1))
                }
            }
        }
    }
}

struct ScoredFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let time: CMTime
    let score: Int

    var timeLabel: String {
        formatTimestamp(time)
    }
}

@MainActor
final class VideoScoringViewModel: ObservableObject {
    @Published var isScoring = false
    @Published var scoredFrames: [ScoredFrame] = []

    private(set) var scoringMode: ScoringMode = .person

    private let asset: PHAsset
    var highestScore: Int {
        scoredFrames.map(\.score).max() ?? 0
    }

    init(asset: PHAsset) {
        self.asset = asset
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

        let avAsset = await loadAVAsset()
        await scoreFrames(from: avAsset)
    }

    private func loadAVAsset() async -> AVAsset {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(returning: AVURLAsset(url: URL(fileURLWithPath: "/dev/null")))
                }
            }
        }
    }

    private func scoreFrames(from asset: AVAsset) async {
        let durationSeconds = CMTimeGetSeconds(asset.duration)
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
        guard let urlAsset = asset as? AVURLAsset else { return nil }
        do {
            let scorer = try VideoPickerScoring()
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
#endif
}

enum ScoringMode {
    case person
    case scenery
}

private func formatTimestamp(_ time: CMTime) -> String {
    let totalSeconds = max(time.seconds, 0)
    let totalMilliseconds = Int((totalSeconds * 1000).rounded(.down))
    let minutes = totalMilliseconds / 60000
    let seconds = (totalMilliseconds % 60000) / 1000
    let milliseconds = totalMilliseconds % 1000
    return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
}

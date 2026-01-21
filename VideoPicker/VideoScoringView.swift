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

struct VideoScoringView: View {
    let item: VideoItem

    @StateObject private var viewModel: VideoScoringViewModel

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
                                        .frame(height: 110)
                                        .clipped()
                                        .background(Color.black.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    if frame.score == viewModel.highestScore {
                                        BestBadge()
                                            .padding(6)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }

                                    Text(frame.timeLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                        .padding(6)
                                }
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
        .task {
            await viewModel.startScoring()
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

    private let asset: PHAsset
    var highestScore: Int {
        scoredFrames.map(\.score).max() ?? 0
    }

    init(asset: PHAsset) {
        self.asset = asset
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

        for index in 0..<sampleCount {
            let seconds = durationSeconds * Double(index + 1) / Double(sampleCount + 1)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? await generateImage(with: generator, at: time) {
                let score = 70 + Int(abs(sin(Double(index))) * 30)
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
}

private struct BestBadge: View {
    var body: some View {
        Text("BEST")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 2)
            .padding(.horizontal, 14)
            .background(Color.red)
            .rotationEffect(.degrees(-45))
            .offset(x: -10, y: 6)
    }
}

private func formatTimestamp(_ time: CMTime) -> String {
    let totalSeconds = max(time.seconds, 0)
    let totalMilliseconds = Int((totalSeconds * 1000).rounded(.down))
    let minutes = totalMilliseconds / 60000
    let seconds = (totalMilliseconds % 60000) / 1000
    let milliseconds = totalMilliseconds % 1000
    return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
}

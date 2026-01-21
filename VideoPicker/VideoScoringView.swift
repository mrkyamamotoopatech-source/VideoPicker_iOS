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

                                    Text("\(frame.score)/100")
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

                        Text("スコア: \(frames[index].score)/100")
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
    }
}

struct ScoredFrame: Identifiable {
    let id = UUID()
    let image: UIImage
    let time: CMTime
    let score: Int
}

@MainActor
final class VideoScoringViewModel: ObservableObject {
    @Published var isScoring = false
    @Published var scoredFrames: [ScoredFrame] = []

    private let asset: PHAsset

    init(asset: PHAsset) {
        self.asset = asset
    }

    func startScoring() async {
        guard !isScoring else { return }
        isScoring = true
        defer { isScoring = false }

        let avAsset = await loadAVAsset()
        let frames = await scoreFrames(from: avAsset)
        scoredFrames = frames
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

    private func scoreFrames(from asset: AVAsset) async -> [ScoredFrame] {
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let sampleCount = 6
        var frames: [ScoredFrame] = []

        for index in 0..<sampleCount {
            let seconds = durationSeconds * Double(index + 1) / Double(sampleCount + 1)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let image = try? await generateImage(with: generator, at: time) {
                frames.append(ScoredFrame(image: image, time: time, score: 75))
            }
        }

        return frames
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

//
//  VideoDetailViewModel.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

@preconcurrency import AVKit
import Photos
import UIKit

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false

    private let asset: PHAsset
    private let assetLoader: VideoAssetLoader
    private let photoLibrary: PhotoLibraryService
    private var avAsset: AVAsset?
    private var statusObservation: NSKeyValueObservation?

    init(
        asset: PHAsset,
        assetLoader: VideoAssetLoader = VideoAssetLoader(),
        photoLibrary: PhotoLibraryService = PhotoLibraryService()
    ) {
        self.asset = asset
        self.assetLoader = assetLoader
        self.photoLibrary = photoLibrary
    }

    func loadPlayer() async {
        guard player == nil else { return }
        let avAsset = await assetLoader.loadAVAsset(for: asset)
        self.avAsset = avAsset
        let playerItem = AVPlayerItem(asset: avAsset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        observePlayer(newPlayer)
    }

    func togglePlay() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func stop() {
        player?.pause()
    }

    func seek(by seconds: Double) {
        guard let player else { return }
        let currentSeconds = player.currentTime().seconds
        let target = max(currentSeconds + seconds, 0)
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time)
    }

    func stepFrames(by frames: Int) {
        guard let player, let item = player.currentItem else { return }
        player.pause()
        item.step(byCount: frames)
    }

    func saveCurrentFrame() async -> Bool {
        guard let player, let avAsset, !isPlaying else { return false }
        let time = player.currentTime()
        return await saveFrame(at: time, from: avAsset)
    }

    private func observePlayer(_ player: AVPlayer) {
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func saveFrame(at time: CMTime, from asset: AVAsset) async -> Bool {
        guard await photoLibrary.requestAddOnlyAccess() else { return false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let cgImage = try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImageAsynchronously(for: time) { cgImage, _, error in
                    if let cgImage {
                        continuation.resume(returning: cgImage)
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "ImageGenerator", code: 1))
                    }
                }
            }
            let uiImage = UIImage(cgImage: cgImage)
            try await photoLibrary.saveImage(uiImage)
            return true
        } catch {
            return false
        }
    }
}

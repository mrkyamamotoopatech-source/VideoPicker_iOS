//
//  VideoDetailView.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

@preconcurrency import AVKit
import Photos
import SwiftUI
import UIKit

struct VideoDetailView: View {
    let item: VideoItem

    @StateObject private var viewModel: VideoDetailViewModel
    @State private var showsSaveToast = false

    init(item: VideoItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(asset: item.asset))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                videoArea
                    .frame(height: geo.size.height * 0.75)

                controlsArea
                    .frame(height: geo.size.height * 0.25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .overlay(saveToastOverlay, alignment: .bottom)
        }
        .navigationTitle("動画詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPlayer()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var videoArea: some View {
        Group {
            if let player = viewModel.player {
                VideoPlayer(player: player)
            } else {
                ProgressView("読み込み中…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }

    private var controlsArea: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 18) {
                    ForEach(leftControls, id: \.id) { control in
                        ControlButton(control: control)
                    }
                }

                Spacer()

                Button {
                    viewModel.togglePlay()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                }
                .accessibilityLabel(viewModel.isPlaying ? "停止" : "再生")
                .disabled(viewModel.player == nil)

                Spacer()

                HStack(spacing: 18) {
                    ForEach(rightControls, id: \.id) { control in
                        ControlButton(control: control)
                    }
                }
            }

            Button {
                Task {
                    if await viewModel.saveCurrentFrame() {
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
            .disabled(viewModel.isPlaying || viewModel.player == nil)
            .accessibilityLabel("フレームを保存")
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
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

    private var leftControls: [ControlAction] {
        if viewModel.isPlaying {
            return [
                ControlAction(id: "back5s", label: "5s", systemImage: "gobackward.5") {
                    viewModel.seek(by: -5)
                },
                ControlAction(id: "back1s", label: "1s", systemImage: "gobackward.1") {
                    viewModel.seek(by: -1)
                }
            ]
        }
        return [
            ControlAction(id: "back5f", label: "5f", systemImage: "backward.frame.fill") {
                viewModel.stepFrames(by: -5)
            },
            ControlAction(id: "back1f", label: "1f", systemImage: "backward.frame.fill") {
                viewModel.stepFrames(by: -1)
            }
        ]
    }

    private var rightControls: [ControlAction] {
        if viewModel.isPlaying {
            return [
                ControlAction(id: "forward1s", label: "1s", systemImage: "goforward.1") {
                    viewModel.seek(by: 1)
                },
                ControlAction(id: "forward5s", label: "5s", systemImage: "goforward.5") {
                    viewModel.seek(by: 5)
                }
            ]
        }
        return [
            ControlAction(id: "forward1f", label: "1f", systemImage: "forward.frame.fill") {
                viewModel.stepFrames(by: 1)
            },
            ControlAction(id: "forward5f", label: "5f", systemImage: "forward.frame.fill") {
                viewModel.stepFrames(by: 5)
            }
        ]
    }
}

private struct ControlAction {
    let id: String
    let label: String
    let systemImage: String
    let action: () -> Void
}

private struct ControlButton: View {
    let control: ControlAction

    var body: some View {
        Button(action: control.action) {
            VStack(spacing: 4) {
                Image(systemName: control.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(control.label)
                    .font(.caption2)
            }
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false

    private let asset: PHAsset
    private var avAsset: AVAsset?
    private var statusObservation: NSKeyValueObservation?

    init(asset: PHAsset) {
        self.asset = asset
    }

    func loadPlayer() async {
        guard player == nil else { return }
        let avAsset = await loadAVAsset()
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

    private func saveFrame(at time: CMTime, from asset: AVAsset) async -> Bool {
        guard await requestPhotoLibraryAccess() else { return false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        do {
            let cgImage = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let image = try generator.copyCGImage(at: time, actualTime: nil)
                        continuation.resume(returning: image)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            let uiImage = UIImage(cgImage: cgImage)
            try await saveImageToLibrary(uiImage)
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

//
//  VideoAssetLoader.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import AVFoundation
import Photos

struct VideoAssetLoader {
    func loadAVAsset(for asset: PHAsset) async -> AVAsset {
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

    func exportCompatibleURL(for asset: AVAsset) async throws -> URL {
        let presetName = AVAssetExportPreset1280x720
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw NSError(domain: "VideoAssetLoader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create export session"
            ])
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4

        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    let error = exportSession.error ?? NSError(domain: "VideoAssetLoader", code: 2)
                    continuation.resume(throwing: error)
                default:
                    let error = NSError(domain: "VideoAssetLoader", code: 3)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

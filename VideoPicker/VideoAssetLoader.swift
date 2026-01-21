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
}

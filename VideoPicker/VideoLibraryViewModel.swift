//
//  VideoLibraryViewModel.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI
import Photos

@MainActor
final class VideoLibraryViewModel: ObservableObject {
    @Published var items: [VideoItem] = []
    @Published var authorization: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var showDeniedAlert = false

    private let imageManager = PHCachingImageManager()

    func requestAccessAndLoadVideos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        authorization = status

        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                DispatchQueue.main.async {
                    self?.authorization = newStatus
                    self?.handleStatus(newStatus)
                }
            }
        default:
            handleStatus(status)
        }
    }

    private func handleStatus(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            loadVideos()
        case .denied, .restricted:
            showDeniedAlert = true
        default:
            break
        }
    }

    private func loadVideos() {
        // 取り直し
        items.removeAll()

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 必要なら件数制限
        // fetchOptions.fetchLimit = 200

        let result = PHAsset.fetchAssets(with: .video, options: fetchOptions)

        var tmp: [VideoItem] = []
        tmp.reserveCapacity(result.count)

        result.enumerateObjects { asset, _, _ in
            tmp.append(VideoItem(id: asset.localIdentifier, asset: asset, duration: asset.duration))
        }

        self.items = tmp
    }

    func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}


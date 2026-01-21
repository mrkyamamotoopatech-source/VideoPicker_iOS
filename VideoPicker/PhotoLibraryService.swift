//
//  PhotoLibraryService.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import Photos
import UIKit

struct PhotoLibraryService {
    func requestAddOnlyAccess() async -> Bool {
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

    func saveImage(_ image: UIImage) async throws {
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

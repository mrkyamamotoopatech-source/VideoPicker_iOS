//
//  FrameDetailViewModel.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import UIKit

@MainActor
final class FrameDetailViewModel: ObservableObject {
    private let photoLibrary: PhotoLibraryService

    init(photoLibrary: PhotoLibraryService = PhotoLibraryService()) {
        self.photoLibrary = photoLibrary
    }

    func saveFrame(_ image: UIImage) async -> Bool {
        guard await photoLibrary.requestAddOnlyAccess() else { return false }
        do {
            try await photoLibrary.saveImage(image)
            return true
        } catch {
            return false
        }
    }
}

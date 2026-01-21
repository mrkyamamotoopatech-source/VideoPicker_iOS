//
//  VideoItem.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import Photos

struct VideoItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let duration: TimeInterval

    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

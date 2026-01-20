//
//  VideoItem.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import Photos

struct VideoItem: Identifiable {
    let id: String
    let asset: PHAsset
    let duration: TimeInterval
}

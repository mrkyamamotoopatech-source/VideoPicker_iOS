//
//  VideoThumbnailCell.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI
import Photos

struct VideoThumbnailCell: View {
    let item: VideoItem
    let loadThumbnail: (PHAsset, CGSize) async -> UIImage?

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .task {
                                // 画面サイズに合わせてサムネ生成
                                let size = CGSize(width: geo.size.width * 2, height: geo.size.height * 2)
                                self.image = await loadThumbnail(item.asset, size)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                Text(formatDuration(item.duration))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .cornerRadius(6)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .aspectRatio(1, contentMode: .fit) // 正方形
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.down))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

//
//  ZoomableImageView.swift
//  VideoPicker
//
//  Created by Claude on 2026/03/16.
//

import SwiftUI

struct ZoomableImageView: View {
    let image: UIImage
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .gesture(
                    SimultaneousGesture(
                        // ピンチズームジェスチャー
                        MagnificationGesture()
                            .onChanged { value in
                                let newScale = lastScale * value
                                scale = max(minScale, min(maxScale, newScale))
                                
                                // 現在のスケールに応じてオフセットの範囲を制限
                                constrainOffset(for: geometry, scale: scale)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if scale <= minScale {
                                        scale = minScale
                                        lastScale = minScale
                                        offset = .zero
                                        lastOffset = .zero
                                    } else if scale > maxScale {
                                        scale = maxScale
                                        lastScale = maxScale
                                    }
                                }
                            },
                        
                        // パンジェスチャー（ズーム中のドラッグ）
                        DragGesture()
                            .onChanged { value in
                                if scale > minScale {
                                    let newOffsetX = lastOffset.width + value.translation.width
                                    let newOffsetY = lastOffset.height + value.translation.height
                                    
                                    offset = CGSize(width: newOffsetX, height: newOffsetY)
                                    constrainOffset(for: geometry, scale: scale)
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                )
                // ダブルタップでズームリセット
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scale = minScale
                        lastScale = minScale
                        offset = .zero
                        lastOffset = .zero
                    }
                }
        }
        .clipped()
    }
    
    private func constrainOffset(for geometry: GeometryProxy, scale: CGFloat) {
        // スケールに応じた最大オフセットを計算
        let maxOffsetX = max(0, (geometry.size.width * (scale - 1)) / 2)
        let maxOffsetY = max(0, (geometry.size.height * (scale - 1)) / 2)
        
        // 現在のオフセットを制限範囲内に収める
        let constrainedX = max(-maxOffsetX, min(maxOffsetX, offset.width))
        let constrainedY = max(-maxOffsetY, min(maxOffsetY, offset.height))
        
        // スケールが最小値に近い場合は中央に戻す
        if scale <= minScale + 0.05 {
            offset = .zero
            lastOffset = .zero
        } else {
            offset = CGSize(width: constrainedX, height: constrainedY)
        }
    }
}

#Preview {
    ZoomableImageView(image: UIImage(systemName: "photo") ?? UIImage())
        .frame(height: 300)
        .background(Color(.systemGray6))
}
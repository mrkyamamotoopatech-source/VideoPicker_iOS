//
//  VideoSelectionDialog.swift
//  VideoPicker
//
//  Created by Claude on 2026/03/16.
//

import SwiftUI
import Photos

struct VideoSelectionDialog: View {
    let item: VideoItem
    let onSelection: (VideoSelectionChoice) -> Void
    
    @Binding var isPresented: Bool
    @State private var thumbnailImage: UIImage?
    
    enum VideoSelectionChoice {
        case automatic  // 自動(試作)
        case manual     // 手動
        case cancel     // キャンセル
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    handleSelection(.cancel)
                }
            
            VStack(spacing: 20) {
                // タイトル
                Text(InfoPlistStrings.string("VP_Alert_Confirm_Title"))
                    .font(.headline.weight(.semibold))
                    .padding(.top, 20)
                
                // サムネイル表示
                if let thumbnailImage = thumbnailImage {
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 110)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .frame(width: 110, height: 110)
                        .overlay {
                            ProgressView()
                        }
                }
                
                // ボタン群
                VStack(spacing: 16) {
                    // 自動(試作)ボタンとメッセージ
                    VStack(spacing: 8) {
                        Button {
                            handleSelection(.automatic)
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("自動でベストショットを選択")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // ※メッセージ
                        Text(InfoPlistStrings.string("VP_Alert_ProcessingTime_Message"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                    }
                    
                    // 手動ボタン
                    Button {
                        handleSelection(.manual)
                    } label: {
                        HStack {
                            Image(systemName: "hand.point.up.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("手動で動画を確認")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // キャンセルボタン
                    Button {
                        handleSelection(.cancel)
                    } label: {
                        Text("キャンセル")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 40)
        }
        .task {
            // サムネイル読み込み
            if let image = await VideoLibraryViewModel().thumbnail(for: item.asset, targetSize: CGSize(width: 110, height: 110)) {
                thumbnailImage = image
            }
        }
    }
    
    private func handleSelection(_ choice: VideoSelectionChoice) {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            onSelection(choice)
        }
    }
}

#Preview {
    VideoSelectionDialog(
        item: VideoItem(
            id: "preview",
            asset: PHAsset(),
            duration: 60.0,
            isFavorite: false
        ),
        onSelection: { _ in },
        isPresented: .constant(true)
    )
}

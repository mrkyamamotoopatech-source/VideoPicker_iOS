//
//  TopView.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//
import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var vm = VideoLibraryViewModel()

    // グリッドの見た目
    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {

                // ====== 赤枠の中身（一覧エリア） ======
                VStack {
                    if vm.items.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(vm.items) { item in
                                    VideoThumbnailCell(item: item) { asset, size in
                                        await vm.thumbnail(for: asset, targetSize: size)
                                    }
                                }
                            }
                            .padding(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // ====== 右下ボタン ======
                Button {
                    vm.requestAccessAndLoadVideos()
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle())
                        .shadow(radius: 6)
                        .padding(20)
                }
                .accessibilityLabel("動画一覧を読み込む")
            }
            .navigationTitle("VideoPicker")
            .navigationBarTitleDisplayMode(.inline)
            .alert("写真へのアクセスが必要です", isPresented: $vm.showDeniedAlert) {
                Button("設定を開く") { openAppSettings() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("動画一覧を表示するには写真ライブラリへのアクセスを許可してください。")
            }
            .onAppear {
                // 起動時に許可済みなら即ロードしても良い
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .authorized || status == .limited {
                    vm.requestAccessAndLoadVideos()
                }
            }
        }
    }

    private var emptyMessage: String {
        switch vm.authorization {
        case .authorized, .limited:
            return "動画が見つかりませんでした"
        case .denied, .restricted:
            return "右下ボタン → 設定から写真アクセスを許可してください"
        case .notDetermined:
            return "右下ボタンで写真アクセスを許可すると動画一覧を表示します"
        @unknown default:
            return "状態不明"
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

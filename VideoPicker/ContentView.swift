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
    @State private var navigationPath = NavigationPath()
    @State private var pendingItem: VideoItem?
    @State private var showsSelectionDialog = false
    @State private var showsSettings = false

    // グリッドの見た目
    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                VStack(spacing: 0) {
                    // ====== メインコンテンツエリア ======
                    ZStack(alignment: .bottomTrailing) {
                        // ====== 一覧エリア ======
                        VStack {
                            if vm.items.isEmpty {
                                Text(vm.emptyMessage)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                ScrollView {
                                    LazyVGrid(columns: columns, spacing: 8) {
                                        ForEach(vm.items) { item in
                                            Button {
                                                pendingItem = item
                                                showsSelectionDialog = true
                                            } label: {
                                                VideoThumbnailCell(item: item) { asset, size in
                                                    await vm.thumbnail(for: asset, targetSize: size)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(12)
                                    .padding(.bottom, 90) // バナー広告の最大高さ分の余白を追加
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // ====== 右下ボタン ======
                        VStack(spacing: 12) {
                            // お気に入りフィルタボタン
                            if !vm.items.isEmpty {
                                Button {
                                    vm.toggleFavoriteFilter()
                                } label: {
                                    Image(systemName: vm.showOnlyFavorites ? "heart.fill" : "heart")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(vm.showOnlyFavorites ? .red : .white)
                                        .frame(width: 48, height: 48)
                                        .background(Circle().fill(vm.showOnlyFavorites ? .white : .gray))
                                        .shadow(radius: 4)
                                }
                                .accessibilityLabel("お気に入りフィルタ")
                            }
                            
                            // 動画読み込みボタン（動画が読み込まれていない時のみ表示）
                            if vm.items.isEmpty {
                                Button {
                                    vm.requestAccessAndLoadVideos()
                                } label: {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 56, height: 56)
                                        .background(Circle())
                                        .shadow(radius: 6)
                                }
                                .accessibilityLabel(InfoPlistStrings.string("VP_Accessibility_LoadVideos"))
                            }
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 110) // バナー最大高さ(90) + マージン(20)
                    }
                    
                    // ====== 下部バナー広告 ======
                    // 注意: 本番リリース前に実際のAd Unit IDに変更してください
                    AdMobAnchoredAdaptiveBannerView(adUnitID: "ca-app-pub-3940256099942544/2934735716") // テスト用ID
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50, maxHeight: 90) // 高さを50-60pxに制限
                        .clipped() // 制限を超える部分をクリップ
                        .background(Color(.systemGray6))
                }
            }
            .navigationTitle(InfoPlistStrings.string("VP_Title_Main"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.body)
                    }
                    .accessibilityLabel(InfoPlistStrings.string("VP_Settings_Title"))
                }
            }
            .navigationDestination(for: VideoRoute.self) { route in
                switch route {
                case .detail(let item):
                    VideoDetailView(item: item)
                case .scoring(let item):
                    VideoScoringView(item: item)
                }
            }
            .alert(InfoPlistStrings.string("VP_Alert_PhotosAccess_Title"), isPresented: $vm.showDeniedAlert) {
                Button(InfoPlistStrings.string("VP_Button_OpenSettings")) { openAppSettings() }
                Button(InfoPlistStrings.string("VP_Button_Cancel"), role: .cancel) {}
            } message: {
                Text(InfoPlistStrings.string("VP_Alert_PhotosAccess_Message"))
            }
            .alert(InfoPlistStrings.string("VP_Alert_Confirm_Title"), isPresented: $showsSelectionDialog) {
                Button(InfoPlistStrings.string("VP_Button_No"), role: .cancel) {
                    guard let item = pendingItem else { return }
                    navigationPath.append(VideoRoute.detail(item))
                    pendingItem = nil
                }
                Button(InfoPlistStrings.string("VP_Button_Yes")) {
                    guard let item = pendingItem else { return }
                    navigationPath.append(VideoRoute.scoring(item))
                    pendingItem = nil
                }
            } message: {
                Text(InfoPlistStrings.string("VP_Alert_AutoPick_Message") + "\n\n" + InfoPlistStrings.string("VP_Alert_ProcessingTime_Message"))
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
            .onAppear {
                // 起動時に許可済みなら即ロードしても良い
//                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
//                if status == .authorized || status == .limited {
//                    vm.requestAccessAndLoadVideos()
//                }
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum VideoRoute: Hashable {
    case detail(VideoItem)
    case scoring(VideoItem)
}

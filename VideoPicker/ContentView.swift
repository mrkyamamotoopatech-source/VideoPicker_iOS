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
    @StateObject private var adManager = InterstitialAdManager.shared
    @AppStorage("isAdFree") private var isAdFree = false
    @State private var pendingItem: VideoItem?
    @State private var showsSelectionDialog = false
    @State private var showsSettings = false
    @State private var selectedItem: VideoItem?
    @State private var showDetailView = false
    @State private var showScoringView = false

    // グリッドの見た目
    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]
    

    var body: some View {
        NavigationStack {
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
                                    .padding(.bottom, isAdFree ? 20 : 90) // 広告非表示時は20px、表示時は90px
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
                        .padding(.bottom, isAdFree ? 40 : 110) // 広告非表示時は40px、表示時は110px
                    }
                    
                    // ====== 下部バナー広告 ======
                    if !isAdFree {
                        AdMobAnchoredAdaptiveBannerView(adUnitID: AdMobConfig.bannerAdUnitID)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50, maxHeight: 90) // 高さを50-60pxに制限
                            .clipped() // 制限を超える部分をクリップ
                            .background(Color(.systemGray6))
                    }
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
            .background {
                NavigationLink(
                    destination: selectedItem.map { VideoDetailView(item: $0) },
                    isActive: $showDetailView,
                    label: { EmptyView() }
                )
                NavigationLink(
                    destination: selectedItem.map { VideoScoringView(item: $0) },
                    isActive: $showScoringView,
                    label: { EmptyView() }
                )
            }
            .alert(InfoPlistStrings.string("VP_Alert_PhotosAccess_Title"), isPresented: $vm.showDeniedAlert) {
                Button(InfoPlistStrings.string("VP_Button_OpenSettings")) { openAppSettings() }
                Button(InfoPlistStrings.string("VP_Button_Cancel"), role: .cancel) {}
            } message: {
                Text(InfoPlistStrings.string("VP_Alert_PhotosAccess_Message"))
            }
            .sheet(isPresented: $showsSettings) {
                SettingsView()
            }
            .overlay {
                if showsSelectionDialog, let item = pendingItem {
                    VideoSelectionDialog(
                        item: item,
                        onSelection: handleVideoSelection,
                        isPresented: $showsSelectionDialog
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: showsSelectionDialog)
                }
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
    
    /// ビデオ選択ダイアログの選択結果を処理
    private func handleVideoSelection(_ choice: VideoSelectionDialog.VideoSelectionChoice) {
        guard let item = pendingItem else { return }
        
        selectedItem = item
        
        switch choice {
        case .automatic:
            // 自動選択の場合はNavigationLinkで遷移
            showScoringView = true
        case .manual:
            // 手動選択の場合もNavigationLinkで遷移
            showDetailView = true
            // 手動モードの場合のみ広告を表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak adManager] in
                adManager?.showInterstitialAd(from: UIViewController.topMostViewController()) {
                    NSLog("インタースティシャル広告が閉じられました")
                }
            }
        case .cancel:
            selectedItem = nil
        }
        
        // 状態をリセット
        pendingItem = nil
    }
}


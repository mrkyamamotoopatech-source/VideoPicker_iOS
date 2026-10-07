//
//  VideoScoringView.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI
import UIKit

struct VideoScoringView: View {
    let item: VideoItem

    @StateObject private var viewModel: VideoScoringViewModel
    @State private var isPersonScoring = true
    @State private var showsStopScoringAlert = false
    /// 表示中のフレーム詳細。タップ時点の一覧を固定して持つ
    @State private var detailSnapshot: FrameDetailSnapshot?
    @Environment(\.dismiss) private var dismiss

    init(item: VideoItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: VideoScoringViewModel(asset: item.asset))
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 16) {
            ScoringProgressBar(viewModel: viewModel, style: .regular)

            if viewModel.scoredFrames.isEmpty && !viewModel.isScoring {
                Text(InfoPlistStrings.string("VP_Scoring_Empty"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 32)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.scoredFrames) { frame in
                            Button {
                                // 採点中は一覧が更新され続けるので、タップ時点の内容を固定して詳細画面へ渡す
                                detailSnapshot = FrameDetailSnapshot.make(
                                    frames: viewModel.scoredFrames,
                                    selectedFrameID: frame.id
                                )
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: frame.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 110)
                                        .clipped()

                                    Text(frame.timeLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Capsule())
                                        .padding(6)
                                }
                                .background(Color.black.opacity(0.05))
                                .overlay(alignment: .topLeading) {
                                    if frame.isSegmentBest {
                                        Image(systemName: "star.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.yellow)
                                            .padding(6)
                                            .background(Circle().fill(Color.black.opacity(0.65)))
                                            .padding(6)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(InfoPlistStrings.string("VP_Title_ScoringResult"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 採点がまだ開始されていない場合のみ開始
            if !viewModel.isScoring && viewModel.scoredFrames.isEmpty {
                viewModel.startScoring()
            }
        }
        .onChange(of: isPersonScoring) { _, newValue in
            viewModel.rescore(for: newValue ? .person : .scenery)
        }
        .navigationDestination(item: $detailSnapshot) { snapshot in
            FrameDetailView(frames: snapshot.frames, selectedIndex: snapshot.selectedIndex, scoringViewModel: viewModel)
        }
        // 採点を止めるのは「完了したとき」と「戻る確認で『はい』を選んだとき」だけ。
        // フレーム詳細への遷移など、画面が隠れただけでは止めない。
        // 採点中は標準の戻るボタンと端スワイプを無効にし、確認を経ずに戻れないようにする
        .navigationBarBackButtonHidden(viewModel.isScoring)
        .toolbar {
            if viewModel.isScoring {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showsStopScoringAlert = true
                    } label: {
                        Label(InfoPlistStrings.string("VP_Button_Back"), systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .alert(InfoPlistStrings.string("VP_Alert_Confirm_Title"), isPresented: $showsStopScoringAlert) {
            Button(InfoPlistStrings.string("VP_Button_Yes"), role: .destructive) {
                viewModel.cancelScoring()
                dismiss()
            }
            Button(InfoPlistStrings.string("VP_Button_No"), role: .cancel) {}
        } message: {
            Text(InfoPlistStrings.string("VP_Alert_StopScoring_Message"))
        }
        .onChange(of: viewModel.isScoring) { _, isScoring in
            // 確認を出している間に採点が完了したら、中止の確認は意味がなくなるので閉じる
            if !isScoring {
                showsStopScoringAlert = false
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                isPersonScoring.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPersonScoring ? "person.2.fill" : "leaf.fill")
                        .font(.headline.weight(.bold))
                    Text(isPersonScoring ? InfoPlistStrings.string("VP_Mode_Person") : InfoPlistStrings.string("VP_Mode_Scenery"))
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                )
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
            .accessibilityLabel(InfoPlistStrings.string("VP_Accessibility_ScoringToggle"))
            .accessibilityValue(isPersonScoring ? InfoPlistStrings.string("VP_Mode_Person") : InfoPlistStrings.string("VP_Mode_Scenery"))
        }
    }
}

struct FrameDetailView: View {
    let frames: [ScoredFrame]
    let selectedIndex: Int
    let scoringViewModel: VideoScoringViewModel

    @State private var selection: Int
    @State private var showsSaveToast = false
    @State private var originalImages: [Int: UIImage] = [:] // オリジナル画像のキャッシュ
    @State private var loadingImages: Set<Int> = [] // 読み込み中のインデックス
    @StateObject private var viewModel = FrameDetailViewModel()
    @StateObject private var adManager = InterstitialAdManager.shared

    init(frames: [ScoredFrame], selectedIndex: Int, scoringViewModel: VideoScoringViewModel) {
        self.frames = frames
        self.selectedIndex = selectedIndex
        self.scoringViewModel = scoringViewModel
        _selection = State(initialValue: selectedIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(frames.indices, id: \.self) { index in
                    VStack {
                        ZStack {
                            if let originalImage = originalImages[index] {
                                // オリジナル画像（ズーム可能）
                                ZoomableImageView(image: originalImage)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .transition(.opacity)
                            } else {
                                // 読み込み中表示
                                Color(.systemGray6)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                            .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                    }
                            }
                        }
                        .padding(.horizontal, 16)

                        Text(InfoPlistStrings.formatted("VP_Label_ScoreResult", frames[index].score))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                    }
                    .tag(index)
                    .onAppear {
                        loadOriginalImageIfNeeded(for: index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 詳細を見ている間も採点は続くので、進捗を出し続ける（完了すると消える）
            ScoringProgressBar(viewModel: scoringViewModel, style: .compact)

            HStack {
                Button(InfoPlistStrings.string("VP_Button_Back")) {
                    selection = max(selection - 1, 0)
                }
                .buttonStyle(.bordered)
                .disabled(selection == 0)

                Spacer()

                Button {
                    Task {
                        // オリジナル画像があればそれを保存、なければサムネイルを保存
                        let imageToSave = originalImages[selection] ?? frames[selection].image
                        if await viewModel.saveFrame(imageToSave) {
                            await showSaveToast()
                            
                            // 20%の確率で広告を表示（5回に1回）
                            if shouldShowAd() {
                                showInterstitialAd()
                            }
                        }
                    }
                } label: {
                    Label(InfoPlistStrings.string("VP_Button_Save"), systemImage: "square.and.arrow.down")
                        .font(.caption.weight(.semibold))
                        .frame(width: 112, height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(InfoPlistStrings.string("VP_Accessibility_SaveFrame"))

                Spacer()

                Button(InfoPlistStrings.string("VP_Button_Next")) {
                    selection = min(selection + 1, frames.count - 1)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == frames.count - 1)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemBackground))
        }
        .navigationTitle(InfoPlistStrings.string("VP_Title_FrameDetail"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay(saveToastOverlay, alignment: .bottom)
        .onChange(of: selection) { _, newIndex in
            // 新しく選択されたフレームのオリジナル画像も読み込み
            loadOriginalImageIfNeeded(for: newIndex)
        }
    }
    
    private func loadOriginalImageIfNeeded(for index: Int) {
        // すでに読み込み済みまたは読み込み中の場合はスキップ
        guard originalImages[index] == nil && !loadingImages.contains(index) else { return }
        
        loadingImages.insert(index)
        
        let frameTime = frames[index].time
        
        Task {
            if let originalImage = await scoringViewModel.generateOriginalFrameImage(at: frameTime) {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        originalImages[index] = originalImage
                        loadingImages.remove(index)
                    }
                }
            } else {
                await MainActor.run {
                    loadingImages.remove(index)
                }
            }
        }
    }

    private var saveToastOverlay: some View {
        Group {
            if showsSaveToast {
                Text(InfoPlistStrings.string("VP_Toast_Saved"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .foregroundColor(.white)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsSaveToast)
    }

    private func showSaveToast() async {
        await MainActor.run {
            showsSaveToast = true
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await MainActor.run {
            showsSaveToast = false
        }
    }
    
    /// 広告を表示するかどうかの判定（25%の確率）
    private func shouldShowAd() -> Bool {
        return Int.random(in: 0..<4) == 1 // 1/4の確率
    }
    
    /// インタースティシャル広告を表示
    private func showInterstitialAd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak adManager] in
            adManager?.showInterstitialAd(from: UIViewController.topMostViewController()) {
                NSLog("フレーム保存後のインタースティシャル広告が閉じられました")
            }
        }
    }

}

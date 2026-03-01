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
            if viewModel.isScoring {
                VStack(spacing: 12) {
                    Text(InfoPlistStrings.string("VP_Scoring_InProgress"))
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        // プログレスバー
                        ProgressView(value: viewModel.currentProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .scaleEffect(x: 1, y: 2, anchor: .center) // 高さを2倍に
                        
                        // 時間表示
                        HStack {
                            Text(viewModel.currentTime)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text(viewModel.totalDuration)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 32)
                }
                .padding(.top, 24)
            }

            if viewModel.scoredFrames.isEmpty && !viewModel.isScoring {
                Text(InfoPlistStrings.string("VP_Scoring_Empty"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 32)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Array(viewModel.scoredFrames.enumerated()), id: \.element.id) { index, frame in
                            NavigationLink {
                                FrameDetailView(frames: viewModel.scoredFrames, selectedIndex: index, scoringViewModel: viewModel)
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
            viewModel.startScoring()
        }
        .onChange(of: isPersonScoring) { _, newValue in
            viewModel.rescore(for: newValue ? .person : .scenery)
        }
        .onDisappear {
            viewModel.cancelScoring()
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
                            // サムネイル画像（背景）
                            Image(uiImage: frames[index].image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 16)
                                .opacity(originalImages[index] != nil ? 0 : 1)
                            
                            // オリジナル画像（メイン）
                            if let originalImage = originalImages[index] {
                                Image(uiImage: originalImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, 16)
                                    .transition(.opacity)
                            }
                            
                            // ローディングインジケータ
                            if loadingImages.contains(index) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.black.opacity(0.6))
                                            .frame(width: 60, height: 60)
                                    )
                            }
                        }

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

}

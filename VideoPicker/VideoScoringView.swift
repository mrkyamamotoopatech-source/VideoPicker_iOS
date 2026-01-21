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
                ProgressView(InfoPlistStrings.string("VP_Scoring_InProgress"))
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
                                FrameDetailView(frames: viewModel.scoredFrames, selectedIndex: index)
                            } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    Image(uiImage: frame.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110)
                                        .frame(height: 110)
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
                                    if frame.score == viewModel.highestScore {
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
            await viewModel.startScoring()
        }
        .onChange(of: isPersonScoring) { _, newValue in
            Task {
                await viewModel.rescore(for: newValue ? .person : .scenery)
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

    @State private var selection: Int
    @State private var showsSaveToast = false
    @StateObject private var viewModel = FrameDetailViewModel()

    init(frames: [ScoredFrame], selectedIndex: Int) {
        self.frames = frames
        self.selectedIndex = selectedIndex
        _selection = State(initialValue: selectedIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                ForEach(frames.indices, id: \.self) { index in
                    VStack {
                        Image(uiImage: frames[index].image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 16)

                        Text(InfoPlistStrings.formatted("VP_Label_ScoreResult", frames[index].score))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                    }
                    .tag(index)
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
                        if await viewModel.saveFrame(frames[selection].image) {
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

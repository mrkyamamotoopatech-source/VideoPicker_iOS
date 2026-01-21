//
//  VideoDetailView.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

@preconcurrency import AVKit
import SwiftUI

struct VideoDetailView: View {
    let item: VideoItem

    @StateObject private var viewModel: VideoDetailViewModel
    @State private var showsSaveToast = false

    init(item: VideoItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: VideoDetailViewModel(asset: item.asset))
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                videoArea
                    .frame(height: geo.size.height * 0.75)

                controlsArea
                    .frame(height: geo.size.height * 0.25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .overlay(saveToastOverlay, alignment: .bottom)
        }
        .navigationTitle(InfoPlistStrings.string("VP_Title_VideoDetail"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPlayer()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private var videoArea: some View {
        Group {
            if let player = viewModel.player {
                VideoPlayer(player: player)
            } else {
                ProgressView(InfoPlistStrings.string("VP_Loading_Video"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }

    private var controlsArea: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 18) {
                    ForEach(leftControls, id: \.id) { control in
                        ControlButton(control: control)
                    }
                }

                Spacer()

                Button {
                    viewModel.togglePlay()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                }
                .accessibilityLabel(viewModel.isPlaying ? InfoPlistStrings.string("VP_Accessibility_Stop") : InfoPlistStrings.string("VP_Accessibility_Play"))
                .disabled(viewModel.player == nil)

                Spacer()

                HStack(spacing: 18) {
                    ForEach(rightControls, id: \.id) { control in
                        ControlButton(control: control)
                    }
                }
            }

            Button {
                Task {
                    if await viewModel.saveCurrentFrame() {
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
            .disabled(viewModel.isPlaying || viewModel.player == nil)
            .accessibilityLabel(InfoPlistStrings.string("VP_Accessibility_SaveFrame"))
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
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

    private var leftControls: [ControlAction] {
        if viewModel.isPlaying {
            return [
                ControlAction(id: "back5s", label: InfoPlistStrings.string("VP_Control_5s"), systemImage: "gobackward.5") {
                    viewModel.seek(by: -5)
                },
                ControlAction(id: "back1s", label: InfoPlistStrings.string("VP_Control_1s"), systemImage: "gobackward.1") {
                    viewModel.seek(by: -1)
                }
            ]
        }
        return [
            ControlAction(id: "back5f", label: InfoPlistStrings.string("VP_Control_5f"), systemImage: "backward.frame.fill") {
                viewModel.stepFrames(by: -5)
            },
            ControlAction(id: "back1f", label: InfoPlistStrings.string("VP_Control_1f"), systemImage: "backward.frame.fill") {
                viewModel.stepFrames(by: -1)
            }
        ]
    }

    private var rightControls: [ControlAction] {
        if viewModel.isPlaying {
            return [
                ControlAction(id: "forward1s", label: InfoPlistStrings.string("VP_Control_1s"), systemImage: "goforward.1") {
                    viewModel.seek(by: 1)
                },
                ControlAction(id: "forward5s", label: InfoPlistStrings.string("VP_Control_5s"), systemImage: "goforward.5") {
                    viewModel.seek(by: 5)
                }
            ]
        }
        return [
            ControlAction(id: "forward1f", label: InfoPlistStrings.string("VP_Control_1f"), systemImage: "forward.frame.fill") {
                viewModel.stepFrames(by: 1)
            },
            ControlAction(id: "forward5f", label: InfoPlistStrings.string("VP_Control_5f"), systemImage: "forward.frame.fill") {
                viewModel.stepFrames(by: 5)
            }
        ]
    }
}

private struct ControlAction {
    let id: String
    let label: String
    let systemImage: String
    let action: () -> Void
}

private struct ControlButton: View {
    let control: ControlAction

    var body: some View {
        Button(action: control.action) {
            VStack(spacing: 4) {
                Image(systemName: control.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(control.label)
                    .font(.caption2)
            }
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}

//
//  ScoringProgressBar.swift
//  VideoPicker
//

import SwiftUI

/// 採点中だけ進捗を表示する。採点が終わると何も表示しない。
/// フレーム詳細画面はViewModelを監視していないので、進捗の更新で再描画されるのはこのビューだけになる
/// （一覧画面はViewModelを自分で監視しているため、従来どおり画面全体が再描画される）
struct ScoringProgressBar: View {
    enum Style {
        /// 採点結果の一覧画面用（見出し＋太めのバー＋パーセント）
        case regular
        /// フレーム詳細画面用（1行に収める）
        case compact
    }

    @ObservedObject var viewModel: VideoScoringViewModel
    let style: Style

    var body: some View {
        if viewModel.isScoring {
            switch style {
            case .regular:
                regularBody
            case .compact:
                compactBody
            }
        }
    }

    private var percentText: String {
        "\(Int(viewModel.currentProgress * 100))%"
    }

    private var regularBody: some View {
        VStack(spacing: 12) {
            Text(InfoPlistStrings.string("VP_Scoring_InProgress"))
                .font(.headline)

            VStack(spacing: 8) {
                ProgressView(value: viewModel.currentProgress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .scaleEffect(x: 1, y: 2, anchor: .center) // 高さを2倍に

                Text(percentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
        }
        .padding(.top, 24)
    }

    private var compactBody: some View {
        HStack(spacing: 12) {
            Text(InfoPlistStrings.string("VP_Scoring_InProgress"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ProgressView(value: viewModel.currentProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())

            Text(percentText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

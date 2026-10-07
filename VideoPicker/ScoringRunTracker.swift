//
//  ScoringRunTracker.swift
//  VideoPicker
//

import Foundation

/// 採点の実行に通し番号を振り、どの実行が最新かを判定する。
///
/// 採点を中止・やり直ししても、古い採点タスクはすぐには終わらず、後から終了処理を実行する。
/// その終了処理が新しい採点の状態（採点中フラグなど）を上書きしないよう、
/// 開始時に受け取った番号が最新のときだけ状態を更新する
struct ScoringRunTracker: Equatable {
    private(set) var latestRunID = 0

    /// 番号を1つ進めた新しいトラッカーを返す。採点の開始時と中止時に呼ぶ
    func advanced() -> ScoringRunTracker {
        ScoringRunTracker(latestRunID: latestRunID + 1)
    }

    /// 指定した番号の採点が、置き換えられていない最新の実行かどうか
    func isLatest(_ runID: Int) -> Bool {
        runID == latestRunID
    }
}

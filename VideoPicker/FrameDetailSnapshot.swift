//
//  FrameDetailSnapshot.swift
//  VideoPicker
//

import Foundation

/// フレーム詳細画面に渡す、タップ時点のフレーム一覧と選択位置。
/// 採点中は一覧が並べ替え・間引きで置き換えられ続けるため、詳細画面には固定した内容を渡す。
/// 等価性はidだけで判定する（遷移1回ごとに別物として扱う）。内容の比較には使えない
struct FrameDetailSnapshot: Identifiable, Hashable {
    let id: UUID
    let frames: [ScoredFrame]
    let selectedIndex: Int

    /// タップしたフレームを選択位置にしたスナップショットを作る。
    /// 一覧の更新でそのフレームがすでに無くなっている場合はnilを返す
    static func make(frames: [ScoredFrame], selectedFrameID: ScoredFrame.ID) -> FrameDetailSnapshot? {
        guard let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
            return nil
        }
        return FrameDetailSnapshot(id: UUID(), frames: frames, selectedIndex: index)
    }

    // 画面遷移の識別にはidだけを使う（framesはUIImageを含み比較できない）
    static func == (lhs: FrameDetailSnapshot, rhs: FrameDetailSnapshot) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

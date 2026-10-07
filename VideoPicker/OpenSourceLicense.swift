//
//  OpenSourceLicense.swift
//  VideoPicker
//

import Foundation
import os

/// アプリに組み込んでいるオープンソースソフトウェアと、そのライセンス文の所在
struct OpenSourceLicense: Identifiable, Equatable {
    private static let logger = Logger(subsystem: "VideoPicker", category: "Licenses")
    private static let resourceExtension = "txt"

    let name: String
    let licenseName: String
    /// バンドルに同梱したライセンス文のファイル名（拡張子なし）
    let resourceName: String

    var id: String { name }

    /// ライセンス表示の対象。ライブラリを追加・削除したらここも更新する。
    /// OpenCVはMediaPipeに同梱されているものを利用している
    static let all: [OpenSourceLicense] = [
        OpenSourceLicense(
            name: "MediaPipe",
            licenseName: "Apache License 2.0",
            resourceName: "License-MediaPipe"
        ),
        OpenSourceLicense(
            name: "BlazeFace (short-range) face detection model",
            licenseName: "Apache License 2.0",
            resourceName: "License-MediaPipe"
        ),
        OpenSourceLicense(
            name: "OpenCV",
            licenseName: "Apache License 2.0",
            resourceName: "License-OpenCV"
        )
    ]

    /// 同梱したライセンス文を読み込む。ファイルがない、または読めない場合はnil
    func loadText(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: Self.resourceExtension) else {
            Self.logger.error("ライセンス文のファイルが見つからない: \(resourceName, privacy: .public)")
            return nil
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logger.error("ライセンス文の読み込みに失敗: \(resourceName, privacy: .public) \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

//
//  AdMobConfig.swift
//  VideoPicker
//
//  Created by Claude on 2026/03/15.
//

import Foundation

struct AdMobConfig {
    // App ID
    static let appID = "ca-app-pub-5859864934932113~9414286435"
    
    // バナー広告ユニットID
    static var bannerAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2934735716" // テスト用ID
        #else
        return "ca-app-pub-5859864934932113/BANNER_UNIT_ID" // 本番用（要設定）
        #endif
    }
    
    // インタースティシャル広告ユニットID
    static var interstitialAdUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/4411468910" // テスト用ID
        #else
        return "ca-app-pub-5859864934932113/5604293117" // 本番用
        #endif
    }
}
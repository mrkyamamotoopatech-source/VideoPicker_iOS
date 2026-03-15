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
    
    // アプリがテストモードかどうかを判定
    private static var isTestMode: Bool {
        // App Store Connect、TestFlightからのインストールの場合はfalse
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else { return true }
        let receiptURLString = appStoreReceiptURL.path
        
        // App Store、TestFlightの場合
        if receiptURLString.contains("/Applications/") || receiptURLString.contains("CoreSimulator") {
            return true // シミュレータやXcodeからの直接インストール
        }
        
        if receiptURLString.contains("StoreKit/sandboxReceipt") {
            return false // TestFlight
        }
        
        if receiptURLString.contains("/StoreKit/receipt") {
            return false // App Store
        }
        
        return true // その他（開発時など）
    }
    
    // バナー広告ユニットID
    static var bannerAdUnitID: String {
        if isTestMode {
            return "ca-app-pub-3940256099942544/2934735716" // テスト用ID
        } else {
            return "ca-app-pub-5859864934932113/4765758706" // 本番用
        }
    }
    
    // インタースティシャル広告ユニットID
    static var interstitialAdUnitID: String {
        if isTestMode {
            return "ca-app-pub-3940256099942544/4411468910" // テスト用ID
        } else {
            return "ca-app-pub-5859864934932113/5604293117" // 本番用
        }
    }
}

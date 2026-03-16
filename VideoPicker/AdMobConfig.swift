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
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else { return true }
        let receiptURLString = appStoreReceiptURL.path
        
        // シミュレータ
        if receiptURLString.contains("CoreSimulator") { return true }
        
        // TestFlight
        if receiptURLString.contains("sandboxReceipt") { return true }
        
        // App Store
        if receiptURLString.contains("StoreKit/receipt") { return false }
        
        // Xcodeから直接インストール（レシートなし or 上記以外）
        return true
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

//
//  VideoPickerApp.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI
import GoogleMobileAds

@main
struct VideoPickerApp: App {
    @State private var isSplashScreenActive = false
    
    init() {
        // Google Mobile Ads SDKを初期化
        MobileAds.shared.start(completionHandler: nil)

        // 顔検出モデルの読み込みをメインスレッドで行わないよう、起動直後にバックグラウンドで済ませておく
        Task.detached(priority: .utility) {
            _ = PersonBlurScorer.shared
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isSplashScreenActive {
                    ContentView()
                        .transition(.opacity)
                } else {
                    SplashScreenView(isActive: $isSplashScreenActive)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isSplashScreenActive)
        }
    }
}

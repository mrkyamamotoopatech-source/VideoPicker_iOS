//
//  VideoPickerApp.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI
// import GoogleMobileAds  // 一時的にコメントアウト

@main
struct VideoPickerApp: App {
    @State private var isSplashScreenActive = false
    
    init() {
        // Google Mobile Ads SDKを初期化（SDKが利用可能になったら有効化）
        // MobileAds.shared.start(completionHandler: nil)
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

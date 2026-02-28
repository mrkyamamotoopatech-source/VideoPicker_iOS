//
//  VideoPickerApp.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI

@main
struct VideoPickerApp: App {
    @State private var isSplashScreenActive = false
    
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

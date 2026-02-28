//
//  AdMobBannerView.swift
//  VideoPicker
//

import SwiftUI
import UIKit

// プレースホルダー実装: Google Mobile Ads SDKが利用可能になるまでの暫定版
struct AdMobAnchoredAdaptiveBannerView: UIViewRepresentable {
    let adUnitID: String
    
    func makeUIView(context: Context) -> UIView {
        let placeholderView = UIView()
        placeholderView.backgroundColor = UIColor.systemGray6
        
        let label = UILabel()
        label.text = "広告エリア (AdMob Banner)"
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = UIColor.systemGray2
        label.translatesAutoresizingMaskIntoConstraints = false
        
        placeholderView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor)
        ])
        
        return placeholderView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // プレースホルダーなので何もしない
    }
}

// MARK: - 実際のGoogle Mobile Ads実装（SDKが利用可能な場合）
/*
実際にGoogle Mobile Ads SDKを使用する場合は、以下の手順で実装してください：

1. Swift Package ManagerまたはCocoaPodsでGoogle Mobile Ads SDKを追加
2. 上記のコメントアウトを解除
3. 以下の実装に置き換え

import SwiftUI
import GoogleMobileAds
import UIKit

struct AdMobAnchoredAdaptiveBannerView: UIViewRepresentable {
    let adUnitID: String
    
    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView()
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = UIApplication.shared.rootViewController
        
        let screenWidth = UIScreen.main.bounds.width
        let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: screenWidth)
        bannerView.adSize = adaptiveSize
        
        bannerView.load(Request())
        
        return bannerView
    }
    
    func updateUIView(_ uiView: BannerView, context: Context) {
        let screenWidth = UIScreen.main.bounds.width
        let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: screenWidth)
        uiView.adSize = adaptiveSize
    }
}

extension UIApplication {
    var keyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    
    var rootViewController: UIViewController? {
        keyWindow?.rootViewController
    }
}
*/
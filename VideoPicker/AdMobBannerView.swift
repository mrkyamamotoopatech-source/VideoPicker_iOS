//
//  AdMobBannerView.swift
//  VideoPicker
//

import SwiftUI
import GoogleMobileAds
import UIKit

struct AdMobAnchoredAdaptiveBannerView: UIViewRepresentable {
    let adUnitID: String
    
    func makeUIView(context: Context) -> UIView {
        // コンテナビューを作成して高さを制限
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemGray6
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let bannerView = BannerView()
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = UIApplication.shared.rootViewController
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        
        let screenWidth = UIScreen.main.bounds.width
        let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: screenWidth)
        bannerView.adSize = adaptiveSize
        
        containerView.addSubview(bannerView)
        
        // 高さ制限付きの制約を設定
        NSLayoutConstraint.activate([
            // バナービューをコンテナの中央に配置
            bannerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            bannerView.leadingAnchor.constraint(greaterThanOrEqualTo: containerView.leadingAnchor),
            bannerView.trailingAnchor.constraint(lessThanOrEqualTo: containerView.trailingAnchor),
            // コンテナの高さを60px以下に制限
            containerView.heightAnchor.constraint(lessThanOrEqualToConstant: 60),
            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
        
        bannerView.load(Request())
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // バナービューを探して更新
        if let bannerView = uiView.subviews.first(where: { $0 is BannerView }) as? BannerView {
            let screenWidth = UIScreen.main.bounds.width
            let adaptiveSize = currentOrientationAnchoredAdaptiveBanner(width: screenWidth)
            bannerView.adSize = adaptiveSize
        }
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


//import SwiftUI
//import UIKit
//
//// プレースホルダー実装: Google Mobile Ads SDKが利用可能になるまでの暫定版
//struct AdMobAnchoredAdaptiveBannerView: UIViewRepresentable {
//    let adUnitID: String
//
//    func makeUIView(context: Context) -> UIView {
//        let placeholderView = UIView()
//        placeholderView.backgroundColor = UIColor.systemGray6
//
//        let label = UILabel()
//        label.text = "広告エリア (AdMob Banner)"
//        label.textAlignment = .center
//        label.font = UIFont.systemFont(ofSize: 12)
//        label.textColor = UIColor.systemGray2
//        label.translatesAutoresizingMaskIntoConstraints = false
//
//        placeholderView.addSubview(label)
//        NSLayoutConstraint.activate([
//            label.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
//            label.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),
//            // プレースホルダーでも高さ制限を設定
//            placeholderView.heightAnchor.constraint(lessThanOrEqualToConstant: 90)
//        ])
//
//        return placeholderView
//    }
//
//    func updateUIView(_ uiView: UIView, context: Context) {
//        // プレースホルダーなので何もしない
//    }
//}

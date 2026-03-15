//
//  InterstitialAdManager.swift
//  VideoPicker
//
//  Created by Claude on 2026/03/15.
//

import UIKit
import GoogleMobileAds
import Foundation

@MainActor
class InterstitialAdManager: NSObject, ObservableObject {
    static let shared = InterstitialAdManager()
    
    private var interstitialAd: InterstitialAd?
    @Published private(set) var isAdReady = false
    @Published private(set) var isAdShowing = false
    
    private var completionHandler: (() -> Void)?
    
    override init() {
        super.init()
        loadInterstitialAd()
    }
    
    /// インタースティシャル広告をロード
    func loadInterstitialAd() {
        let request = Request()
        
        InterstitialAd.load(
            with: AdMobConfig.interstitialAdUnitID,
            request: request
        ) { [weak self] ad, error in
            DispatchQueue.main.async {
                if let error = error {
                    NSLog("インタースティシャル広告のロードに失敗: %@", error.localizedDescription)
                    self?.isAdReady = false
                    return
                }
                
                guard let ad = ad else {
                    NSLog("インタースティシャル広告が nil")
                    self?.isAdReady = false
                    return
                }
                
                NSLog("インタースティシャル広告のロードに成功")
                self?.interstitialAd = ad
                self?.interstitialAd?.fullScreenContentDelegate = self
                self?.isAdReady = true
            }
        }
    }
    
    /// インタースティシャル広告を表示
    /// - Parameters:
    ///   - viewController: 表示元のViewController（SwiftUIから呼ぶ場合はUIWindow.rootViewController）
    ///   - completion: 広告が閉じられた後のコールバック
    func showInterstitialAd(from viewController: UIViewController?, completion: @escaping () -> Void) {
        // 広告非表示モードの確認
        let isAdFree = UserDefaults.standard.bool(forKey: "isAdFree")
        if isAdFree {
            NSLog("広告非表示モードが有効なため、広告をスキップしました")
            completion()
            return
        }
        
        guard let viewController = viewController else {
            NSLog("ViewControllerが取得できませんでした")
            completion()
            return
        }
        
        guard let interstitialAd = interstitialAd, isAdReady else {
            NSLog("インタースティシャル広告が準備できていません")
            completion()
            return
        }
        
        completionHandler = completion
        isAdShowing = true
        interstitialAd.present(from: viewController)
        
        NSLog("インタースティシャル広告を表示しました")
    }
    
    /// 次の広告のために事前ロードを開始
    private func preloadNextAd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.loadInterstitialAd()
        }
    }
}

// MARK: - FullScreenContentDelegate
extension InterstitialAdManager: FullScreenContentDelegate {
    /// 広告の表示に成功
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        NSLog("インタースティシャル広告が表示されます")
    }
    
    /// 広告が閉じられた
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        NSLog("インタースティシャル広告が閉じられました")
        
        isAdShowing = false
        isAdReady = false
        interstitialAd = nil
        
        // コールバックを実行
        completionHandler?()
        completionHandler = nil
        
        // 次の広告を事前ロード
        preloadNextAd()
    }
    
    /// 広告の表示に失敗
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        NSLog("インタースティシャル広告の表示に失敗: %@", error.localizedDescription)
        
        isAdShowing = false
        isAdReady = false
        interstitialAd = nil
        
        // エラーの場合でもコールバックを実行（UXを損なわない）
        completionHandler?()
        completionHandler = nil
        
        // 次の広告を事前ロード
        preloadNextAd()
    }
}

// MARK: - UIViewController Extension for SwiftUI Integration
extension UIViewController {
    /// 現在のトップViewController を取得
    static func topMostViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return nil
        }
        
        var topController = window.rootViewController
        
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        
        if let navigationController = topController as? UINavigationController {
            return navigationController.visibleViewController
        }
        
        if let tabBarController = topController as? UITabBarController {
            return tabBarController.selectedViewController
        }
        
        return topController
    }
}
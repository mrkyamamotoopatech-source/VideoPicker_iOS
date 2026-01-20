//
//  TopView.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import SwiftUI
import Photos

struct ContentView: View {
    @State private var showPicker = false
    @State private var showDeniedAlert = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 16) {}
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    requestPhotoLibrary()
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle())
                        .shadow(radius: 6)
                        .padding(20)
                }
                .accessibilityLabel("動画選択へ")
            }
            .navigationTitle("VideoPicker")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showPicker) {
                Text("ここに VideoPicker を置く")
            }
            .alert("写真へのアクセスが必要です", isPresented: $showDeniedAlert) {
                Button("設定を開く") {
                    openAppSettings()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("動画一覧を表示するには写真ライブラリへのアクセスを許可してください。")
            }
        }
    }

    private func requestPhotoLibrary() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    handleStatus(newStatus)
                }
            }

        case .authorized, .limited:
            showPicker = true

        case .denied:
            // ここではもうOSの許可ダイアログは出ない（仕様）
            showDeniedAlert = true

        case .restricted:
            // 端末制限。設定へ誘導しても変えられない場合がある
            showDeniedAlert = true

        @unknown default:
            showDeniedAlert = true
        }
    }

    private func handleStatus(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited:
            showPicker = true
        case .denied, .restricted:
            showDeniedAlert = true
        default:
            break
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

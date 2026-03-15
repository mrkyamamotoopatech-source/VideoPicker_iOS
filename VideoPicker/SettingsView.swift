//
//  SettingsView.swift
//  VideoPicker
//
//  Created by Claude on 2026/03/14.
//

import SwiftUI
import CryptoKit

struct SettingsView: View {
    @AppStorage("scoringQuality") private var scoringQualityRawValue = ScoringQuality.medium.rawValue
    @AppStorage("isAdFree") private var isAdFree = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var secretCode = ""
    @State private var showSuccessAlert = false
    @State private var showFailureAlert = false
    
    // シークレットコードのハッシュ値
    private let targetHash = "4342ad90e8f17dab7ea31702a240fe352b60c6f8ce211c1c882fe8a2878283ff"
    
    private var scoringQuality: ScoringQuality {
        ScoringQuality(rawValue: scoringQualityRawValue) ?? .medium
    }
    
    private var appVersion: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return InfoPlistStrings.string("VP_Settings_Version_Unknown")
        }
        return "\(version) (\(build))"
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    // 採点精度設定
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(InfoPlistStrings.string("VP_Settings_ScoringQuality"), systemImage: "gauge.high")
                            Spacer()
                        }
                        
                        Picker("", selection: Binding(
                            get: { scoringQuality },
                            set: { scoringQualityRawValue = $0.rawValue }
                        )) {
                            ForEach(ScoringQuality.allCases, id: \.self) { quality in
                                Text(quality.displayName)
                                    .tag(quality)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        // 選択中の品質の説明を表示
                        Text(scoringQuality.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                    
                    // シークレットコード入力エリア
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .padding(.top, 16)
                        
                        HStack {
                            Label("広告非表示コード", systemImage: isAdFree ? "checkmark.shield.fill" : "shield")
                                .foregroundColor(isAdFree ? .green : .primary)
                            Spacer()
                            if isAdFree {
                                Text("有効")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        if !isAdFree {
                            HStack {
                                SecureField("コードを入力", text: $secretCode)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(isAdFree)
                                
                                Button("適用") {
                                    validateSecretCode()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(secretCode.isEmpty)
                            }
                        } else {
                            HStack {
                                Text("広告が無効化されています")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Spacer()
                                
                                Button("リセット") {
                                    isAdFree = false
                                    secretCode = ""
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(InfoPlistStrings.string("VP_Settings_Footer"))
                        if !isAdFree {
                            Text("正しいコードを入力すると広告が非表示になります")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
                
                Section {
                    // アプリバージョン
                    HStack {
                        Label(InfoPlistStrings.string("VP_Settings_Version"), systemImage: "info.circle")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(InfoPlistStrings.string("VP_Settings_Title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(InfoPlistStrings.string("VP_Button_Done")) {
                        dismiss()
                    }
                }
            }
            .alert("成功", isPresented: $showSuccessAlert) {
                Button("OK") {}
            } message: {
                Text("広告が無効化されました")
            }
            .alert("エラー", isPresented: $showFailureAlert) {
                Button("OK") {
                    secretCode = ""
                }
            } message: {
                Text("無効なコードです")
            }
        }
    }
    
    /// シークレットコードを検証
    private func validateSecretCode() {
        let inputHash = sha256(secretCode)
        
        if inputHash == targetHash {
            isAdFree = true
            secretCode = ""
            showSuccessAlert = true
        } else {
            showFailureAlert = true
        }
    }
    
    /// SHA256ハッシュを生成
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    SettingsView()
}
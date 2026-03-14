//
//  SettingsView.swift
//  VideoPicker
//
//  Created by Claude on 2026/03/14.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("scoringQuality") private var scoringQualityRawValue = ScoringQuality.medium.rawValue
    @Environment(\.dismiss) private var dismiss
    
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
                } footer: {
                    Text(InfoPlistStrings.string("VP_Settings_Footer"))
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
        }
    }
}

#Preview {
    SettingsView()
}
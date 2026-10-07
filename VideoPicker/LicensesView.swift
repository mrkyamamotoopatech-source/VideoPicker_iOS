//
//  LicensesView.swift
//  VideoPicker
//

import SwiftUI

/// 組み込んでいるオープンソースソフトウェアの一覧。行を選ぶとライセンス文を表示する
struct LicensesView: View {
    var body: some View {
        List(OpenSourceLicense.all) { license in
            NavigationLink {
                LicenseDetailView(license: license)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(license.name)
                    Text(license.licenseName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle(InfoPlistStrings.string("VP_Settings_Licenses"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// ライセンス文の全文表示
struct LicenseDetailView: View {
    let license: OpenSourceLicense

    var body: some View {
        ScrollView {
            Text(license.loadText() ?? InfoPlistStrings.string("VP_Licenses_LoadFailed"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}

import SwiftUI

// MARK: - AppInfoView (B06 アプリ情報モーダル画面)
// i18n (L10n) 完全対応
// バージョン、暗号化方式、ライセンス表示

public struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    private var licenseCount: Int {
        LicenseLoader.shared.loadLicenses().count
    }
    
    public var body: some View {
        NavigationStack {
            List {
                // Section 1: バージョン情報
                Section {
                    HStack {
                        Text(L10n.AppInfo.version)
                        Spacer()
                        Text(appVersionString)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Section 2: 暗号化方式
                Section {
                    HStack {
                        Text(L10n.AppInfo.encryption)
                        Spacer()
                        Text(L10n.AppInfo.encryptionDetail)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text(L10n.AppInfo.encryptionDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Section 3: オープンソースライセンス
                Section {
                    NavigationLink {
                        LicenseListView()
                    } label: {
                        HStack {
                            Text(L10n.AppInfo.licenses)
                                .foregroundColor(.primary)
                            Spacer()
                            if licenseCount > 0 {
                                Text("\(licenseCount)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.AppInfo.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

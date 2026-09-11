import SwiftUI

// MARK: - AppInfoView (B06 アプリ情報画面)
// i18n (L10n) 完全対応
// バージョン、暗号化方式（改行表示）、利用規約・プライバシーポリシー、ライセンス表示
// ※ モーダルではなく NavigationStack 経由の Push 画面

public struct AppInfoView: View {
    public init() {}
    
    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    public var body: some View {
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
            
            // Section 2: 暗号化方式 (2つの方式を改行表示)
            Section {
                HStack(alignment: .top) {
                    Text(L10n.AppInfo.encryption)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(L10n.AppInfo.encryptionDetail1)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(L10n.AppInfo.encryptionDetail2)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text(L10n.AppInfo.encryptionDesc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Section 3: 規約・ポリシー・ライセンス (利用規約・プライバシーポリシー・ライセンス表示)
            Section(L10n.Settings.sectionLegal) {
                NavigationLink {
                    TermsOfServiceView(isPresentedInModal: false)
                } label: {
                    Text(L10n.Legal.termsTitle)
                        .foregroundColor(.primary)
                }
                
                NavigationLink {
                    PrivacyPolicyView(isPresentedInModal: false)
                } label: {
                    Text(L10n.Legal.privacyTitle)
                        .foregroundColor(.primary)
                }
                
                NavigationLink {
                    LicenseListView()
                } label: {
                    Text(L10n.AppInfo.licenses)
                        .foregroundColor(.primary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.AppInfo.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

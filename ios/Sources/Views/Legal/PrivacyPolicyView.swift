import SwiftUI

// MARK: - PrivacyPolicyView
/// プライバシーポリシー画面 (個人情報保護法 & Apple Guideline 5.1.1 適合)
/// shared/legal/privacy_policy.md を読み込んでレンダリング
public struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    var isPresentedInModal: Bool
    
    public init(isPresentedInModal: Bool = false) {
        self.isPresentedInModal = isPresentedInModal
    }
    
    public var body: some View {
        if isPresentedInModal {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(L10n.Common.close) {
                                dismiss()
                            }
                        }
                    }
            }
        } else {
            content
        }
    }
    
    private var content: some View {
        LegalMarkdownView(fileName: "privacy_policy")
            .navigationTitle(L10n.Legal.privacyTitle)
            .navigationBarTitleDisplayMode(.inline)
    }
}

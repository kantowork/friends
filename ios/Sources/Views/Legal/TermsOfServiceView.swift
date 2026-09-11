import SwiftUI

// MARK: - TermsOfServiceView
/// 利用規約 (EULA) 画面 (Apple Guideline 1.2 ゼロトレランス方針準拠)
/// shared/legal/terms_of_service.md を読み込んでレンダリング
public struct TermsOfServiceView: View {
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
        LegalMarkdownView(fileName: "terms_of_service")
            .navigationTitle(L10n.Legal.termsTitle)
            .navigationBarTitleDisplayMode(.inline)
    }
}

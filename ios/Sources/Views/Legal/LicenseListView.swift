import SwiftUI

// MARK: - LicenseListView (B06-a オープンソースライセンス画面)
/// shared/legal/licenses.md を読み込んでレンダリング
public struct LicenseListView: View {
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
                        ToolbarItem(placement: .confirmationAction) {
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
        LegalMarkdownView(fileName: "licenses")
            .navigationTitle(L10n.AppInfo.licenses)
            .navigationBarTitleDisplayMode(.inline)
    }
}

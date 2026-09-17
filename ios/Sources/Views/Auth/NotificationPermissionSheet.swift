import SwiftUI

// MARK: - NotificationPermissionSheet (A06m)
/// 初回ログイン後に表示するメッセージ通知の事前説明シート (ソフトプロンプト)
public struct NotificationPermissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var notificationManager = NotificationManager.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // アイコン & イラスト
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.2), Color.appAccent.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "bell.badge.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 44))
                    .foregroundColor(Color.appAccent)
            }
            
            // 説明テキスト
            VStack(spacing: 12) {
                Text(L10n.Notification.permissionTitle)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                
                Text(L10n.Notification.permissionDesc)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // アクションボタン群
            VStack(spacing: 12) {
                // 通知をオンにする
                Button {
                    notificationManager.requestNotificationPermission { _ in
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.fill")
                        Text(L10n.Notification.enableButton)
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(Color.appAccent)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                
                // あとで
                Button {
                    notificationManager.markPromptAsHandled()
                    dismiss()
                } label: {
                    Text(L10n.Notification.laterButton)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

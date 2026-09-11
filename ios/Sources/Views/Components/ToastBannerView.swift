import SwiftUI

// MARK: - ToastBannerView
// 新規メッセージ受信時のアプリ内トースト通知バナー UI

public struct ToastBannerView: View {
    let toast: InAppToast
    let onTap: () -> Void
    let onDismiss: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    
    public init(
        toast: InAppToast,
        onTap: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.toast = toast
        self.onTap = onTap
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 送信者アイコン (グループトーク: グループアイコン / 1:1トーク: 送信元アバター)
                if toast.isGroup {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.85), Color.pink.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 42, height: 42)
                        
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                } else {
                    UserAvatarView(
                        userId: toast.senderId,
                        displayName: toast.senderName,
                        avatarNonce: toast.avatarNonce,
                        avatarUpdatedAt: toast.avatarUpdatedAt,
                        size: 42
                    )
                }
                
                // 送信者名 & メッセージ本文プレビュー
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(toast.senderName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formattedTime(toast.createdAt))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Text(toast.messageText.isEmpty ? L10n.Toast.newMessage : toast.messageText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                // 遷移インジケータ
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .offset(y: min(0, dragOffset))
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height < -20 {
                        onDismiss()
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = 0
                        }
                    }
                }
        )
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

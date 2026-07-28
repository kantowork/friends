import Foundation
import SwiftUI
import Combine

// MARK: - ToastNotificationManager
// 新規メッセージ受信時のフォアグラウンドアプリ内トースト通知を制御するシングルトンマネージャー

@MainActor
final class ToastNotificationManager: ObservableObject {
    static let shared = ToastNotificationManager()
    
    /// 現在表示中のトースト通知
    @Published var currentToast: InAppToast?
    
    /// トーストタップ時に遷移すべき対象チャット情報
    @Published var navigationTargetChat: FriendsChatUIModel?
    
    /// 最後に受信・通知したメッセージID（重複防止用）
    private var lastNotifiedMessageId: String?
    
    /// 自動消去タイマー
    private var dismissTask: Task<Void, Never>?
    
    init() {}
    
    /// トースト通知を表示
    public func show(
        chatId: String,
        senderId: String,
        senderName: String,
        messageText: String,
        messageId: String? = nil,
        isGroup: Bool = false,
        avatarNonce: String = "",
        avatarUpdatedAt: Date? = nil,
        duration: TimeInterval = 4.0
    ) {
        // メッセージIDの重複チェック
        if let msgId = messageId {
            if lastNotifiedMessageId == msgId {
                return
            }
            lastNotifiedMessageId = msgId
        }
        
        // 既存の自動消去タスクをキャンセル
        dismissTask?.cancel()
        
        let newToast = InAppToast(
            chatId: chatId,
            senderId: senderId,
            senderName: senderName,
            messageText: messageText,
            isGroup: isGroup,
            avatarNonce: avatarNonce,
            avatarUpdatedAt: avatarUpdatedAt
        )
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.currentToast = newToast
        }
        
        // 指定秒数後に自動消去
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss()
            }
        }
    }
    
    /// トーストを手動消去
    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            self.currentToast = nil
        }
    }
    
    /// トーストタップ時の処理 (対象チャットへの遷移を指示)
    public func handleToastTap(_ toast: InAppToast) {
        dismiss()
        
        // ChatService のチャット一覧から対象を検索
        let chatService = ChatService.shared
        if let existingChat = chatService.chats.first(where: { $0.chatID == toast.chatId }) {
            self.navigationTargetChat = existingChat
        } else if let friend = chatService.friends.first(where: { $0.userID == toast.senderId || $0.uid == toast.senderId }) {
            // 友達情報から FriendsChatUIModel を生成
            let tenantId = chatService.currentTenant?.tenantID ?? ""
            let currentUserId = chatService.currentUser?.userID ?? ""
            let fallbackChat = FriendsChatUIModel(
                chat: FriendsChat(
                    chatID: toast.chatId,
                    tenantID: tenantId,
                    chatType: .direct,
                    members: [currentUserId, friend.userID].sorted()
                ),
                title: friend.displayName,
                lastMessage: toast.messageText,
                lastMessageAt: toast.createdAt,
                unreadCount: 0
            )
            self.navigationTargetChat = fallbackChat
        } else {
            // 汎用 FriendsChatUIModel
            let tenantId = chatService.currentTenant?.tenantID ?? ""
            let fallbackChat = FriendsChatUIModel(
                chat: FriendsChat(
                    chatID: toast.chatId,
                    tenantID: tenantId,
                    chatType: .direct,
                    members: []
                ),
                title: toast.senderName,
                lastMessage: toast.messageText,
                lastMessageAt: toast.createdAt,
                unreadCount: 0
            )
            self.navigationTargetChat = fallbackChat
        }
    }
}

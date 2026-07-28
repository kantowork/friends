import SwiftUI

// MARK: - FriendListView (C01/C04 友達・チャット一覧画面)
// i18n (L10n) 完全対応
// 右上: ユーザー追加アイコン (person.crop.circle.badge.plus) -> AddFriendView へ遷移
// リスト: チャット一覧（メッセージ最新順ソート、未読バッジ表示、ユーザーID表記なし）

public struct FriendListView: View {
    @ObservedObject var chatService = ChatService.shared
    @State private var showingAddFriendSheet = false
    
    private struct FriendRowItem: Identifiable {
        let friend: FriendsPublicUserProfile
        let chat: FriendsChatUIModel
        var id: String {
            "\(friend.userID)_\(friend.avatarNonce)_\(friend.avatarUpdatedAt.seconds)_\(chat.lastMessageAt.timeIntervalSince1970)_\(chat.unreadCount)"
        }
    }

    
    private var friendRowItems: [FriendRowItem] {
        let currentUserId = chatService.currentUser?.userID ?? ""
        let currentTenantId = chatService.currentTenant?.tenantID ?? ""
        
        return chatService.friends.map { friend in
            let dmChatId = "dm_" + [currentUserId, friend.userID].sorted().joined(separator: "_")
            let calculatedUnread = chatService.unreadCount(for: dmChatId)
            
            let chatUI: FriendsChatUIModel
            if let existingChat = chatService.chats.first(where: { $0.chatID == dmChatId }) {
                let latestDecrypted = chatService.messages[dmChatId]?.last
                let effectiveLastMessage = latestDecrypted?.decryptedText ?? existingChat.lastMessage
                let effectiveLastMessageAt = latestDecrypted?.createdDate ?? existingChat.lastMessageAt
                
                chatUI = FriendsChatUIModel(
                    chat: existingChat.chat,
                    title: friend.displayName,
                    lastMessage: effectiveLastMessage,
                    lastMessageAt: effectiveLastMessageAt,
                    unreadCount: calculatedUnread
                )
            } else {
                let latestDecrypted = chatService.messages[dmChatId]?.last
                let effectiveLastMessage = latestDecrypted?.decryptedText ?? ""
                let effectiveLastMessageAt = latestDecrypted?.createdDate ?? Date.distantPast
                
                chatUI = FriendsChatUIModel(
                    chat: FriendsChat(
                        chatID: dmChatId,
                        tenantID: currentTenantId,
                        chatType: .direct,
                        members: [currentUserId, friend.userID].sorted()
                    ),
                    title: friend.displayName,
                    lastMessage: effectiveLastMessage,
                    lastMessageAt: effectiveLastMessageAt,
                    unreadCount: calculatedUnread
                )
            }
            return FriendRowItem(friend: friend, chat: chatUI)
        }.sorted { (i1: FriendRowItem, i2: FriendRowItem) -> Bool in
            if i1.chat.lastMessageAt != i2.chat.lastMessageAt {
                return i1.chat.lastMessageAt > i2.chat.lastMessageAt
            }
            return i1.chat.title < i2.chat.title
        }
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if friendRowItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 24)
                            Text(L10n.Friend.listEmpty)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 24)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(friendRowItems) { item in
                            NavigationLink(destination: ChatDetailView(chat: item.chat)) {
                                ChatRowView(chat: item.chat, friend: item.friend)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            .navigationTitle(L10n.Friend.listTitle)
            .refreshable {
                await withCheckedContinuation { continuation in
                    chatService.refreshFriendsProfiles(force: true) {
                        continuation.resume()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddFriendSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.blue)
                    }
                    .accessibilityLabel(L10n.Friend.addBtn)
                }
            }
            .sheet(isPresented: $showingAddFriendSheet) {
                AddFriendView()
            }
        }
    }
}

// MARK: - ChatRowView (個別チャットセル: ユーザーID非表示・未読バッジ・最新メッセージ・時間表示)

private struct ChatRowView: View {
    let chat: FriendsChatUIModel
    let friend: FriendsPublicUserProfile?
    
    var body: some View {
        HStack(spacing: 12) {
            // アバターアイコン (キャッシュ優先・暗号化アバター対応)
            UserAvatarView(
                userId: friend?.userID ?? chat.chatID,
                displayName: friend?.displayName ?? chat.title,
                avatarNonce: friend?.avatarNonce ?? "",
                avatarUpdatedAt: friend?.avatarUpdatedDate,
                size: 48
            )
            
            // 表示名 & 最新メッセージ


            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !chat.lastMessage.isEmpty {
                    Text(chat.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("メッセージのやり取りはありません")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 日時 & 未読バッジ
            VStack(alignment: .trailing, spacing: 6) {
                if chat.lastMessageAt != Date.distantPast {
                    Text(formattedTimestamp(chat.lastMessageAt))
                        .font(.caption2)
                        .foregroundColor(chat.unreadCount > 0 ? .blue : .secondary)
                }
                
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption2)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue)
                        .clipShape(Capsule())
                } else {
                    // レイアウト維持用Spacerまたは透過プレースホルダー
                    Spacer()
                        .frame(height: 18)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨日"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}


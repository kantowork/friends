import SwiftUI

// MARK: - FriendListView (C01/C04 友達・チャット一覧画面)
// i18n (L10n) 完全対応
// 右上: ユーザー追加アイコン (person.crop.circle.badge.plus) -> AddFriendView へ遷移
// リスト: チャット一覧（メッセージ最新順ソート、未読バッジ表示、ユーザーID表記なし）

public struct FriendListView: View {
    @ObservedObject var directChatService = DirectChatService.shared
    @ObservedObject var messageService = MessageService.shared
    @ObservedObject var authService = AuthService.shared
    
    @State private var showingAddFriendSheet = false
    @State private var editingFriend: FriendsPublicUserProfile? = nil
    @State private var newFriendDisplayName: String = ""
    @Binding var navigationPath: NavigationPath
    
    public init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        self._navigationPath = navigationPath
    }
    
    private struct FriendRowItem: Identifiable {
        let friend: FriendsPublicUserProfile
        let chat: FriendsChatUIModel
        var id: String {
            "\(friend.userID)_\(friend.displayName)_\(friend.avatarNonce)_\(friend.avatarUpdatedAt.seconds)_\(chat.lastMessageAt.timeIntervalSince1970)_\(chat.unreadCount)"
        }
    }

    
    private var friendRowItems: [FriendRowItem] {
        let currentUserId = authService.currentUser?.userID ?? ""
        let currentTenantId = authService.currentTenant?.tenantID ?? ""
        
        return directChatService.friends.map { friend in
            let dmChatId = "dm_" + [currentUserId, friend.userID].sorted().joined(separator: "_")
            let calculatedUnread = messageService.unreadCount(for: dmChatId)
            let latestDecrypted = messageService.messages[dmChatId]?.last
            let effectiveLastMessage = latestDecrypted?.summaryText ?? ""
            let effectiveLastMessageAt = latestDecrypted?.createdDate ?? Date.distantPast
            
            let chatUI = FriendsChatUIModel(
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
            return FriendRowItem(friend: friend, chat: chatUI)
        }.sorted { (i1: FriendRowItem, i2: FriendRowItem) -> Bool in
            if i1.chat.lastMessageAt != i2.chat.lastMessageAt {
                return i1.chat.lastMessageAt > i2.chat.lastMessageAt
            }
            return i1.chat.title < i2.chat.title
        }
    }
    
    public var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    if friendRowItems.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.system(.largeTitle))
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
                            NavigationLink(value: item.chat) {
                                ChatRowView(chat: item.chat, friend: item.friend)
                            }
                            .contextMenu {
                                Button {
                                    editingFriend = item.friend
                                    newFriendDisplayName = item.friend.displayName
                                } label: {
                                    Label(L10n.Friend.editNameAction, systemImage: "pencil")
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    editingFriend = item.friend
                                    newFriendDisplayName = item.friend.displayName
                                } label: {
                                    Label(L10n.Friend.editNameAction, systemImage: "pencil")
                                }
                                .tint(.appAccent)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Friend.listTitle)
            .navigationDestination(for: FriendsChatUIModel.self) { chat in
                ChatDetailView(chat: chat)
            }
            .refreshable {
                await withCheckedContinuation { continuation in
                    directChatService.listFriendsProfiles(force: true) {
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
                            .foregroundColor(.appAccent)
                    }
                    .accessibilityLabel(L10n.Friend.addBtn)
                }
            }
            .sheet(isPresented: $showingAddFriendSheet) {
                AddFriendView()
            }
            .alert(L10n.Friend.editNameTitle, isPresented: Binding(
                get: { editingFriend != nil },
                set: { if !$0 { editingFriend = nil } }
            )) {
                TextField(L10n.Friend.editNamePlaceholder, text: $newFriendDisplayName)
                Button(L10n.Common.cancel, role: .cancel) {
                    editingFriend = nil
                }
                Button(L10n.Common.save) {
                    if let target = editingFriend {
                        let trimmed = newFriendDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            directChatService.updateFriendDisplayName(friendUserId: target.userID, newDisplayName: trimmed) { _ in
                                editingFriend = nil
                            }
                        } else {
                            editingFriend = nil
                        }
                    }
                }
            } message: {
                Text(L10n.Friend.editNameMessage)
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
            .fixedSize()
            .layoutPriority(1)
            
            // 表示名 & 最新メッセージ
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                if !chat.lastMessage.isEmpty {
                    Text(chat.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text(L10n.Chat.noMessages)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            
            Spacer()
            
            // 日時 & 未読バッジ
            VStack(alignment: .trailing, spacing: 6) {
                if chat.lastMessageAt != Date.distantPast {
                    Text(formattedTimestamp(chat.lastMessageAt))
                        .font(.caption2)
                        .foregroundColor(chat.unreadCount > 0 ? .appAccent : .secondary)
                }
                
                if chat.unreadCount > 0 {
                    Text("\(chat.unreadCount)")
                        .font(.caption2)
                        .bold()
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appAccent)
                        .clipShape(Capsule())
                } else {
                    // レイアウト維持用透過プレースホルダー (Dynamic Type連動)
                    Text(" ")
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .opacity(0)
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
            return L10n.Common.yesterday
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return formatter.string(from: date)
        }
    }
}


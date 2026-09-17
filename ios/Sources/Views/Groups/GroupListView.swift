import SwiftUI

// MARK: - GroupListView (D01 グループチャット一覧画面 / タブ名: かいぎ)
// i18n (L10n) 完全対応
// 右上: 新規グループ作成ボタン (plus) -> CreateGroupView へ遷移
// リスト: 参加中グループチャット一覧（メッセージ最新順ソート、未読バッジ表示）

public struct GroupListView: View {
    @ObservedObject var groupChatService = GroupChatService.shared
    @ObservedObject var messageService = MessageService.shared
    @State private var showingCreateGroupSheet = false
    @Binding var navigationPath: NavigationPath
    
    public init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        self._navigationPath = navigationPath
    }
    
    /// グループチャット一覧（最新メッセージ時刻降順）
    private var groupListItems: [FriendsChatUIModel] {
        return groupChatService.groupChats.map { groupChat in
            let calculatedUnread = messageService.unreadCount(for: groupChat.chatID)
            let latestDecrypted = messageService.messages[groupChat.chatID]?.last
            let effectiveLastMessage = latestDecrypted?.summaryText ?? groupChat.lastMessage
            let effectiveLastMessageAt = latestDecrypted?.createdDate ?? groupChat.lastMessageAt
            
            return FriendsChatUIModel(
                chat: groupChat.chat,
                title: groupChat.title,
                lastMessage: effectiveLastMessage,
                lastMessageAt: effectiveLastMessageAt,
                unreadCount: calculatedUnread,
                avatarNonce: groupChat.avatarNonce,
                avatarUpdatedAt: groupChat.avatarUpdatedAt
            )
        }.sorted { c1, c2 in
            if c1.lastMessageAt != c2.lastMessageAt {
                return c1.lastMessageAt > c2.lastMessageAt
            }
            return c1.title < c2.title
        }
    }
    
    public var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    if groupListItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(.largeTitle))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 28)
                            Text(L10n.Group.listEmpty)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 28)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(groupListItems) { item in
                            NavigationLink(value: item) {
                                GroupChatRowView(chat: item)
                                    .id("\(item.chatID)_\(item.avatarNonce)_\(item.avatarUpdatedAt?.timeIntervalSince1970 ?? 0)_\(item.lastMessageAt.timeIntervalSince1970)_\(item.unreadCount)")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Group.listTitle)
            .refreshable {
                await withCheckedContinuation { continuation in
                    groupChatService.listGroupChats {
                        continuation.resume()
                    }
                }
            }
            .navigationDestination(for: FriendsChatUIModel.self) { chat in
                ChatDetailView(chat: chat)
            }
            .navigationDestination(for: GroupDetailRoute.self) { route in
                GroupDetailView(chat: route.chat, onGroupDeletedOrLeft: {
                    navigationPath = NavigationPath()
                })
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreateGroupSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroupSheet) {
                CreateGroupView { newChat in
                    navigationPath.append(newChat)
                }
            }
        }
    }
}

// MARK: - GroupChatRowView (グループチャット一覧行)

struct GroupChatRowView: View {
    let chat: FriendsChatUIModel
    
    var body: some View {
        HStack(spacing: 12) {
            // グループアバター
            GroupAvatarView(
                chatId: chat.chatID,
                avatarNonce: chat.avatarNonce,
                avatarUpdatedAt: chat.avatarUpdatedAt,
                size: 48
            )
            .fixedSize()
            .layoutPriority(1)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Text(L10n.Group.memberCountFormat(chat.chat.members.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if chat.lastMessageAt != Date.distantPast && !chat.lastMessage.isEmpty {
                        Text(chat.lastMessageAt, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text(chat.lastMessage.isEmpty ? L10n.Group.groupCreated : chat.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Spacer()
                    
                    // 未読件数バッジ
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appAccent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

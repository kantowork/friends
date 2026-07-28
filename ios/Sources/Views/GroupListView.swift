import SwiftUI

// MARK: - GroupListView (D01 グループチャット一覧画面 / タブ名: かいぎ)
// i18n (L10n) 完全対応
// 右上: 新規グループ作成ボタン (plus) -> CreateGroupView へ遷移
// リスト: 参加中グループチャット一覧（メッセージ最新順ソート、未読バッジ表示）

public struct GroupListView: View {
    @ObservedObject var chatService = ChatService.shared
    @State private var showingCreateGroupSheet = false
    @State private var navigationPath = NavigationPath()
    
    public init() {}
    
    /// グループチャット一覧（最新メッセージ時刻降順）
    private var groupListItems: [FriendsChatUIModel] {
        return chatService.groupChats.map { groupChat in
            let calculatedUnread = chatService.unreadCount(for: groupChat.chatID)
            let latestDecrypted = chatService.messages[groupChat.chatID]?.last
            let effectiveLastMessage = latestDecrypted?.decryptedText ?? groupChat.lastMessage
            let effectiveLastMessageAt = latestDecrypted?.createdDate ?? groupChat.lastMessageAt
            
            return FriendsChatUIModel(
                chat: groupChat.chat,
                title: groupChat.title,
                lastMessage: effectiveLastMessage,
                lastMessageAt: effectiveLastMessageAt,
                unreadCount: calculatedUnread
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
                                .font(.system(size: 42))
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
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Group.listTitle)
            .navigationDestination(for: FriendsChatUIModel.self) { chat in
                ChatDetailView(chat: chat)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreateGroupSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
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
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.8), Color.pink.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("(\(chat.chat.members.count))")
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
                    Text(chat.lastMessage.isEmpty ? "グループが作成されました" : chat.lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // 未読件数バッジ
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

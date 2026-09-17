import SwiftUI

// MARK: - B01 HomeView (ホーム画面)
// クイックアクセス・お知らせを提供するホーム画面

public struct HomeView: View {
    @ObservedObject var tenantManager = TenantManager.shared
    @ObservedObject var directChatService = DirectChatService.shared
    @ObservedObject var groupChatService = GroupChatService.shared
    @ObservedObject var messageService = MessageService.shared
    @ObservedObject var authService = AuthService.shared
    
    @State private var showingAddFriendSheet = false
    @State private var showingTenantSwitchSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Action Buttons (最上段・セカンダリボタン)
                    quickActionsSection
                    
                    // Unread Messages Section (未読チャット一覧)
                    unreadMessagesSection
                    
                    // Notifications / Activity Section
                    notificationSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.Tab.home)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // ⚙️ 設定ボタン
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingAddFriendSheet) {
                AddFriendView()
            }
            .sheet(isPresented: $showingTenantSwitchSheet) {
                TenantSwitcherView()
            }
            .onAppear {
                tenantManager.refreshUnreadCounts()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Home.quickActionTitle)
                .font(.footnote)
                .bold()
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button {
                    showingAddFriendSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.headline)
                        Text(L10n.Home.quickActionAddFriend)
                            .font(.subheadline)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .foregroundColor(.appAccent)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.appAccent.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Unread Messages Section (Fan-out on Read)
    
    @ViewBuilder
    private var unreadMessagesSection: some View {
        let unreadChats = messageService.getUnreadChats()
        if !unreadChats.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.Home.unreadSectionTitle)
                        .font(.footnote)
                        .bold()
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(unreadChats.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.appAccent)
                        .clipShape(Capsule())
                }
                
                VStack(spacing: 0) {
                    ForEach(Array(unreadChats.enumerated()), id: \.element.id) { index, chat in
                        NavigationLink {
                            ChatDetailView(chat: chat)
                        } label: {
                            unreadChatRow(chat)
                        }
                        .buttonStyle(.plain)
                        
                        if index < unreadChats.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }
    
    private func unreadChatRow(_ item: FriendsChatUIModel) -> some View {
        HStack(spacing: 12) {
            // アバター表示
            if item.chatType == .group {
                GroupAvatarView(
                    chatId: item.chatID,
                    avatarNonce: item.avatarNonce,
                    avatarUpdatedAt: item.avatarUpdatedAt,
                    size: 44
                )
            } else {
                let currentUserId = authService.currentUser?.userID ?? ""
                let peerUserId = item.chat.members.first(where: { $0 != currentUserId }) ?? item.chatID
                UserAvatarView(
                    userId: peerUserId,
                    displayName: item.displayTitle,
                    avatarNonce: item.avatarNonce,
                    avatarUpdatedAt: item.avatarUpdatedAt,
                    size: 44
                )
            }
            
            // チャット名 & 最新時刻
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.displayTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if item.lastMessageAt > Date.distantPast {
                        Text(item.lastMessageAt, style: .time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text(item.chatType == .group ? L10n.Tab.groups : L10n.Tab.friends)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if item.unreadCount > 0 {
                        Text("\(item.unreadCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.appAccent)
                            .clipShape(Capsule())
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Home.notificationTitle)
                .font(.footnote)
                .bold()
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(.largeTitle))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 16)
                
                Text(L10n.Home.notificationEmpty)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

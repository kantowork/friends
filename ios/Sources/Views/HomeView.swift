import SwiftUI

// MARK: - B01 HomeView (ホーム画面)
// お知らせ・テナントステータス・クイックアクセスを提供するホーム画面

public struct HomeView: View {
    @ObservedObject var chatService = ChatService.shared
    @State private var showingAddFriendSheet = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Tenant Banner Card
                    tenantStatusCard
                    
                    // Quick Action Buttons
                    quickActionsSection
                    
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
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingAddFriendSheet) {
                AddFriendView()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var tenantStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(chatService.currentTenant?.tenantName ?? "デフォルト組織")
                        .font(.headline)
                        .bold()
                    if let code = chatService.currentTenant?.tenantCode, !code.isEmpty {
                        Text("@\(code)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("接続中")
                        .font(.caption2)
                        .bold()
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .clipShape(Capsule())
            }
            
            Divider()
            
            HStack(spacing: 12) {
                if let user = chatService.currentUser {
                    UserAvatarView(
                        userId: user.userID,
                        displayName: user.displayName,
                        avatarNonce: user.avatarNonce,
                        avatarUpdatedAt: user.avatarUpdatedDate,
                        size: 40
                    )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("ログインアカウント")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(chatService.currentUser?.displayName ?? "ユーザー")
                        .font(.subheadline)
                        .bold()
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ユーザーID")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(chatService.currentUser?.userID ?? "-")
                        .font(.caption)
                        .monospaced()
                }
            }

        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("クイックアクション")
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
                        Text("友達を追加")
                            .font(.subheadline)
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("お知らせ")
                .font(.footnote)
                .bold()
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 16)
                
                Text("新しいお知らせはありません")
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

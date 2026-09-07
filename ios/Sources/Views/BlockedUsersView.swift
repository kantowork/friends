import SwiftUI

// MARK: - BlockedUsersView
/// ブロックしたユーザーの一覧確認およびブロック解除画面
public struct BlockedUsersView: View {
    @ObservedObject var blockManager = BlockManager.shared
    @ObservedObject var chatService = ChatService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var unblockingUserId: String? = nil
    @State private var showingUnblockAlert: Bool = false
    
    public init() {}
    
    private var blockedUsersList: [String] {
        Array(blockManager.blockedUserIds)
    }
    
    public var body: some View {
        List {
            if blockedUsersList.isEmpty {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "shield.checkmark.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.7))
                        
                        Text(L10n.Block.listEmpty)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(blockedUsersList, id: \.self) { userId in
                        let profile = chatService.userProfile(for: userId)
                        HStack(spacing: 12) {
                            UserAvatarView(
                                userId: userId,
                                displayName: profile?.displayName ?? userId,
                                avatarNonce: profile?.avatarNonce ?? "",
                                avatarUpdatedAt: profile?.avatarUpdatedDate,
                                size: 40
                            )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile?.displayName ?? userId)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                Text(userId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(L10n.Block.unblockAction) {
                                unblockingUserId = userId
                                showingUnblockAlert = true
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.Block.listTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            L10n.Block.unblockConfirmTitle(chatService.userProfile(for: unblockingUserId ?? "")?.displayName ?? unblockingUserId ?? ""),
            isPresented: $showingUnblockAlert
        ) {
            Button(L10n.Common.cancel, role: .cancel) {
                unblockingUserId = nil
            }
            Button(L10n.Block.unblockExecute) {
                if let uid = unblockingUserId {
                    blockManager.unblock(userId: uid)
                }
                unblockingUserId = nil
            }
        } message: {
            Text(L10n.Block.unblockConfirmMsg)
        }
    }
}

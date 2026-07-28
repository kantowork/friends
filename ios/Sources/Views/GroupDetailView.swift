import SwiftUI

// MARK: - GroupDetailView (D04 グループ詳細・メンバー一覧画面)
// グループ情報、参加メンバー一覧の表示

struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let chat: FriendsChatUIModel
    @ObservedObject var chatService = ChatService.shared
    
    var groupMembers: [FriendsPublicUserProfile] {
        var result: [FriendsPublicUserProfile] = []
        let memberUids = chat.chat.members
        
        // 自分自身
        if let current = chatService.currentUser, memberUids.contains(current.uid) {
            result.append(current)
        }
        
        // 登録されている友達
        for friend in chatService.friends {
            if memberUids.contains(friend.uid) && !result.contains(where: { $0.uid == friend.uid }) {
                result.append(friend)
            }
        }
        
        return result
    }
    
    var body: some View {
        List {
            // Section 1: グループ概要
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.orange.opacity(0.8), Color.pink.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.displayTitle)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(chat.chat.createdDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            
            // Section 2: 参加メンバー一覧
            Section(header: Text(L10n.Group.membersSection(chat.chat.members.count))) {
                if groupMembers.isEmpty {
                    Text("\(chat.chat.members.count) 人のメンバーが参加中")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(groupMembers) { member in
                        HStack(spacing: 12) {
                            UserAvatarView(
                                userId: member.userID,
                                displayName: member.displayName,
                                avatarNonce: member.avatarNonce,
                                avatarUpdatedAt: member.avatarUpdatedDate,
                                size: 36
                            )
                            
                            VStack(alignment: .leading, spacing: 2) {

                                HStack {
                                    Text(member.displayName)
                                        .font(.body)
                                    if member.uid == chatService.currentUser?.uid {
                                        Text("(\(L10n.Reaction.you))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.Group.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

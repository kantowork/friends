import SwiftUI

// MARK: - AddGroupMemberSheet (かいぎメンバー追加モーダルシート)
// 未参加の友達一覧から複数名を選択してかいぎに追加するモーダルビュー

struct AddGroupMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var chatService = ChatService.shared
    
    let chatId: String
    let existingMemberIds: [String]
    let onMembersAdded: (([String]) -> Void)?
    
    @State private var selectedFriendUserIds: Set<String> = []
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    
    init(
        chatId: String,
        existingMemberIds: [String],
        onMembersAdded: (([String]) -> Void)? = nil
    ) {
        self.chatId = chatId
        self.existingMemberIds = existingMemberIds
        self.onMembersAdded = onMembersAdded
    }
    
    init(
        chat: FriendsChatUIModel,
        onMembersAdded: (([String]) -> Void)? = nil
    ) {
        self.chatId = chat.chatID
        self.existingMemberIds = chat.chat.members
        self.onMembersAdded = onMembersAdded
    }
    
    /// まだグループに参加していない友達候補リスト
    private var candidateFriends: [FriendsPublicUserProfile] {
        let existingSet = Set(existingMemberIds)
        return chatService.friends.filter { !existingSet.contains($0.userID) }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if candidateFriends.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.top, 24)
                        Text(L10n.Group.addMemberNoCandidates)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(candidateFriends) { friend in
                            Button {
                                if selectedFriendUserIds.contains(friend.userID) {
                                    selectedFriendUserIds.remove(friend.userID)
                                } else {
                                    selectedFriendUserIds.insert(friend.userID)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    // 友達アバター
                                    UserAvatarView(
                                        userId: friend.userID,
                                        displayName: friend.displayName,
                                        avatarNonce: friend.avatarNonce,
                                        avatarUpdatedAt: friend.avatarUpdatedDate,
                                        size: 40
                                    )
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        if !friend.username.isEmpty {
                                            Text("@\(friend.username)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // 選択チェックマーク
                                    Image(systemName: selectedFriendUserIds.contains(friend.userID) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(selectedFriendUserIds.contains(friend.userID) ? .blue : .secondary.opacity(0.4))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if !selectedFriendUserIds.isEmpty {
                            Text(L10n.Group.addMemberSelectCount(selectedFriendUserIds.count))
                        }
                    }
                }
                
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Group.addMemberTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submitAddMembers()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(L10n.Group.addMemberSubmitBtn)
                                .bold()
                        }
                    }
                    .disabled(selectedFriendUserIds.isEmpty || isSubmitting)
                }
            }
        }
    }
    
    private func submitAddMembers() {
        guard !selectedFriendUserIds.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        let newMemberIds = Array(selectedFriendUserIds)
        
        chatService.addMembersToGroup(chatId: chatId, newMemberUserIds: newMemberIds) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success:
                    self.onMembersAdded?(newMemberIds)
                    self.dismiss()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

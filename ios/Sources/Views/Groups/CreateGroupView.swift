import SwiftUI

// MARK: - CreateGroupView (D03 新規グループ作成画面)
// グループ名の入力と、友達一覧からのチェックボックスによる複数メンバー選択を行うモーダルビュー

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var directChatService = DirectChatService.shared
    @ObservedObject var groupChatService = GroupChatService.shared
    
    @State private var groupName: String = ""
    @State private var selectedFriendUserIds: Set<String> = []
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    
    let onGroupCreated: ((FriendsChatUIModel) -> Void)?
    
    init(onGroupCreated: ((FriendsChatUIModel) -> Void)? = nil) {
        self.onGroupCreated = onGroupCreated
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Section 1: グループ名入力
                Section(header: Text(L10n.Group.nameLabel)) {
                    TextField(L10n.Group.namePlaceholder, text: $groupName)
                        .autocorrectionDisabled(true)
                }
                
                // Section 2: メンバー選択
                Section(header: Text(L10n.Group.selectMembers(selectedFriendUserIds.count))) {
                    if directChatService.friends.isEmpty {
                        Text(L10n.Group.noFriends)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(directChatService.friends) { friend in
                            Button {
                                if selectedFriendUserIds.contains(friend.userID) {
                                    selectedFriendUserIds.remove(friend.userID)
                                } else {
                                    selectedFriendUserIds.insert(friend.userID)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    // 友達アバター
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [Color.appAccent.opacity(0.7), Color.purple.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(width: 36, height: 36)
                                        Text(friend.displayName.prefix(1).uppercased())
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text(friend.displayName)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    // チェックマーク
                                    if selectedFriendUserIds.contains(friend.userID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.appAccent)
                                            .font(.system(size: 22))
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary.opacity(0.4))
                                            .font(.system(size: 22))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(L10n.Group.createTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Group.submitBtn) {
                        submitCreateGroup()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .fontWeight(.bold)
                }
            }
        }
    }
    
    private func submitCreateGroup() {
        let cleanName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        groupChatService.createGroup(title: cleanName, memberUserIds: Array(selectedFriendUserIds)) { result in
            DispatchQueue.main.async {
                self.isSubmitting = false
                switch result {
                case .success(let createdChat):
                    self.dismiss()
                    self.onGroupCreated?(createdChat)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

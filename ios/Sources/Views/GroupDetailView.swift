import SwiftUI
import PhotosUI

// MARK: - GroupDetailView (D04 グループ詳細・メンバー一覧画面)
// グループ情報、参加メンバー一覧、メンバー属性(role)表示・操作、退室管理、および重要操作グループ削除（1回確認ダイアログ）

struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let chat: FriendsChatUIModel
    @ObservedObject var chatService = ChatService.shared
    
    // アラート管理状態
    @State private var showDeleteAlert: Bool = false
    @State private var showClaimOwnerAlert: Bool = false
    @State private var showAssignAdminAlert: Bool = false
    @State private var targetAssignAdminMember: FriendsPublicUserProfile? = nil
    @State private var showRemoveMemberAlert: Bool = false
    @State private var targetRemoveMember: FriendsPublicUserProfile? = nil
    @State private var showLeaveGroupAlert: Bool = false
    @State private var showCannotLeaveAlert: Bool = false
    @State private var showEditTitleAlert: Bool = false
    @State private var editTitleText: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    
    // アバター変更 & メンバー追加シート状態
    @State private var showingAvatarActionSheet: Bool = false
    @State private var showingPhotoPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showingPresetSheet: Bool = false
    @State private var showAddMemberSheet: Bool = false
    
    /// リアルタイムに最新のチャット状態を取得（未検出時は初期プロパティへフォールバック）
    private var currentChat: FriendsChatUIModel {
        chatService.chats.first(where: { $0.chatID == chat.chatID }) ?? chat
    }
    
    /// 現在のログインユーザー
    private var currentUserId: String {
        chatService.currentUser?.userID ?? ""
    }
    
    /// 現在のユーザーがオーナーまたは管理者であるか
    private var isCurrentUserOwnerOrAdmin: Bool {
        guard !currentUserId.isEmpty else { return false }
        return currentChat.isOwnerOrAdmin(userId: currentUserId)
    }
    
    /// 現在のユーザーがオーナーであるか
    private var isCurrentUserOwner: Bool {
        guard !currentUserId.isEmpty else { return false }
        return currentChat.role(for: currentUserId) == .owner
    }
    
    /// 現在のユーザーが管理者であるか
    private var isCurrentUserAdmin: Bool {
        guard !currentUserId.isEmpty else { return false }
        return currentChat.role(for: currentUserId) == .admin
    }
    
    /// グループメンバー一覧
    var groupMembers: [FriendsPublicUserProfile] {
        var result: [FriendsPublicUserProfile] = []
        let memberIds = currentChat.chat.members
        
        // 自分自身
        if let current = chatService.currentUser, (memberIds.contains(current.userID) || memberIds.contains(current.uid)) {
            result.append(current)
        }
        
        // 登録されている友達
        for friend in chatService.friends {
            if (memberIds.contains(friend.userID) || memberIds.contains(friend.uid)) && !result.contains(where: { $0.userID == friend.userID }) {
                result.append(friend)
            }
        }
        
        return result
    }
    
    var body: some View {
        List {
            // Section 1: グループ概要 (アバター + グループ名)
            Section {
                HStack(spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        GroupAvatarView(
                            chatId: currentChat.chatID,
                            avatarNonce: currentChat.avatarNonce,
                            avatarUpdatedAt: currentChat.avatarUpdatedAt,
                            size: 64
                        )
                        
                        if isCurrentUserOwnerOrAdmin {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
                        }
                    }
                    .contentShape(Circle())
                    .onTapGesture {
                        if isCurrentUserOwnerOrAdmin {
                            showingAvatarActionSheet = true
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentChat.displayTitle)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(currentChat.chat.createdDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            
            // Section 2: 管理者用 オーナー引き継ぎアクション
            if isCurrentUserAdmin {
                Section {
                    Button {
                        showClaimOwnerAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 18))
                            Text(L10n.Group.claimOwner)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(isProcessing)
                }
            }
            
            // Section 3: 参加メンバー一覧（メンバー属性 role の表示と操作）
            Section(header: Text(L10n.Group.membersSection(currentChat.chat.members.count))) {
                if groupMembers.isEmpty {
                    Text("\(currentChat.chat.members.count) 人のメンバーが参加中")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(groupMembers) { member in
                        let role = currentChat.role(for: member.userID)
                        let isMe = (member.userID == currentUserId || member.uid == chatService.currentUser?.uid)
                        
                        HStack(spacing: 12) {
                            UserAvatarView(
                                userId: member.userID,
                                displayName: member.displayName,
                                avatarNonce: member.avatarNonce,
                                avatarUpdatedAt: member.avatarUpdatedDate,
                                size: 36
                            )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(member.displayName)
                                        .font(.body)
                                    
                                    if isMe {
                                        Text("(\(L10n.Reaction.you))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                // メンバー属性(role)バッジ表示 (名前の下に配置)
                                roleBadge(for: role)
                            }
                            
                            Spacer()
                            
                            // 行右端: 「…」メニュー（スワイプに気付かない人や誤操作防止の確実な操作メニュー）
                            if !isMe && ((isCurrentUserOwner && role == .member) || (isCurrentUserOwnerOrAdmin && role != .owner)) {
                                Menu {
                                    // オーナーのみ: 一般メンバーを管理者に任命
                                    if isCurrentUserOwner && role == .member {
                                        Button {
                                            targetAssignAdminMember = member
                                            showAssignAdminAlert = true
                                        } label: {
                                            Label(L10n.Group.assignAdmin, systemImage: "shield.fill")
                                        }
                                    }
                                    
                                    // 管理者・オーナー: かいぎから退出させる（破壊的操作・赤字）
                                    if isCurrentUserOwnerOrAdmin && role != .owner {
                                        Button(role: .destructive) {
                                            targetRemoveMember = member
                                            showRemoveMemberAlert = true
                                        } label: {
                                            Label(L10n.Group.removeMember, systemImage: "trash")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            // オーナーのみ: 一般メンバー行を右スワイプで管理者に任命
                            if isCurrentUserOwner && role == .member && !isMe {
                                Button {
                                    targetAssignAdminMember = member
                                    showAssignAdminAlert = true
                                } label: {
                                    Label(L10n.Group.assignAdmin, systemImage: "shield.fill")
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            // 長押しコンテキストメニュー
                            if isCurrentUserOwner && role == .member && !isMe {
                                Button {
                                    targetAssignAdminMember = member
                                    showAssignAdminAlert = true
                                } label: {
                                    Label(L10n.Group.assignAdmin, systemImage: "shield.fill")
                                }
                            }
                            if isCurrentUserOwnerOrAdmin && role != .owner && !isMe {
                                Button(role: .destructive) {
                                    targetRemoveMember = member
                                    showRemoveMemberAlert = true
                                } label: {
                                    Label(L10n.Group.removeMember, systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            
            // Section 4: 参加状態（退室）
            Section {
                Button(role: .destructive) {
                    if isCurrentUserOwner {
                        showCannotLeaveAlert = true
                    } else {
                        showLeaveGroupAlert = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(L10n.Group.leaveGroup)
                    }
                }
                .disabled(isProcessing)
            }
            
            // Section 5: かいぎ完全削除 (オーナーまたは管理者のみ表示・重要操作)
            if isCurrentUserOwnerOrAdmin {
                Section {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Image(systemName: "trash.fill")
                            Text(L10n.Group.deleteButton)
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .foregroundColor(.red)
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currentChat.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCurrentUserOwnerOrAdmin {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showAddMemberSheet = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel(L10n.Group.addMemberAction)
                    
                    Button {
                        editTitleText = currentChat.title
                        showEditTitleAlert = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel(L10n.Group.editTitle)
                }
            }
        }
        .modifier(GroupDetailSheetsModifier(
            currentChat: currentChat,
            showingAvatarActionSheet: $showingAvatarActionSheet,
            showingPhotoPicker: $showingPhotoPicker,
            selectedPhotoItem: $selectedPhotoItem,
            showingPresetSheet: $showingPresetSheet,
            showAddMemberSheet: $showAddMemberSheet,
            onUploadAvatar: { executeUploadAvatar($0) },
            onDeleteAvatar: { executeDeleteAvatar() }
        ))
        .modifier(GroupDetailAlertsModifier(
            currentChat: currentChat,
            showDeleteAlert: $showDeleteAlert,
            showLeaveGroupAlert: $showLeaveGroupAlert,
            showClaimOwnerAlert: $showClaimOwnerAlert,
            showAssignAdminAlert: $showAssignAdminAlert,
            targetAssignAdminMember: $targetAssignAdminMember,
            showRemoveMemberAlert: $showRemoveMemberAlert,
            targetRemoveMember: $targetRemoveMember,
            showCannotLeaveAlert: $showCannotLeaveAlert,
            showEditTitleAlert: $showEditTitleAlert,
            editTitleText: $editTitleText,
            onDeleteGroup: { executeDeleteGroup() },
            onLeaveGroup: { leaveGroup() },
            onClaimOwner: { executeClaimOwnership() },
            onAssignAdmin: { assignAdmin(to: $0) },
            onRemoveMember: { executeRemoveMember(targetUserId: $0) },
            onEditTitle: { executeEditTitle() }
        ))
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func roleBadge(for role: FriendsGroupMemberRole) -> some View {
        switch role {
        case .owner:
            HStack(spacing: 3) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                Text(L10n.Group.roleOwner)
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18))
            .foregroundColor(.orange)
            .clipShape(Capsule())
            
        case .admin:
            HStack(spacing: 3) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10))
                Text(L10n.Group.roleAdmin)
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.18))
            .foregroundColor(.blue)
            .clipShape(Capsule())
            
        case .member, .unspecified, .UNRECOGNIZED:
            EmptyView()
        }
    }
    
    // MARK: - Actions
    
    /// 確認を経たグループ削除の実行 (1回ダイアログ承認後)
    private func executeDeleteGroup() {
        isProcessing = true
        chatService.deleteGroup(chatId: currentChat.chatID) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success:
                    self.dismiss()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// 管理者によるオーナー立候補昇格の実行
    private func executeClaimOwnership() {
        isProcessing = true
        chatService.claimOwnership(chatId: currentChat.chatID) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// 管理者任命
    private func assignAdmin(to userId: String) {
        isProcessing = true
        chatService.assignAdmin(chatId: currentChat.chatID, targetUserId: userId) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                self.targetAssignAdminMember = nil
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// 他メンバーを退出させる
    private func executeRemoveMember(targetUserId: String) {
        isProcessing = true
        chatService.kickMember(chatId: currentChat.chatID, targetUserId: targetUserId) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                self.targetRemoveMember = nil
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// 自発的退出
    private func leaveGroup() {
        isProcessing = true
        chatService.kickMember(chatId: currentChat.chatID, targetUserId: currentUserId) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                switch result {
                case .success:
                    self.dismiss()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// かいぎ名の変更実行
    private func executeEditTitle() {
        let trimmed = editTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isProcessing = true
        chatService.updateGroupTitle(chatId: currentChat.chatID, newTitle: trimmed) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// グループアバターのアップロード実行
    private func executeUploadAvatar(_ image: UIImage) {
        isProcessing = true
        chatService.updateGroupAvatar(chatId: currentChat.chatID, image: image) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// グループアバターの削除実行
    private func executeDeleteAvatar() {
        isProcessing = true
        chatService.deleteGroupAvatar(chatId: currentChat.chatID) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
                if case .failure(let error) = result {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - GroupDetailSheetsModifier

private struct GroupDetailSheetsModifier: ViewModifier {
    let currentChat: FriendsChatUIModel
    @Binding var showingAvatarActionSheet: Bool
    @Binding var showingPhotoPicker: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var showingPresetSheet: Bool
    @Binding var showAddMemberSheet: Bool
    let onUploadAvatar: (UIImage) -> Void
    let onDeleteAvatar: () -> Void
    
    func body(content: Content) -> some View {
        content
            .confirmationDialog(L10n.Group.avatarChangeTitle, isPresented: $showingAvatarActionSheet, titleVisibility: .visible) {
                Button(L10n.Settings.avatarChoosePhoto) {
                    showingPhotoPicker = true
                }
                Button(L10n.Settings.avatarPresetTitle) {
                    showingPresetSheet = true
                }
                if currentChat.avatarUpdatedAt != nil {
                    Button(L10n.Settings.avatarRemove, role: .destructive) {
                        onDeleteAvatar()
                    }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            onUploadAvatar(uiImage)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPresetSheet) {
                PresetAvatarPickerSheet { presetImage in
                    onUploadAvatar(presetImage)
                }
            }
            .sheet(isPresented: $showAddMemberSheet) {
                AddGroupMemberSheet(chat: currentChat)
            }
    }
}

// MARK: - GroupDetailAlertsModifier

private struct GroupDetailAlertsModifier: ViewModifier {
    let currentChat: FriendsChatUIModel
    @Binding var showDeleteAlert: Bool
    @Binding var showLeaveGroupAlert: Bool
    @Binding var showClaimOwnerAlert: Bool
    @Binding var showAssignAdminAlert: Bool
    @Binding var targetAssignAdminMember: FriendsPublicUserProfile?
    @Binding var showRemoveMemberAlert: Bool
    @Binding var targetRemoveMember: FriendsPublicUserProfile?
    @Binding var showCannotLeaveAlert: Bool
    @Binding var showEditTitleAlert: Bool
    @Binding var editTitleText: String
    
    let onDeleteGroup: () -> Void
    let onLeaveGroup: () -> Void
    let onClaimOwner: () -> Void
    let onAssignAdmin: (String) -> Void
    let onRemoveMember: (String) -> Void
    let onEditTitle: () -> Void
    
    func body(content: Content) -> some View {
        content
            .alert(
                L10n.Group.deleteConfirmTitle(currentChat.displayTitle),
                isPresented: $showDeleteAlert
            ) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Group.deleteConfirmAction, role: .destructive) {
                    onDeleteGroup()
                }
            } message: {
                Text(L10n.Group.deleteConfirmMessage)
            }
            .alert(
                L10n.Group.leaveGroup,
                isPresented: $showLeaveGroupAlert
            ) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Group.leaveGroup, role: .destructive) {
                    onLeaveGroup()
                }
            } message: {
                Text(L10n.Group.leaveGroupConfirm)
            }
            .alert(
                L10n.Group.claimOwner,
                isPresented: $showClaimOwnerAlert
            ) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.ok) {
                    onClaimOwner()
                }
            } message: {
                Text(L10n.Group.claimOwnerConfirm)
            }
            .alert(
                L10n.Group.assignAdmin,
                isPresented: $showAssignAdminAlert
            ) {
                Button(L10n.Common.cancel, role: .cancel) {
                    targetAssignAdminMember = nil
                }
                Button(L10n.Group.assignAdmin) {
                    if let target = targetAssignAdminMember {
                        onAssignAdmin(target.userID)
                    }
                }
            } message: {
                Text(L10n.Group.assignAdminConfirm(targetAssignAdminMember?.displayName ?? ""))
            }
            .alert(
                L10n.Group.removeMember,
                isPresented: $showRemoveMemberAlert
            ) {
                Button(L10n.Common.cancel, role: .cancel) {
                    targetRemoveMember = nil
                }
                Button(L10n.Group.removeMember, role: .destructive) {
                    if let target = targetRemoveMember {
                        onRemoveMember(target.userID)
                    }
                }
            } message: {
                Text(L10n.Group.removeMemberConfirm(targetRemoveMember?.displayName ?? ""))
            }
            .alert(
                L10n.Group.leaveGroup,
                isPresented: $showCannotLeaveAlert
            ) {
                Button(L10n.Common.ok, role: .cancel) {}
            } message: {
                Text(L10n.Group.cannotLeaveOwner)
            }
            .alert(
                L10n.Group.editTitle,
                isPresented: $showEditTitleAlert
            ) {
                TextField(L10n.Group.namePlaceholder, text: $editTitleText)
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.save) {
                    onEditTitle()
                }
            } message: {
                Text(L10n.Group.editTitlePrompt)
            }
    }
}

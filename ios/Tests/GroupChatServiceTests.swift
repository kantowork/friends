import XCTest
import SwiftProtobuf
@testable import Friends

@MainActor
final class GroupChatServiceTests: XCTestCase {
    
    func testGroupChatIdPrefix() {
        let groupId = "gm_01J6XYZ1234567890ABCDEF"
        XCTAssertTrue(groupId.hasPrefix("gm_"), "グループチャットIDは不変プレフィックス規約により gm_ で始まる必要があります")
    }
    
    func testGroupChatUIModelProperties() {
        let now = Date()
        let pbChat = FriendsChat(
            chatID: "gm_test_group",
            tenantID: "t_test",
            chatType: .group,
            members: ["uid_1", "uid_2", "uid_3"],
            createdAt: now,
            updatedAt: now
        )
        
        let uiModel = FriendsChatUIModel(
            chat: pbChat,
            title: "開発チーム会",
            lastMessage: "テストメッセージ",
            lastMessageAt: now,
            unreadCount: 3
        )
        
        XCTAssertEqual(uiModel.displayTitle, "開発チーム会")
        XCTAssertEqual(uiModel.chatType, .group)
        XCTAssertEqual(uiModel.unreadCount, 3)
        XCTAssertEqual(uiModel.chat.members.count, 3)
        
        // タイトル空時のデフォルト表示名（かいぎ）
        let emptyTitleChat = FriendsChatUIModel(chat: pbChat, title: "")
        XCTAssertEqual(emptyTitleChat.displayTitle, "かいぎ")
    }
    
    func testL10nGroupLocalizationKeys() {
        XCTAssertFalse(L10n.Tab.groups.isEmpty, "Tab.groups がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.listTitle.isEmpty, "Group.listTitle がローカライズされている必要があります")
        XCTAssertEqual(L10n.Group.listTitle, "かいぎ")
        XCTAssertFalse(L10n.Group.createTitle.isEmpty, "Group.createTitle がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.selectMembers(2).isEmpty, "Group.selectMembers がフォーマット可能である必要があります")
        XCTAssertFalse(L10n.Group.roleOwner.isEmpty, "Group.roleOwner がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.roleAdmin.isEmpty, "Group.roleAdmin がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.claimOwner.isEmpty, "Group.claimOwner がローカライズされている必要があります")
        XCTAssertEqual(L10n.Group.claimOwner, "オーナーを引き継ぐ")
        XCTAssertFalse(L10n.Group.claimOwnerConfirm.isEmpty, "Group.claimOwnerConfirm がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.assignAdmin.isEmpty, "Group.assignAdmin がローカライズされている必要があります")
        XCTAssertEqual(L10n.Group.assignAdmin, "管理者にする")
        XCTAssertFalse(L10n.Group.assignAdminConfirm("テスト太郎").isEmpty, "Group.assignAdminConfirm がフォーマット可能である必要があります")
        XCTAssertFalse(L10n.Group.removeMember.isEmpty, "Group.removeMember がローカライズされている必要があります")
        XCTAssertEqual(L10n.Group.removeMember, "退出させる")
        XCTAssertFalse(L10n.Group.leaveGroup.isEmpty, "Group.leaveGroup がローカライズされている必要があります")
        XCTAssertEqual(L10n.Group.leaveGroup, "退室する")
        XCTAssertEqual(L10n.Group.deleteButton, "かいぎを完全に削除")
        XCTAssertFalse(L10n.Group.editTitle.isEmpty, "Group.editTitle がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.editTitlePrompt.isEmpty, "Group.editTitlePrompt がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.deleteButton.isEmpty, "Group.deleteButton がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.deleteConfirmTitle("テスト会").isEmpty, "deleteConfirmTitle がフォーマット可能である必要があります")
        XCTAssertFalse(L10n.Group.deleteConfirmMessage.isEmpty, "deleteConfirmMessage がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.deleteConfirmAction.isEmpty, "deleteConfirmAction がローカライズされている必要があります")
    }
    
    func testGroupMemberRolesAndPermissions() {
        let now = Date()
        let roles: [String: FriendsGroupMemberRole] = [
            "u_owner": .owner,
            "u_admin": .admin,
            "u_member": .member
        ]
        
        let pbChat = FriendsChat(
            chatID: "gm_test_role_chat",
            tenantID: "t_test",
            chatType: .group,
            members: ["u_owner", "u_admin", "u_member"],
            title: "権限テストグループ",
            createdBy: "u_owner",
            createdAt: now,
            updatedBy: "u_owner",
            updatedAt: now,
            memberRoles: roles,
            isDeleted: false
        )
        
        let uiModel = FriendsChatUIModel(chat: pbChat, title: "権限テストグループ")
        
        // ロール判定
        XCTAssertEqual(uiModel.role(for: "u_owner"), .owner)
        XCTAssertEqual(uiModel.role(for: "u_admin"), .admin)
        XCTAssertEqual(uiModel.role(for: "u_member"), .member)
        XCTAssertEqual(uiModel.role(for: "u_unknown"), .member, "未設定メンバーはmemberへフォールバック")
        
        // オーナー・管理者判定（他人を退出させる権限・かいぎ削除権限・かいぎ名変更権限）
        XCTAssertTrue(uiModel.isOwnerOrAdmin(userId: "u_owner"), "オーナーは他人を退出させる権限を持つ")
        XCTAssertTrue(uiModel.isOwnerOrAdmin(userId: "u_admin"), "管理者は他人を退出させる権限を持つ")
        XCTAssertFalse(uiModel.isOwnerOrAdmin(userId: "u_member"), "一般メンバーは他人を退出させる権限を持たない")
        XCTAssertFalse(uiModel.isOwnerOrAdmin(userId: "u_unknown"))
        
        // オーナーID取得
        XCTAssertEqual(uiModel.ownerUserId, "u_owner")
    }
    
    func testGroupTitleUpdate() {
        let now = Date()
        var pbChat = FriendsChat(
            chatID: "gm_title_test",
            tenantID: "t_test",
            chatType: .group,
            members: ["u_owner", "u_admin"],
            title: "旧グループ名",
            createdBy: "u_owner",
            createdAt: now,
            updatedBy: "u_owner",
            updatedAt: now,
            memberRoles: ["u_owner": .owner, "u_admin": .admin]
        )
        
        let initialModel = FriendsChatUIModel(chat: pbChat, title: "旧グループ名")
        XCTAssertEqual(initialModel.displayTitle, "旧グループ名")
        
        // 管理者権限チェック (オーナーまたは管理者が更新可能)
        XCTAssertTrue(initialModel.isOwnerOrAdmin(userId: "u_admin"))
        
        // タイトル変更反映
        pbChat.title = "新グループ名"
        let updatedModel = FriendsChatUIModel(
            chat: pbChat,
            title: "新グループ名",
            lastMessage: initialModel.lastMessage,
            lastMessageAt: initialModel.lastMessageAt,
            unreadCount: initialModel.unreadCount
        )
        
        XCTAssertEqual(updatedModel.displayTitle, "新グループ名")
        XCTAssertEqual(updatedModel.title, "新グループ名")
    }
    
    func testGroupMemberProfileResolution() {
        let groupChatService = GroupChatService.shared
        
        // 友達未登録のグループメンバープロファイル登録
        var groupMember = FriendsPublicUserProfile()
        groupMember.userID = "u_group_member_99"
        groupMember.uid = "firebase_uid_99"
        groupMember.tenantID = "t_test"
        groupMember.displayName = "未登録メンバー太郎"
        groupMember.publicKey = "pub_key_99"
        groupMember.role = .member
        groupMember.accountType = .persistent
        groupMember.avatarNonce = "nonce_99"
        groupMember.avatarUpdatedAt = Google_Protobuf_Timestamp(date: Date())
        groupMember.username = "group_member_99"
        
        groupChatService.groupMemberProfiles["u_group_member_99"] = groupMember
        
        // UserProfileResolver での解決確認
        let resolved = UserProfileResolver.resolve(userId: "u_group_member_99")
        XCTAssertNotNil(resolved, "グループメンバープロファイルが解決できる必要があります")
        XCTAssertEqual(resolved?.displayName, "未登録メンバー太郎")
        XCTAssertEqual(resolved?.avatarNonce, "nonce_99")
        
        // 存在しない userId
        let resolvedUnknown = UserProfileResolver.resolve(userId: "u_unknown")
        XCTAssertNil(resolvedUnknown, "存在しないユーザーIDはnilである必要があります")
    }
    
    func testGroupChatPaginationProperties() {
        let messageService = MessageService.shared
        let testChatId = "gm_pagination_test"
        
        // 初期状態
        messageService.hasMoreMessages[testChatId] = true
        XCTAssertTrue(messageService.hasMoreMessages[testChatId] == true)
        
        // 全件取得後
        messageService.hasMoreMessages[testChatId] = false
        XCTAssertFalse(messageService.hasMoreMessages[testChatId] == true)
    }
    
    func testGroupAvatarModelProperties() {
        let now = Date()
        let pbChat = FriendsChat(
            chatID: "gm_avatar_test",
            tenantID: "t_test",
            chatType: .group,
            members: ["u_1", "u_2"],
            createdAt: now,
            updatedAt: now
        )
        
        let uiModel = FriendsChatUIModel(
            chat: pbChat,
            title: "アバターテスト会",
            avatarNonce: "nonce_abc123",
            avatarUpdatedAt: now
        )
        
        XCTAssertEqual(uiModel.avatarNonce, "nonce_abc123")
        XCTAssertEqual(uiModel.avatarUpdatedAt, now)
    }
    
    func testNewGroupLocalizationKeys() {
        XCTAssertFalse(L10n.Group.addMemberAction.isEmpty)
        XCTAssertFalse(L10n.Group.addMemberTitle.isEmpty)
        XCTAssertFalse(L10n.Group.addMemberSubmitBtn.isEmpty)
        XCTAssertFalse(L10n.Group.addMemberNoCandidates.isEmpty)
        XCTAssertFalse(L10n.Group.avatarChangeTitle.isEmpty)
        XCTAssertFalse(L10n.Group.addMemberSelectCount(3).isEmpty)
    }
}



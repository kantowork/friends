import XCTest
@testable import Friends

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
    }
    
    func testL10nGroupLocalizationKeys() {
        XCTAssertFalse(L10n.Tab.groups.isEmpty, "Tab.groups がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.listTitle.isEmpty, "Group.listTitle がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.createTitle.isEmpty, "Group.createTitle がローカライズされている必要があります")
        XCTAssertFalse(L10n.Group.selectMembers(2).isEmpty, "Group.selectMembers がフォーマット可能である必要があります")
    }
}

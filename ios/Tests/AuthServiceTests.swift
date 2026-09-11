import XCTest
@testable import Friends

@MainActor
final class AuthServiceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        AuthService.shared.clear()
        DirectChatService.shared.clear()
        GroupChatService.shared.clear()
        MessageService.shared.clear()
    }
    
    override func tearDown() {
        AuthService.shared.clear()
        DirectChatService.shared.clear()
        GroupChatService.shared.clear()
        MessageService.shared.clear()
        super.tearDown()
    }
    
    func testAuthServiceClearCascadesToAllChatServices() {
        // 各サービスに状態を注入
        var friend = FriendsPublicUserProfile()
        friend.userID = "u_friend_01"
        DirectChatService.shared.friends = [friend]
        
        var groupChat = FriendsChatUIModel(
            chat: FriendsChat(
                chatID: "gm_test_01",
                tenantID: "t_test",
                chatType: .group,
                members: ["u_test"]
            ),
            title: "テスト会"
        )
        GroupChatService.shared.groupChats = [groupChat]
        
        MessageService.shared.activeChatId = "gm_test_01"
        
        XCTAssertFalse(DirectChatService.shared.friends.isEmpty)
        XCTAssertFalse(GroupChatService.shared.groupChats.isEmpty)
        XCTAssertEqual(MessageService.shared.activeChatId, "gm_test_01")
        
        // AuthService の clear を実行
        AuthService.shared.clear()
        
        // すべてクリアされることを検証
        XCTAssertTrue(DirectChatService.shared.friends.isEmpty, "AuthService.clear() により DirectChatService もクリアされる必要があります")
        XCTAssertTrue(GroupChatService.shared.groupChats.isEmpty, "AuthService.clear() により GroupChatService もクリアされる必要があります")
        XCTAssertNil(MessageService.shared.activeChatId, "AuthService.clear() により MessageService もクリアされる必要があります")
    }
    
    func testUserProfileResolverPriority() {
        // 1. 自分自身 (AuthService.currentUser) の解決
        var me = FriendsPublicUserProfile()
        me.userID = "u_myself"
        me.displayName = "わたし"
        AuthService.shared.currentUser = me
        
        let resolvedMe = UserProfileResolver.resolve(userId: "u_myself")
        XCTAssertNotNil(resolvedMe)
        XCTAssertEqual(resolvedMe?.displayName, "わたし")
        
        // 2. 友達 (DirectChatService.friends) の解決
        var friend = FriendsPublicUserProfile()
        friend.userID = "u_friend_bob"
        friend.displayName = "ボブ"
        DirectChatService.shared.friends = [friend]
        
        let resolvedFriend = UserProfileResolver.resolve(userId: "u_friend_bob")
        XCTAssertNotNil(resolvedFriend)
        XCTAssertEqual(resolvedFriend?.displayName, "ボブ")
        
        // 3. グループメンバー (GroupChatService.groupMemberProfiles) の解決
        var member = FriendsPublicUserProfile()
        member.userID = "u_member_charlie"
        member.displayName = "チャーリー"
        GroupChatService.shared.groupMemberProfiles["u_member_charlie"] = member
        
        let resolvedMember = UserProfileResolver.resolve(userId: "u_member_charlie")
        XCTAssertNotNil(resolvedMember)
        XCTAssertEqual(resolvedMember?.displayName, "チャーリー")
        
        // 4. 未知のユーザー
        let resolvedUnknown = UserProfileResolver.resolve(userId: "u_unknown_ghost")
        XCTAssertNil(resolvedUnknown)
    }
}

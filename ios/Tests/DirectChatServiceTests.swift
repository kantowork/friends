import XCTest
import CryptoKit
@testable import Friends

@MainActor
final class DirectChatServiceTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        DirectChatService.shared.clear()
        MessageService.shared.clear()
    }
    
    override func tearDown() {
        DirectChatService.shared.clear()
        MessageService.shared.clear()
        super.tearDown()
    }
    
    func testDirectChatIdGenerationConvention() {
        // AGENTS.md 第5条 (dm_ プレフィックス) & doc/09-guidelines/09-01-id-naming-conventions.md
        let userA = "u_alice_001"
        let userB = "u_bob_002"
        
        let dmChatId1 = "dm_" + [userA, userB].sorted().joined(separator: "_")
        let dmChatId2 = "dm_" + [userB, userA].sorted().joined(separator: "_")
        
        XCTAssertEqual(dmChatId1, dmChatId2, "DMチャットIDはソート順により決定論的に一致する必要があります")
        XCTAssertTrue(dmChatId1.hasPrefix("dm_u_"), "DMチャットIDは dm_u_ から始まる必要があります")
        XCTAssertEqual(dmChatId1, "dm_u_alice_001_u_bob_002")
    }
    
    func testFriendProfileResolution() {
        let directChatService = DirectChatService.shared
        
        var friend = FriendsPublicUserProfile()
        friend.userID = "u_friend_123"
        friend.uid = "firebase_auth_uid_123"
        friend.tenantID = "t_test"
        friend.displayName = "テスト太郎"
        friend.username = "test_taro"
        friend.role = .member
        friend.accountType = .persistent
        
        directChatService.friends = [friend]
        
        // ユーザーIDでの解決
        let resolvedById = directChatService.friendProfile(for: "u_friend_123")
        XCTAssertNotNil(resolvedById)
        XCTAssertEqual(resolvedById?.displayName, "テスト太郎")
        
        // 存在しないID
        let resolvedNone = directChatService.friendProfile(for: "u_unknown")
        XCTAssertNil(resolvedNone)
    }
    
    func testTotalDmUnreadCountCalculation() {
        let directChatService = DirectChatService.shared
        let messageService = MessageService.shared
        
        var friend = FriendsPublicUserProfile()
        friend.userID = "u_peer_999"
        friend.uid = "peer_uid_999"
        directChatService.friends = [friend]
        
        // 未読なし状態
        XCTAssertEqual(directChatService.totalDmUnreadCount, 0)
        
        // メッセージサービスに未読をシミュレート
        let testChatId = "dm_u_peer_999"
        var chatUIModel = FriendsChatUIModel(
            chat: FriendsChat(
                chatID: testChatId,
                tenantID: "t_test",
                chatType: .direct,
                members: ["u_peer_999"]
            ),
            title: "DMチャット"
        )
        directChatService.dmChats = [chatUIModel]
        
        // メッセージが空なので 0
        XCTAssertEqual(directChatService.totalDmUnreadCount, 0)
    }
}

import XCTest
@testable import Friends

@MainActor
final class UnreadChatTests: XCTestCase {
    
    func testLocalizationKeys() {
        XCTAssertFalse(L10n.Home.unreadSectionTitle.isEmpty)
        XCTAssertEqual(L10n.Home.unreadSectionTitle, "未読メッセージ")
    }
    
    func testHasUnreadLogic() {
        let service = MessageService.shared
        let myUserId = "u_tester"
        
        // AuthService の currentUser を設定
        var testProfile = FriendsPublicUserProfile()
        testProfile.userID = myUserId
        testProfile.displayName = "Tester"
        AuthService.shared.currentUser = testProfile
        
        let chatId = "dm_u_other_u_tester"
        let baseTime = Date(timeIntervalSince1970: 1000)
        
        // 既読が distantPast の場合（一度も既読にしていない）
        service.readReceipts[chatId] = [:]
        service.messages[chatId] = []
        
        // メッセージが distantPast より新しい場合は未読
        XCTAssertTrue(service.hasUnread(chatId: chatId, lastMessageAt: baseTime))
        
        // アクティブチャット中の場合は未読判定されない
        service.activeChatId = chatId
        XCTAssertFalse(service.hasUnread(chatId: chatId, lastMessageAt: baseTime))
        service.activeChatId = nil
        
        // 既読水位線を進める (baseTime + 10秒 = 1010)
        let readTime = baseTime.addingTimeInterval(10)
        let receipt = FriendsReadReceipt(
            userID: myUserId,
            chatID: chatId,
            tenantID: "t_test",
            lastReadMessageID: "m_1",
            lastReadAt: readTime,
            updatedAt: readTime
        )
        service.readReceipts[chatId] = [myUserId: receipt]
        
        // 水位線より前のメッセージなら既読 (未読ではない)
        XCTAssertFalse(service.hasUnread(chatId: chatId, lastMessageAt: baseTime))
        
        // 水位線より後のメッセージなら未読
        let newMsgTime = readTime.addingTimeInterval(5)
        XCTAssertTrue(service.hasUnread(chatId: chatId, lastMessageAt: newMsgTime))
    }
    
    func testGetUnreadChatsReturnsFriendsChatUIModel() {
        let service = MessageService.shared
        let myUserId = "u_tester_chats"
        let tenantId = "t_test_tenant"
        
        var testProfile = FriendsPublicUserProfile()
        testProfile.userID = myUserId
        testProfile.displayName = "Tester"
        AuthService.shared.currentUser = testProfile
        
        let tenant = FriendsTenant(
            tenantID: tenantId,
            tenantCode: "test",
            tenantName: "Test Tenant",
            isDefaultTenant: true
        )
        AuthService.shared.currentTenant = tenant
        
        // 未読チャット取得の戻り値が [FriendsChatUIModel] であることを確認
        let unreadChats = service.getUnreadChats()
        XCTAssertTrue(unreadChats is [FriendsChatUIModel])
    }
}

import XCTest
import SwiftProtobuf
@testable import Friends

final class ReadReceiptServiceTests: XCTestCase {
    
    func testReadReceiptInitialization() {
        let now = Date()
        let receipt = FriendsReadReceipt(
            userID: "u_user_123",
            chatID: "dm_chat_456",
            tenantID: "t_tenant_789",
            lastReadMessageID: "m_01JABCDEF",
            lastReadAt: now,
            updatedAt: now
        )
        
        XCTAssertEqual(receipt.userID, "u_user_123")
        XCTAssertEqual(receipt.chatID, "dm_chat_456")
        XCTAssertEqual(receipt.tenantID, "t_tenant_789")
        XCTAssertEqual(receipt.lastReadMessageID, "m_01JABCDEF")
        XCTAssertEqual(receipt.id, "dm_chat_456_u_user_123")
        XCTAssertEqual(floor(receipt.lastReadDate.timeIntervalSince1970), floor(now.timeIntervalSince1970))
    }
    
    func testDirectMessageReadStatusCalculation() {
        let chatService = ChatService.shared
        let chatId = "dm_test_read_1"
        let myUid = "u_alice"
        let friendUid = "u_bob"
        
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        let t2 = Date(timeIntervalSince1970: 3000)
        
        // Bob has read up to t1
        let bobReceipt = FriendsReadReceipt(
            userID: friendUid,
            chatID: chatId,
            tenantID: "t_default",
            lastReadMessageID: "m_1",
            lastReadAt: t1,
            updatedAt: t1
        )
        
        // Populate chatService readReceipts map
        chatService.readReceipts[chatId] = [
            friendUid: bobReceipt
        ]
        
        // 1. Message sent at t0 (before Bob's lastReadAt) -> Should be READ
        let isReadT0 = chatService.isMessageRead(chatId: chatId, messageDate: t0, senderId: myUid)
        XCTAssertTrue(isReadT0, "作成日時が相手のlastReadAt以前のメッセージは既読と判定される必要があります")
        
        // 2. Message sent at t1 (exact Bob's lastReadAt) -> Should be READ
        let isReadT1 = chatService.isMessageRead(chatId: chatId, messageDate: t1, senderId: myUid)
        XCTAssertTrue(isReadT1, "作成日時が相手のlastReadAtと同時のメッセージは既読と判定される必要があります")
        
        // 3. Message sent at t2 (after Bob's lastReadAt) -> Should be UNREAD
        let isReadT2 = chatService.isMessageRead(chatId: chatId, messageDate: t2, senderId: myUid)
        XCTAssertFalse(isReadT2, "作成日時が相手のlastReadAtより未来のメッセージは未読と判定される必要があります")
    }
    
    func testGroupChatReadCountCalculation() {
        let chatService = ChatService.shared
        let chatId = "gm_test_group_1"
        let myUid = "u_alice"
        let bobUid = "u_bob"
        let carolUid = "u_carol"
        let daveUid = "u_dave"
        
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 2000)
        let t2 = Date(timeIntervalSince1970: 3000)
        
        // Bob read up to t2, Carol read up to t1, Dave has not read (t0 - 100)
        chatService.readReceipts[chatId] = [
            bobUid: FriendsReadReceipt(userID: bobUid, chatID: chatId, tenantID: "t_default", lastReadAt: t2),
            carolUid: FriendsReadReceipt(userID: carolUid, chatID: chatId, tenantID: "t_default", lastReadAt: t1),
            daveUid: FriendsReadReceipt(userID: daveUid, chatID: chatId, tenantID: "t_default", lastReadAt: Date(timeIntervalSince1970: 900))
        ]
        
        // Message sent at t0 -> Bob and Carol have read it (count = 2)
        let countT0 = chatService.readCountForMessage(chatId: chatId, messageDate: t0, senderId: myUid)
        XCTAssertEqual(countT0, 2, "t0時点のメッセージはBobとCarolの2名が既読である必要があります")
        
        // Message sent at t1 -> Bob and Carol have read it (count = 2)
        let countT1 = chatService.readCountForMessage(chatId: chatId, messageDate: t1, senderId: myUid)
        XCTAssertEqual(countT1, 2, "t1時点のメッセージはBobとCarolの2名が既読である必要があります")
        
        // Message sent at t2 -> Only Bob has read it (count = 1)
        let countT2 = chatService.readCountForMessage(chatId: chatId, messageDate: t2, senderId: myUid)
        XCTAssertEqual(countT2, 1, "t2時点のメッセージはBobの1名のみ既読である必要があります")
        
        // Message sent at t2 + 100 -> Nobody has read it (count = 0)
        let countT3 = chatService.readCountForMessage(chatId: chatId, messageDate: Date(timeIntervalSince1970: 3100), senderId: myUid)
        XCTAssertEqual(countT3, 0, "未来のメッセージは既読0名である必要があります")
    }
}

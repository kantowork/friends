import XCTest
@testable import Friends

final class MessageServiceTests: XCTestCase {
    
    func testSendStatusValues() {
        let msg = FriendsMessage(
            messageID: "m_test123",
            tenantID: "t_test",
            chatID: "dm_u_1_u_2",
            senderID: "u_1",
            keyVersion: "v_1",
            ciphertext: "enc",
            nonce: "nonce",
            messageType: .text,
            createdAt: Date()
        )
        
        var decrypted = DecryptedMessage(
            message: msg,
            senderName: "User",
            plainText: "Hello",
            decryptedText: "Hello",
            sendStatus: .sending
        )
        
        XCTAssertEqual(decrypted.sendStatus, .sending)
        
        decrypted.sendStatus = .sent
        XCTAssertEqual(decrypted.sendStatus, .sent)
        
        decrypted.sendStatus = .failed
        XCTAssertEqual(decrypted.sendStatus, .failed)
    }
    
    func testLocalizationKeys() {
        XCTAssertFalse(L10n.Chat.resend.isEmpty)
        XCTAssertFalse(L10n.Chat.sendFailed.isEmpty)
        XCTAssertFalse(L10n.Chat.sending.isEmpty)
    }
    
    func testPendingMessagesFiltering() {
        let chatID = "dm_u_1_u_2"
        let msg1 = FriendsMessage(
            messageID: "m_1",
            tenantID: "t_test",
            chatID: chatID,
            senderID: "u_1",
            keyVersion: "v_1",
            ciphertext: "enc1",
            nonce: "nonce1",
            messageType: .text,
            createdAt: Date()
        )
        let msg2 = FriendsMessage(
            messageID: "m_2",
            tenantID: "t_test",
            chatID: chatID,
            senderID: "u_1",
            keyVersion: "v_1",
            ciphertext: "enc2",
            nonce: "nonce2",
            messageType: .text,
            createdAt: Date()
        )
        
        let localSent = DecryptedMessage(message: msg1, sendStatus: .sent)
        let localFailed = DecryptedMessage(message: msg2, sendStatus: .failed)
        
        let localList = [localSent, localFailed]
        let serverMessageIds: Set<String> = ["m_1"]
        
        let pending = localList.filter { $0.sendStatus != .sent && !serverMessageIds.contains($0.id) }
        
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.id, "m_2")
        XCTAssertEqual(pending.first?.sendStatus, .failed)
    }
}

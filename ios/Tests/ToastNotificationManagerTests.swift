import XCTest
@testable import Friends

@MainActor
final class ToastNotificationManagerTests: XCTestCase {
    
    var manager: ToastNotificationManager!
    
    override func setUp() async throws {
        manager = ToastNotificationManager()
    }
    
    override func tearDown() async throws {
        manager.dismiss()
        manager = nil
    }
    func testShowToast() {
        let now = Date()
        manager.show(
            chatId: "c_chat123",
            senderId: "u_sender456",
            senderName: "Alice",
            messageText: "Hello world!",
            messageId: "m_msg001",
            isGroup: true,
            avatarNonce: "nonce_123",
            avatarUpdatedAt: now,
            duration: 5.0
        )
        
        XCTAssertNotNil(manager.currentToast)
        XCTAssertEqual(manager.currentToast?.chatId, "c_chat123")
        XCTAssertEqual(manager.currentToast?.senderId, "u_sender456")
        XCTAssertEqual(manager.currentToast?.senderName, "Alice")
        XCTAssertEqual(manager.currentToast?.messageText, "Hello world!")
        XCTAssertEqual(manager.currentToast?.isGroup, true)
        XCTAssertEqual(manager.currentToast?.avatarNonce, "nonce_123")
        XCTAssertEqual(manager.currentToast?.avatarUpdatedAt, now)
    }
    
    func testDuplicateMessageIdSuppression() {
        manager.show(
            chatId: "c_chat123",
            senderId: "u_sender456",
            senderName: "Alice",
            messageText: "First",
            messageId: "m_dup_123"
        )
        
        let firstToast = manager.currentToast
        XCTAssertNotNil(firstToast)
        XCTAssertEqual(firstToast?.messageText, "First")
        
        // 同じ messageId のメッセージを再度送信しても無視される
        manager.show(
            chatId: "c_chat123",
            senderId: "u_sender456",
            senderName: "Alice",
            messageText: "Second",
            messageId: "m_dup_123"
        )
        
        XCTAssertEqual(manager.currentToast?.messageText, "First")
    }
    
    func testDismissToast() {
        manager.show(
            chatId: "c_chat123",
            senderId: "u_sender456",
            senderName: "Alice",
            messageText: "Dismiss me"
        )
        XCTAssertNotNil(manager.currentToast)
        
        manager.dismiss()
        XCTAssertNil(manager.currentToast)
    }
    
    func testHandleToastTap() {
        let toast = InAppToast(
            chatId: "c_chat789",
            senderId: "u_bob",
            senderName: "Bob",
            messageText: "Meeting at 3pm"
        )
        
        manager.handleToastTap(toast)
        
        XCTAssertNil(manager.currentToast)
        XCTAssertNotNil(manager.navigationTargetChat)
        XCTAssertEqual(manager.navigationTargetChat?.chatID, "c_chat789")
        XCTAssertEqual(manager.navigationTargetChat?.title, "Bob")
    }
}

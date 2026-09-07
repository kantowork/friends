import XCTest
@testable import Friends

final class SafetyAndModerationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        BlockManager.shared.configure(tenantId: "t_test_moderation")
        BlockManager.shared.clear()
    }
    
    override func tearDown() {
        BlockManager.shared.clear()
        super.tearDown()
    }
    
    // MARK: - BlockManager Tests
    
    func testBlockAndUnblockUser() {
        let testUserId = "u_01J6TESTUSER000000000001"
        
        XCTAssertFalse(BlockManager.shared.isBlocked(userId: testUserId))
        
        // ブロック実行
        BlockManager.shared.block(userId: testUserId)
        XCTAssertTrue(BlockManager.shared.isBlocked(userId: testUserId))
        XCTAssertTrue(BlockManager.shared.blockedUserIds.contains(testUserId))
        
        // ブロック解除
        BlockManager.shared.unblock(userId: testUserId)
        XCTAssertFalse(BlockManager.shared.isBlocked(userId: testUserId))
        XCTAssertFalse(BlockManager.shared.blockedUserIds.contains(testUserId))
    }
    
    func testClearBlockedUsers() {
        let user1 = "u_01J6TESTUSER000000000001"
        let user2 = "u_01J6TESTUSER000000000002"
        
        BlockManager.shared.block(userId: user1)
        BlockManager.shared.block(userId: user2)
        XCTAssertEqual(BlockManager.shared.blockedUserIds.count, 2)
        
        BlockManager.shared.clear()
        XCTAssertEqual(BlockManager.shared.blockedUserIds.count, 0)
        XCTAssertFalse(BlockManager.shared.isBlocked(userId: user1))
        XCTAssertFalse(BlockManager.shared.isBlocked(userId: user2))
    }
    
    // MARK: - Localization Keys Tests
    
    func testSafetyLocalizationKeys() {
        // Block keys
        XCTAssertFalse(L10n.Block.action.isEmpty)
        XCTAssertFalse(L10n.Block.confirmTitle("Alice").isEmpty)
        XCTAssertTrue(L10n.Block.confirmTitle("Alice").contains("Alice"))
        XCTAssertFalse(L10n.Block.confirmMsg.isEmpty)
        XCTAssertFalse(L10n.Block.execute.isEmpty)
        XCTAssertFalse(L10n.Block.unblockAction.isEmpty)
        XCTAssertFalse(L10n.Block.unblockConfirmTitle("Bob").isEmpty)
        XCTAssertTrue(L10n.Block.unblockConfirmTitle("Bob").contains("Bob"))
        XCTAssertFalse(L10n.Block.unblockConfirmMsg.isEmpty)
        XCTAssertFalse(L10n.Block.unblockExecute.isEmpty)
        XCTAssertFalse(L10n.Block.listTitle.isEmpty)
        XCTAssertFalse(L10n.Block.listEmpty.isEmpty)
        XCTAssertFalse(L10n.Block.blockedBanner.isEmpty)
        
        // Legal keys
        XCTAssertFalse(L10n.Legal.termsTitle.isEmpty)
        XCTAssertFalse(L10n.Legal.privacyTitle.isEmpty)
        XCTAssertFalse(L10n.Legal.termsAgreeNotice.isEmpty)
        
        // Account Deletion keys
        XCTAssertFalse(L10n.Settings.accountDelete.isEmpty)
        XCTAssertFalse(L10n.Settings.accountDeleteConfirmTitle.isEmpty)
        XCTAssertFalse(L10n.Settings.accountDeleteConfirmMsg.isEmpty)
        XCTAssertFalse(L10n.Settings.accountDeleteExecute.isEmpty)
        XCTAssertFalse(L10n.Settings.accountDeleteSuccess.isEmpty)
        XCTAssertFalse(L10n.Settings.sectionSafety.isEmpty)
        XCTAssertFalse(L10n.Settings.sectionLegal.isEmpty)
        
        // App Info keys
        XCTAssertFalse(L10n.AppInfo.encryptionDetail1.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryptionDetail2.isEmpty)
    }
}

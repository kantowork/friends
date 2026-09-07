import XCTest
@testable import Friends

final class AuthValidationTests: XCTestCase {
    
    // MARK: - Account Type & User ID Tests
    
    func testUserIdGenerationFormat() {
        let userId = UserIDHelper.generateUserId()
        XCTAssertTrue(userId.hasPrefix("u_"), "User ID must strictly conform to naming convention with u_ prefix")
        XCTAssertGreaterThan(userId.count, 5)
    }
    
    func testAccountTypeEnums() {
        let anon = FriendsAccountType.anonymous
        let persistent = FriendsAccountType.persistent
        
        XCTAssertNotEqual(anon, persistent)
        XCTAssertEqual(anon.rawValue, 1)
        XCTAssertEqual(persistent.rawValue, 2)
    }
}

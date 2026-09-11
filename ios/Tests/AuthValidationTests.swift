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
    
    // MARK: - Localization Tests
    
    func testAuthLocalizationKeys() {
        XCTAssertEqual(L10n.Auth.recoveryBtn, "ふっかつのじゅもん")
        XCTAssertEqual(L10n.Auth.resetDeviceBtn, "この端末から鍵を完全に消す")
        XCTAssertEqual(L10n.Auth.resetDeviceConfirmTitle, "この端末から鍵を完全に消しますか？")
        XCTAssertTrue(L10n.Auth.resetDeviceConfirmMsg.starts(with: "Keychainに保存された暗号鍵を含む"))
        XCTAssertEqual(L10n.Common.close, "閉じる")
        XCTAssertEqual(L10n.Common.cancel, "キャンセル")
        XCTAssertEqual(L10n.Common.delete, "削除")
    }
    
    func testProfileLocalizationKeys() {
        XCTAssertEqual(L10n.Settings.profileUsernameTooShort, "ユーザー名は3文字以上で入力してください。")
        XCTAssertEqual(L10n.Settings.profileUsernameTooLong, "ユーザー名は20文字以内で入力してください。")
        XCTAssertEqual(L10n.Error.User.usernameTaken, "このユーザー名は既に使用されています。")
    }
}


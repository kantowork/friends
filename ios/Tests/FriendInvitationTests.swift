import XCTest
import ULID
@testable import Friends

final class FriendInvitationTests: XCTestCase {
    
    // MARK: - Passcode Generator Tests (3桁合言葉・30秒ローテーション)
    
    func testPasscodeGenerationFormat() {
        let uid = "test_uid_12345"
        let tenantId = "t_kanto_corp"
        let passcode = FriendPasscodeGenerator.generatePasscode(uid: uid, tenantId: tenantId)
        
        XCTAssertEqual(passcode.count, 3, "合言葉は厳密に3桁である必要があります")
        XCTAssertTrue(passcode.allSatisfy({ $0.isNumber }), "合言葉は数字のみで構成されている必要があります")
    }
    
    func testPasscodeDeterminism() {
        let uid = "test_uid_alice"
        let tenantId = "t_test_corp"
        let fixedDate = Date(timeIntervalSince1970: 1700000000) // Fixed point in time
        
        let code1 = FriendPasscodeGenerator.generatePasscode(uid: uid, tenantId: tenantId, date: fixedDate)
        let code2 = FriendPasscodeGenerator.generatePasscode(uid: uid, tenantId: tenantId, date: fixedDate)
        
        XCTAssertEqual(code1, code2, "同一時刻・同一UID・同一テナントの合言葉は一致する必要があります")
    }
    
    func testPasscodeRotationAfter30Seconds() {
        let uid = "test_uid_bob"
        let tenantId = "t_test_corp"
        let baseDate = Date(timeIntervalSince1970: 1700000000)
        let rotatedDate = Date(timeIntervalSince1970: 1700000035) // +35s (next step)
        
        let code1 = FriendPasscodeGenerator.generatePasscode(uid: uid, tenantId: tenantId, date: baseDate)
        let code2 = FriendPasscodeGenerator.generatePasscode(uid: uid, tenantId: tenantId, date: rotatedDate)
        
        // Step differs, should be validated across windows
        let isValidCurrent = FriendPasscodeGenerator.validatePasscode(code: code1, uid: uid, tenantId: tenantId, date: baseDate)
        XCTAssertTrue(isValidCurrent)
        
        // Window tolerance test (+1 step tolerance)
        let isValidWithTolerance = FriendPasscodeGenerator.validatePasscode(code: code1, uid: uid, tenantId: tenantId, date: rotatedDate, toleranceSteps: 1)
        XCTAssertTrue(isValidWithTolerance, "前後1ステップの猶予期間内であれば検証が通る必要があります")
    }
    
    // MARK: - Invitation Payload Encode & Decode Tests
    
    func testPayloadEncodeAndDecode() {
        let uid = "uid_test_charlie"
        let tenantId = "t_sample_tenant"
        let passcode = "782"
        
        var payload = FriendsFriendInvitationPayload()
        payload.type = "friend_invite"
        payload.version = 1
        payload.tenantID = tenantId
        payload.userID = "u_charlie1"
        payload.uid = uid
        payload.displayName = "チャーリー"
        payload.publicKey = "base64SamplePublicKey=="
        payload.passcode = passcode
        payload.timestamp = Int64(Date().timeIntervalSince1970)
        
        let encoded = FriendInvitationHelper.encode(payload: payload)
        XCTAssertTrue(encoded.hasPrefix(FriendInvitationHelper.prefix), "エンコード結果は FRIENDS_USER: プレフィックスで始まる必要があります")
        
        guard let decoded = FriendInvitationHelper.decode(rawInput: encoded) else {
            XCTFail("デコードに失敗しました")
            return
        }
        
        XCTAssertEqual(decoded.userID, "u_charlie1")
        XCTAssertEqual(decoded.uid, uid)
        XCTAssertEqual(decoded.tenantID, tenantId)
        XCTAssertEqual(decoded.displayName, "チャーリー")
        XCTAssertEqual(decoded.publicKey, "base64SamplePublicKey=="
        )
        XCTAssertEqual(decoded.passcode, "782")
    }
    
    // MARK: - Localization (L10n) Tests
    
    func testLocalizationKeys() {
        XCTAssertFalse(L10n.Friend.addTitle.isEmpty)
        XCTAssertFalse(L10n.Friend.tabQR.isEmpty)
        XCTAssertFalse(L10n.Friend.tabText.isEmpty)
        XCTAssertFalse(L10n.Friend.passcodeTitle.isEmpty)
        XCTAssertFalse(L10n.Common.ok.isEmpty)
        XCTAssertFalse(L10n.Error.Friend.invalidFormat.isEmpty)
    }
    
    // MARK: - Message ULID Generation & Lexicographical Ordering Tests
    
    func testMessageULIDGenerationAndLexicographicalSorting() {
        let ulid1 = ULID().ulidString
        Thread.sleep(forTimeInterval: 0.005) // 5ms sleep
        let ulid2 = ULID().ulidString
        Thread.sleep(forTimeInterval: 0.005)
        let ulid3 = ULID().ulidString
        
        let msgId1 = "m_\(ulid1)"
        let msgId2 = "m_\(ulid2)"
        let msgId3 = "m_\(ulid3)"
        
        XCTAssertEqual(msgId1.count, 28, "m_ プレフィックス(2文字) + ULID(26文字) = 28文字である必要があります")
        XCTAssertTrue(msgId1 < msgId2, "時系列順に生成されたULIDメッセージIDは辞書順で msgId1 < msgId2 となる必要があります")
        XCTAssertTrue(msgId2 < msgId3, "時系列順に生成されたULIDメッセージIDは辞書順で msgId2 < msgId3 となる必要があります")
        
        // Sorting test on array of IDs
        let unsorted = [msgId3, msgId1, msgId2]
        let sorted = unsorted.sorted()
        XCTAssertEqual(sorted, [msgId1, msgId2, msgId3], "文字列の辞書順ソートで時系列順に並び替えられる必要があります")
    }
    
    // MARK: - Username & 3-Tier ID Model Tests
    
    func testPublicUserProfileUsernameFallback() {
        // username が空の場合は effectiveUsername が userID にフォールバックすること
        let profile1 = FriendsPublicUserProfile(
            userID: "u_abc12345",
            uid: "firebase_uid_123",
            tenantID: "t_test",
            displayName: "アリス",
            publicKey: "pubkey=="
        )
        XCTAssertEqual(profile1.effectiveUsername, "u_abc12345")
        
        // username が明示的に指定されている場合はそれを返すこと
        let profile2 = FriendsPublicUserProfile(
            userID: "u_abc12345",
            uid: "firebase_uid_123",
            tenantID: "t_test",
            displayName: "アリス",
            publicKey: "pubkey==",
            username: "alice_dev"
        )
        XCTAssertEqual(profile2.effectiveUsername, "alice_dev")
    }
    
    func testUsernameValidationRegex() {
        let regex = "^[a-zA-Z0-9_]{3,20}$"
        let validUsernames = ["alice", "bob_123", "User_Name", "abc", "12345678901234567890"]
        let invalidUsernames = ["ab", "a!b", "user@name", "this_is_too_long_username_over_20", "日本語ユーザー", "user.name", "user-name"]
        
        for name in validUsernames {
            XCTAssertNotNil(name.range(of: regex, options: .regularExpression), "有効なユーザー名が正規表現にマッチする必要があります: \(name)")
        }
        
        for name in invalidUsernames {
            XCTAssertNil(name.range(of: regex, options: .regularExpression), "無効なユーザー名は正規表現で弾かれる必要があります: \(name)")
        }
    }
    
    func testBase58UUIDUserIdGeneration() {
        let userId1 = UserIDHelper.generateUserId()
        let userId2 = UserIDHelper.generateUserId()
        
        XCTAssertTrue(userId1.hasPrefix("u_"), "ユーザー識別子は u_ で始まる必要があります")
        XCTAssertTrue(userId2.hasPrefix("u_"), "ユーザー識別子は u_ で始まる必要があります")
        
        // "u_" (2文字) + Base58(16 bytes: 21~22文字) = 23~24文字以内 (Base58単体で最大22文字)
        let rawBase58 = userId1.replacingOccurrences(of: "u_", with: "")
        XCTAssertTrue(rawBase58.count <= 22, "Base58部分は最大22文字である必要があります: \(rawBase58) (\(rawBase58.count)文字)")
        XCTAssertTrue(rawBase58.count >= 20, "16バイトUUIDのBase58は21文字前後である必要があります: \(rawBase58)")
        
        XCTAssertNotEqual(userId1, userId2, "連続生成されたユーザー識別子は一意である必要があります")
    }
}

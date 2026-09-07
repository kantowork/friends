import XCTest
@testable import Friends

final class AuthValidationTests: XCTestCase {
    
    // MARK: - Nonce Generation Tests
    
    func testRandomNonceGenerationLength() {
        let length32 = AppleAuthCoordinator.generateRandomNonceString(length: 32)
        XCTAssertEqual(length32.count, 32)
        
        let length64 = AppleAuthCoordinator.generateRandomNonceString(length: 64)
        XCTAssertEqual(length64.count, 64)
    }
    
    func testRandomNonceUniqueness() {
        var nonces = Set<String>()
        let count = 100
        for _ in 0..<count {
            let nonce = AppleAuthCoordinator.generateRandomNonceString(length: 32)
            nonces.insert(nonce)
        }
        XCTAssertEqual(nonces.count, count, "Generated nonces should be cryptographically unique")
    }
    
    func testRandomNonceCharacterSet() {
        let validCharacters = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = AppleAuthCoordinator.generateRandomNonceString(length: 128)
        
        for unicodeScalar in nonce.unicodeScalars {
            XCTAssertTrue(validCharacters.contains(unicodeScalar), "Nonce contains invalid character: \(unicodeScalar)")
        }
    }
    
    // MARK: - SHA256 Hash Tests
    
    func testSha256HexKnownVector() {
        // Known SHA256 test vector: "" (empty string) -> e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        let emptyHash = AppleAuthCoordinator.sha256Hex("")
        XCTAssertEqual(emptyHash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        
        // Known SHA256 test vector: "friends" -> 64ec80bc132b3cbdf53495d038318d1fbe0ee8e6b1070cbb4a779183422ba0a0 (or CryptoKit standard)
        let sample = "friends"
        let hash = AppleAuthCoordinator.sha256Hex(sample)
        XCTAssertEqual(hash.count, 64, "SHA-256 hex string should be exactly 64 characters (256 bits)")
    }
    
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

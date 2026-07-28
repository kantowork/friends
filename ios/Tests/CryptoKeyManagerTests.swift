import XCTest
import CryptoKit
@testable import Friends

final class CryptoKeyManagerTests: XCTestCase {
    
    override func tearDown() {
        super.tearDown()
        CryptoKeyManager.shared.deleteKeypair(uid: "test_crypto_user_1")
        CryptoKeyManager.shared.deleteKeypair(uid: "test_crypto_user_2")
    }
    
    func testKeypairGenerationAndPersistence() throws {
        let uid = "test_crypto_user_1"
        
        // 1. Initial generation
        let (privKey1, pubKeyBase64_1) = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        
        XCTAssertFalse(pubKeyBase64_1.isEmpty)
        guard let pubKeyData1 = Data(base64Encoded: pubKeyBase64_1) else {
            XCTFail("公開鍵がBase64デコード可能ではありません")
            return
        }
        XCTAssertEqual(pubKeyData1.count, 32, "Curve25519 の公開鍵は生データ32バイトである必要があります")
        
        // 2. Fetching existing keypair for same UID
        let (privKey2, pubKeyBase64_2) = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        XCTAssertEqual(pubKeyBase64_1, pubKeyBase64_2, "同一UIDの場合は同一の公開鍵が返る必要があります")
        XCTAssertEqual(privKey1.rawRepresentation, privKey2.rawRepresentation, "同一UIDの場合は同一の秘密鍵がKeychainから復元される必要があります")
    }
    
    func testDistinctKeypairsForDifferentUsers() throws {
        let uid1 = "test_crypto_user_1"
        let uid2 = "test_crypto_user_2"
        
        let (_, pubKey1) = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid1)
        let (_, pubKey2) = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid2)
        
        XCTAssertNotEqual(pubKey1, pubKey2, "異なるUIDでは異なる鍵ペアが生成される必要があります")
    }
    
    func testKeyDeletion() throws {
        let uid = "test_crypto_user_1"
        
        let (_, pubKey1) = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        CryptoKeyManager.shared.deleteKeypair(uid: uid)
        
        XCTAssertNil(CryptoKeyManager.shared.getPrivateKey(uid: uid), "削除後は秘密鍵が存在しない必要があります")
        
        // Regenerating should generate a new keypair
        let (_, pubKey2) = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        XCTAssertNotEqual(pubKey1, pubKey2, "削除後の新規生成では新しい鍵ペアが作成される必要があります")
    }
    
    func testTenantMasterKeyEncryptionAndDecryption() throws {
        let tenantId = "t_test_encryption_corp"
        let secretKey = SymmetricKey(size: .bits256)
        let keyBase64 = secretKey.withUnsafeBytes { Data($0).base64EncodedString() }
        
        // 1. Save master key
        CryptoKeyManager.shared.saveTenantMasterKey(tenantId: tenantId, masterKeyBase64: keyBase64)
        
        let retrievedKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
        XCTAssertNotNil(retrievedKey, "Keychainからテナントマスターキーが取得できる必要があります")
        
        // 2. Encrypt sensitive plain text
        let originalText = "テスト田中 太郎（極秘部署）"
        let (encryptedData, nonce) = try CryptoKeyManager.shared.encryptWithTenantKey(plainText: originalText, tenantId: tenantId)
        
        XCTAssertFalse(encryptedData.isEmpty)
        XCTAssertFalse(nonce.isEmpty)
        XCTAssertNotEqual(originalText, encryptedData, "暗号化データは平文と異なる必要があります")
        
        // 3. Decrypt and verify matching original
        let decryptedText = try CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encryptedData, nonce: nonce, tenantId: tenantId)
        XCTAssertEqual(decryptedText, originalText, "復号されたテキストは平文と一致する必要があります")
    }
    
    func testTenantMasterKeyFallbackForDefaultTenant() throws {
        let defaultTenantId = "t_kanto_corp"
        let key = CryptoKeyManager.shared.getTenantMasterKey(tenantId: defaultTenantId)
        XCTAssertNotNil(key, "デフォルトテナントIDに対しては自動的にフォールバックキーが生成される必要があります")
        
        let originalText = "アリス・スミス"
        let (encrypted, nonce) = try CryptoKeyManager.shared.encryptWithTenantKey(plainText: originalText, tenantId: defaultTenantId)
        let decrypted = try CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encrypted, nonce: nonce, tenantId: defaultTenantId)
        XCTAssertEqual(decrypted, originalText)
    }
}

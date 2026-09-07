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
    
    // MARK: - Personal Key (SK_u based) Tests
    
    func testPersonalKeyDerivationAndEncryption() throws {
        let uid = "test_crypto_user_1"
        _ = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        
        let personalKey = CryptoKeyManager.shared.getPersonalKey(uid: uid)
        XCTAssertNotNil(personalKey, "秘密鍵から個人専用暗号鍵 (MK_u) が導出できる必要があります")
        
        let friendCustomName = "親友のボブ（高校同期）"
        let (encryptedData, nonce) = try CryptoKeyManager.shared.encryptWithPersonalKey(plainText: friendCustomName, uid: uid)
        
        XCTAssertFalse(encryptedData.isEmpty)
        XCTAssertFalse(nonce.isEmpty)
        XCTAssertNotEqual(friendCustomName, encryptedData, "暗号化データは平文と異なる必要があります")
        
        let decrypted = try CryptoKeyManager.shared.decryptWithPersonalKey(encryptedData: encryptedData, nonce: nonce, uid: uid)
        XCTAssertEqual(decrypted, friendCustomName, "自身の個人鍵で復号された文字列は平文と一致する必要があります")
    }
    
    func testPersonalKeyIsolationAcrossUsers() throws {
        let uid1 = "test_crypto_user_1"
        let uid2 = "test_crypto_user_2"
        _ = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid1)
        _ = try CryptoKeyManager.shared.getOrCreateKeypair(uid: uid2)
        
        let customName = "秘密のニックネーム"
        let (encryptedData, nonce) = try CryptoKeyManager.shared.encryptWithPersonalKey(plainText: customName, uid: uid1)
        
        // uid2 の個人鍵では uid1 の暗号文を復号できないことを検証 (Zero-Knowledge Isolation)
        XCTAssertThrowsError(try CryptoKeyManager.shared.decryptWithPersonalKey(encryptedData: encryptedData, nonce: nonce, uid: uid2)) { error in
            // CryptoKit authentication failure
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - File Attachment (Envelope Encryption) Tests
    
    func testFileAttachmentEncryptionAndDecryption() throws {
        let sampleFileData = Data("This is a confidential photo binary sample for Friends E2EE testing.".utf8)
        let fileKey = CryptoKeyManager.shared.generateFileKey()
        
        // 1. Encrypt file binary
        let (encryptedData, nonce) = try CryptoKeyManager.shared.encryptFile(fileData: sampleFileData, key: fileKey)
        XCTAssertFalse(encryptedData.isEmpty)
        XCTAssertFalse(nonce.isEmpty)
        XCTAssertNotEqual(sampleFileData, encryptedData, "暗号化バイナリは生データと異なる必要があります")
        
        // 2. Decrypt with correct key
        let decryptedData = try CryptoKeyManager.shared.decryptFile(encryptedData: encryptedData, key: fileKey)
        XCTAssertEqual(sampleFileData, decryptedData, "復号データは元の生データと完全に一致する必要があります")
        
        // 3. Decrypt with wrong key should fail
        let wrongKey = CryptoKeyManager.shared.generateFileKey()
        XCTAssertThrowsError(try CryptoKeyManager.shared.decryptFile(encryptedData: encryptedData, key: wrongKey), "異なるファイル鍵での復号は失敗する必要があります")
    }
    
    func testMessageContentPayloadCodableAndDecryptedMessageParsing() throws {
        let attachment = MessageAttachment(
            attachmentId: "att_test_123",
            storagePath: "tenants/t_test/chats/dm_1_2/attachments/att_test_123.enc",
            fileKey: "dGVzdEtleTEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNA==",
            nonce: "dGVzdE5vbmNlMTI=",
            mimeType: "image/jpeg",
            width: 1920,
            height: 1080,
            size: 102400
        )
        
        let payload = MessageContentPayload(text: "写真送ります！", attachments: [attachment])
        let encodedData = try JSONEncoder().encode(payload)
        let jsonString = String(data: encodedData, encoding: .utf8)!
        
        var pbMsg = FriendsMessage()
        pbMsg.messageID = "m_test_msg_1"
        pbMsg.messageType = .image
        
        let decryptedMsg = DecryptedMessage(
            message: pbMsg,
            senderName: "テスト送信者",
            plainText: jsonString,
            decryptedText: jsonString
        )
        
        XCTAssertEqual(decryptedMsg.plainText, "写真送ります！", "JSONペイロードからテキストが正しく抽出される必要があります")
        XCTAssertTrue(decryptedMsg.hasAttachments, "添付ファイルが存在すると判定される必要があります")
        XCTAssertEqual(decryptedMsg.attachments.count, 1)
        XCTAssertEqual(decryptedMsg.attachments[0].attachmentId, "att_test_123")
        XCTAssertEqual(decryptedMsg.attachments[0].width, 1920)
    }
}

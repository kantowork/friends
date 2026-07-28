import Foundation
import CryptoKit
import Security

// MARK: - CryptoKeyManager
// ユーザーの端末内秘密鍵（Curve25519）を iOS Keychain で安全に保持し、
// Firestore に公開鍵（Base64）を配置するための暗号鍵管理サービス

final class CryptoKeyManager {
    static let shared = CryptoKeyManager()
    
    private let serviceName = "work.kanto.friends.keys"
    
    private init() {}
    
    // MARK: - Keypair Generation & Retrieval
    
    /// 指定された UID に対する既存の鍵ペアを取得するか、存在しない場合は新規生成して Keychain に永続化する
    func getOrCreateKeypair(uid: String) throws -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKeyBase64: String) {
        if let existingPrivKey = getPrivateKey(uid: uid) {
            let pubKeyBase64 = existingPrivKey.publicKey.rawRepresentation.base64EncodedString()
            return (existingPrivKey, pubKeyBase64)
        }
        
        // 新規 Curve25519 鍵ペアの生成
        let newPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let pubKeyBase64 = newPrivateKey.publicKey.rawRepresentation.base64EncodedString()
        
        try savePrivateKey(uid: uid, privateKey: newPrivateKey)
        savePublicKeyString(uid: uid, publicKeyBase64: pubKeyBase64)
        
        return (newPrivateKey, pubKeyBase64)
    }
    
    /// 指定された UID の秘密鍵を取得する
    func getPrivateKey(uid: String) -> Curve25519.KeyAgreement.PrivateKey? {
        let keyTag = privateKeyTag(for: uid)
        guard let keyData = loadFromKeychain(key: keyTag) else {
            return nil
        }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyData)
    }
    
    /// 指定された UID の公開鍵 (Base64) を取得する
    func getPublicKeyBase64(uid: String) -> String? {
        if let pubKeyStr = loadStringFromKeychain(key: publicKeyTag(for: uid)) {
            return pubKeyStr
        }
        if let privKey = getPrivateKey(uid: uid) {
            let pubKeyBase64 = privKey.publicKey.rawRepresentation.base64EncodedString()
            savePublicKeyString(uid: uid, publicKeyBase64: pubKeyBase64)
            return pubKeyBase64
        }
        return nil
    }
    
    /// 秘密鍵を Keychain に保存する
    func savePrivateKey(uid: String, privateKey: Curve25519.KeyAgreement.PrivateKey) throws {
        let keyTag = privateKeyTag(for: uid)
        let rawData = privateKey.rawRepresentation
        let status = saveToKeychain(key: keyTag, data: rawData)
        if status != errSecSuccess && status != errSecDuplicateItem {
            throw NSError(
                domain: "CryptoKeyManager",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to save private key to Keychain with OSStatus \(status)"]
            )
        }
    }
    
    private func savePublicKeyString(uid: String, publicKeyBase64: String) {
        let keyTag = publicKeyTag(for: uid)
        if let data = publicKeyBase64.data(using: .utf8) {
            _ = saveToKeychain(key: keyTag, data: data)
        }
    }
    
    /// アカウント削除やリセット時に鍵ペアを削除する
    func deleteKeypair(uid: String) {
        deleteFromKeychain(key: privateKeyTag(for: uid))
        deleteFromKeychain(key: publicKeyTag(for: uid))
    }
    
    // MARK: - Tenant Master Key (MK_T) Management & Encryption
    
    /// テナントマスターキー (MK_T) を Keychain に保存する
    func saveTenantMasterKey(tenantId: String, masterKeyBase64: String) {
        guard let data = Data(base64Encoded: masterKeyBase64), data.count >= 16 else { return }
        let keyTag = tenantKeyTag(for: tenantId)
        _ = saveToKeychain(key: keyTag, data: data)
    }
    
    /// テナントマスターキー (MK_T) を Keychain から取得する
    func getTenantMasterKey(tenantId: String) -> SymmetricKey? {
        let keyTag = tenantKeyTag(for: tenantId)
        if let data = loadFromKeychain(key: keyTag) {
            return SymmetricKey(data: data)
        }
        
        // PresetTenantConfig にプリセット鍵が設定されている場合
        if tenantId == PresetTenantConfig.tenantId,
           let presetKeyData = Data(base64Encoded: PresetTenantConfig.tenantMasterKey),
           presetKeyData.count >= 16 {
            _ = saveToKeychain(key: keyTag, data: presetKeyData)
            return SymmetricKey(data: presetKeyData)
        }
        
        // デフォルトテナント向けフォールバック鍵（確定シードによる派生）
        if tenantId.hasPrefix("t_") || tenantId.isEmpty {
            let seed = "friends-tenant-default-master-key-\(tenantId)"
            let hash = SHA256.hash(data: Data(seed.utf8))
            let key = SymmetricKey(data: hash)
            // 自動キャッシュ
            _ = saveToKeychain(key: keyTag, data: Data(hash))
            return key
        }
        return nil
    }
    
    /// テナントマスターキーを用いて文字列を AES-256-GCM 暗号化する
    func encryptWithTenantKey(plainText: String, tenantId: String) throws -> (encryptedData: String, nonce: String) {
        guard let masterKey = getTenantMasterKey(tenantId: tenantId) else {
            throw NSError(
                domain: "CryptoKeyManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Tenant master key not found for tenant \(tenantId)"]
            )
        }
        
        let plainData = Data(plainText.utf8)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plainData, using: masterKey, nonce: nonce)
        
        guard let combined = sealedBox.combined else {
            throw NSError(
                domain: "CryptoKeyManager",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to seal AES-GCM payload"]
            )
        }
        
        let encryptedBase64 = combined.base64EncodedString()
        let nonceBase64 = Data(nonce).base64EncodedString()
        
        return (encryptedBase64, nonceBase64)
    }
    
    /// テナントマスターキーを用いて暗号文を復号する
    func decryptWithTenantKey(encryptedData: String, nonce: String, tenantId: String) throws -> String {
        guard let masterKey = getTenantMasterKey(tenantId: tenantId) else {
            throw NSError(
                domain: "CryptoKeyManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Tenant master key not found for tenant \(tenantId)"]
            )
        }
        
        guard let combinedData = Data(base64Encoded: encryptedData) else {
            throw NSError(
                domain: "CryptoKeyManager",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid base64 encrypted data"]
            )
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: masterKey)
        
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(
                domain: "CryptoKeyManager",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Decrypted data is not valid UTF-8 string"]
            )
        }
        
        return decryptedString
    }
    
    // MARK: - E2EE Direct Message Encryption (1:1 ECDH + HKDF + AES-256-GCM)
    
    /// 自分の秘密鍵と相手の公開鍵から 1:1 チャット用セッション鍵 (SK_direct) を導出する
    func deriveDirectSessionKey(myUid: String, peerPublicKeyBase64: String, tenantId: String) throws -> SymmetricKey {
        guard let myPrivateKey = getPrivateKey(uid: myUid) else {
            throw NSError(domain: "CryptoKeyManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "My private key not found for uid \(myUid)"])
        }
        
        guard let peerPubData = Data(base64Encoded: peerPublicKeyBase64) else {
            throw NSError(domain: "CryptoKeyManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid peer public key base64"])
        }
        
        let peerPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPubData)
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        
        let saltString = "friends-direct-salt-\(tenantId)"
        let salt = Data(saltString.utf8)
        let info = Data("friends-direct-v1".utf8)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
        return symmetricKey
    }
    
    /// メッセージ本文を E2EE 暗号化する
    func encryptDirectMessage(plainText: String, sessionKey: SymmetricKey) throws -> (ciphertext: String, nonce: String) {
        let plainData = Data(plainText.utf8)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plainData, using: sessionKey, nonce: nonce)
        
        guard let combined = sealedBox.combined else {
            throw NSError(domain: "CryptoKeyManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to seal direct message payload"])
        }
        
        return (combined.base64EncodedString(), Data(nonce).base64EncodedString())
    }
    
    /// E2EE 暗号化されたメッセージ本文を復号する
    func decryptDirectMessage(ciphertext: String, nonce: String, sessionKey: SymmetricKey) throws -> String {
        guard let combinedData = Data(base64Encoded: ciphertext) else {
            throw NSError(domain: "CryptoKeyManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid ciphertext base64"])
        }
        
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: sessionKey)
        
        guard let text = String(data: decryptedData, encoding: .utf8) else {
            throw NSError(domain: "CryptoKeyManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Decrypted payload is not valid UTF-8 text"])
        }
        return text
    }
    
    // MARK: - Key Tag Helpers
    
    private func privateKeyTag(for uid: String) -> String {
        "friends_priv_key_\(uid)"
    }
    
    private func publicKeyTag(for uid: String) -> String {
        "friends_pub_key_\(uid)"
    }
    
    private func tenantKeyTag(for tenantId: String) -> String {
        "friends_tenant_key_\(tenantId)"
    }
    
    // MARK: - Keychain CRUD Helpers
    
    private func saveToKeychain(key: String, data: Data) -> OSStatus {
        // 既存の同名キーがあれば一度削除
        deleteFromKeychain(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }
    
    private func loadStringFromKeychain(key: String) -> String? {
        guard let data = loadFromKeychain(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// アプリに紐づくすべての Keychain 項目（秘密鍵・公開鍵・テナントキー・セッション鍵）を完全消去する
    func clearAllKeys() {
        let secClasses = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]
        for secClass in secClasses {
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecAttrService as String: serviceName
            ]
            SecItemDelete(query as CFDictionary)
        }
        print("🧹 Keychain keys completely cleared.")
    }
}

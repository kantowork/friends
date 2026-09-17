import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import SwiftProtobuf

// MARK: - AuthStatus
enum AuthStatus {
    case unknown
    case unauthenticated
    case authenticated
}

// MARK: - AuthService
/// 認証、アクティブテナント、ふっかつのじゅもん（Mnemonic）による鍵バックアップ/復旧、アカウント管理を担当するサービス
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()
    
    @Published var authStatus: AuthStatus = .unknown
    @Published var currentTenant: FriendsTenant? = PresetTenantConfig.defaultTenant {
        didSet {
            if let tenantId = currentTenant?.tenantID {
                BlockManager.shared.configure(tenantId: tenantId)
            }
        }
    }
    @Published var currentUser: FriendsPublicUserProfile? = nil
    
    private let db = Firestore.firestore()
    
    private init() {
        if let defaultTid = currentTenant?.tenantID {
            BlockManager.shared.configure(tenantId: defaultTid)
        }
        checkAuthState()
    }
    
    // MARK: - Initial Auth & Tenant Checking
    
    func checkAuthState() {
        TenantManager.shared.loadTenantsFromStorage()
        let activeId = TenantManager.shared.activeTenantId
        
        let targetId = activeId.isEmpty ? PresetTenantConfig.tenantId : activeId
        
        // 1. Fetch Active Tenant from Firestore
        TenantRepository.shared.getTenantByTenantId(tenantId: targetId) { [weak self] tenantResult in
            guard let self = self else { return }
            
            let tenantToUse: FriendsTenant
            switch tenantResult {
            case .success(let tenant):
                tenantToUse = tenant
            case .failure:
                tenantToUse = PresetTenantConfig.defaultTenant
            }
            
            DispatchQueue.main.async {
                self.currentTenant = tenantToUse
                TenantManager.shared.addOrUpdateTenant(tenant: tenantToUse)
            }
            
            // 2. Check Firebase Auth
            if let firebaseUser = Auth.auth().currentUser {
                self.loadUserProfile(uid: firebaseUser.uid, tenantId: tenantToUse.tenantID)
                DispatchQueue.main.async {
                    TenantManager.shared.refreshUnreadCounts()
                }
            } else {
                DispatchQueue.main.async {
                    self.authStatus = .unauthenticated
                }
            }
        }
    }
    
    // MARK: - Switch Tenant (複数テナント切り替え)
    
    func switchToTenant(tenantId: String, completion: @escaping (Result<FriendsTenant, Error>) -> Void) {
        guard let authUid = Auth.auth().currentUser?.uid else {
            let err = NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."])
            completion(.failure(err))
            return
        }
        
        // 1. 各サービスの状態クリア
        DirectChatService.shared.clear()
        GroupChatService.shared.clear()
        MessageService.shared.clear()
        
        self.currentUser = nil
        
        // 2. テナント情報の取得・適用
        TenantRepository.shared.getTenantByTenantId(tenantId: tenantId) { [weak self] tenantResult in
            guard let self = self else { return }
            switch tenantResult {
            case .success(let tenant):
                DispatchQueue.main.async {
                    self.currentTenant = tenant
                    TenantManager.shared.setActiveTenantId(tenant.tenantID)
                }
                
                // 3. 当該テナントのユーザープロファイルを確認・ロード
                UserRepository.shared.getUserProfileByUid(tenantId: tenant.tenantID, uid: authUid) { [weak self] userResult in
                    guard let self = self else { return }
                    switch userResult {
                    case .success(let profile):
                        DispatchQueue.main.async {
                            self.currentUser = profile
                            self.authStatus = .authenticated
                            DirectChatService.shared.configure(tenant: tenant, user: profile)
                            GroupChatService.shared.configure(tenant: tenant, user: profile)
                            TenantManager.shared.refreshUnreadCounts()
                            NotificationManager.shared.syncCurrentDevice()
                            completion(.success(tenant))
                        }
                    case .failure:
                        // 未参加テナントの場合: 既存の表示名と公開鍵を引き継いで参加プロファイルを作成
                        let savedName = CryptoKeyManager.shared.getMyDisplayName(uid: authUid) ?? L10n.Common.defaultUser
                        self.createAndSaveUserProfile(uid: authUid, tenantId: tenant.tenantID, displayName: savedName) { createResult in
                            switch createResult {
                            case .success:
                                DispatchQueue.main.async {
                                    TenantManager.shared.refreshUnreadCounts()
                                    completion(.success(tenant))
                                }
                            case .failure(let err):
                                DispatchQueue.main.async {
                                    completion(.failure(err))
                                }
                            }
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Verify and Apply Custom Tenant
    
    func verifyAndApplyTenant(tenantId: String, completion: @escaping (Result<FriendsTenant, Error>) -> Void) {
        TenantRepository.shared.getTenantByTenantId(tenantId: tenantId) { [weak self] result in
            guard let self = self else { return }
            if case .success(let tenant) = result {
                DispatchQueue.main.async {
                    self.currentTenant = tenant
                    TenantManager.shared.addOrUpdateTenant(tenant: tenant)
                    if self.authStatus == .authenticated, let user = self.currentUser {
                        DirectChatService.shared.configure(tenant: tenant, user: user)
                        GroupChatService.shared.configure(tenant: tenant, user: user)
                    }
                }
            }
            completion(result)
        }
    }
    
    // MARK: - Fetch Default Tenant from Cloud Firestore
    
    func fetchDefaultTenant(completion: @escaping (Result<FriendsTenant, Error>) -> Void) {
        TenantRepository.shared.fetchDefaultTenant(completion: completion)
    }
    
    // MARK: - Sign In Anonymously (Guest Login)
    
    func signInAnonymously(displayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signInAnonymously { [weak self] authResult, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let user = authResult?.user else {
                completion(.failure(NSError(domain: "AuthError", code: 500, userInfo: [NSLocalizedDescriptionKey: "User context not found."])))
                return
            }
            
            let name = displayName.isEmpty ? L10n.Common.guestUser : displayName
            self.handleAuthenticatedUser(user: user, preferredDisplayName: name, accountType: .anonymous, completion: completion)
        }
    }
    
    // MARK: - Authenticated User Profile Handler
    
    private func handleAuthenticatedUser(
        user: FirebaseAuth.User,
        preferredDisplayName: String?,
        accountType: FriendsAccountType,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        ensureTenantLoaded { [weak self] tenant in
            guard let self = self else { return }
            let tenantId = tenant.tenantID
            
            UserRepository.shared.getUserProfileByUid(tenantId: tenantId, uid: user.uid) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    if let preferred = preferredDisplayName, !preferred.isEmpty {
                        if CryptoKeyManager.shared.getMyDisplayName(uid: user.uid) == nil {
                            CryptoKeyManager.shared.saveMyDisplayName(uid: user.uid, name: preferred)
                        }
                    }
                    self.loadUserProfile(uid: user.uid, tenantId: tenantId)
                    completion(.success(()))
                    
                case .failure:
                    let finalDisplayName: String
                    if let preferred = preferredDisplayName, !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        finalDisplayName = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let authName = user.displayName, !authName.isEmpty {
                        finalDisplayName = authName
                    } else if let email = user.email, !email.isEmpty {
                        finalDisplayName = email.components(separatedBy: "@").first ?? L10n.Common.defaultUser
                    } else {
                        finalDisplayName = (accountType == .anonymous) ? L10n.Common.guestUser : L10n.Common.defaultUser
                    }
                    
                    self.createAndSaveUserProfile(
                        uid: user.uid,
                        tenantId: tenantId,
                        displayName: finalDisplayName,
                        accountType: accountType,
                        completion: completion
                    )
                }
            }
        }
    }
    
    private func ensureTenantLoaded(action: @escaping (FriendsTenant) -> Void) {
        if let currentTenant = self.currentTenant {
            action(currentTenant)
        } else {
            self.fetchDefaultTenant { result in
                switch result {
                case .success(let tenant):
                    DispatchQueue.main.async { self.currentTenant = tenant }
                    action(tenant)
                case .failure:
                    let defaultTenant = PresetTenantConfig.defaultTenant
                    DispatchQueue.main.async { self.currentTenant = defaultTenant }
                    action(defaultTenant)
                }
            }
        }
    }
    
    private func createAndSaveUserProfile(
        uid: String,
        tenantId: String,
        displayName: String,
        accountType: FriendsAccountType = .anonymous,
        recoveryWords: [String]? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let userId = UserIDHelper.generateUserId()
        
        // 🔐 Curve25519 鍵ペアを生成し、秘密鍵をローカル Keychain に保存
        let keypair = try? CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        let publicKey = keypair?.publicKeyBase64 ?? "defaultPublicKeyBase64=="
        
        // 🔐 ふっかつのじゅもんの生成とバックアップ保存
        if let privKey = keypair?.privateKey {
            self.backupPrivateKeyWithRecoveryPhrase(uid: uid, privateKey: privKey, words: recoveryWords, completion: nil)
        }
        
        // 🔐 表示名を自身の端末 Keychain に安全に保管
        CryptoKeyManager.shared.saveMyDisplayName(uid: uid, name: displayName)
        
        // 🏷 username 初期値は userId の先頭10文字
        let initialUsername = String(userId.prefix(10))
        
        let userProfile = FriendsPublicUserProfile(
            userID: userId,
            uid: uid,
            tenantID: tenantId,
            displayName: displayName,
            publicKey: publicKey,
            role: .member,
            accountType: accountType,
            username: initialUsername
        )
        
        UserRepository.shared.createOrUpdateUserProfile(tenantId: tenantId, user: userProfile) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result {
                completion(.failure(err))
                return
            }
            
            DispatchQueue.main.async {
                self.currentUser = userProfile
                self.authStatus = .authenticated
                if let tenant = self.currentTenant {
                    DirectChatService.shared.configure(tenant: tenant, user: userProfile)
                    GroupChatService.shared.configure(tenant: tenant, user: userProfile)
                }
                NotificationManager.shared.syncCurrentDevice()
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Recovery Phrase & Private Key Backup
    
    func backupPrivateKeyWithRecoveryPhrase(
        uid: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        words: [String]? = nil,
        completion: ((Result<[String], Error>) -> Void)? = nil
    ) {
        AppLogger.debug("[BACKUP] backupPrivateKeyWithRecoveryPhrase START uid=\(uid)", category: .crypto)
        do {
            let phrase: [String]
            if let existingWords = words, MnemonicManager.shared.validateMnemonic(words: existingWords) {
                phrase = existingWords
                AppLogger.debug("[BACKUP] Using provided words (validated)", category: .crypto)
            } else if let savedWords = CryptoKeyManager.shared.getMnemonicPhrase(uid: uid) {
                phrase = savedWords
                AppLogger.debug("[BACKUP] Using saved words from Keychain", category: .crypto)
            } else {
                phrase = try MnemonicManager.shared.generateMnemonic(language: .japanese)
                AppLogger.debug("[BACKUP] Generated new phrase", category: .crypto)
            }
            
            // Keychain に保存
            try CryptoKeyManager.shared.saveMnemonicPhrase(uid: uid, words: phrase)
            AppLogger.debug("[BACKUP] Saved mnemonic phrase to Keychain", category: .crypto)
            
            // 鍵導出 & 秘密鍵暗号化
            let (_, _, privEncKey, recoveryHash) = try MnemonicManager.shared.deriveKeys(from: phrase)
            let (ciphertext, nonce) = try MnemonicManager.shared.encryptPrivateKey(privateKey, using: privEncKey)
            AppLogger.debug("[BACKUP] Derived keys. recoveryHash=\(recoveryHash.prefix(8))... ciphertextLen=\(ciphertext.count) nonceLen=\(nonce.count)", category: .crypto)
            
            // Firestore /users/{uid}/private/data に保存
            var privateData = FriendsUserPrivateData()
            privateData.uid = uid
            privateData.recoveryHash = recoveryHash
            privateData.encryptedPrivateKey = ciphertext
            privateData.nonce = nonce
            privateData.updatedAt = Google_Protobuf_Timestamp(date: Date())
            
            AppLogger.debug("[BACKUP] Saving to /users/\(uid)/private/data ...", category: .crypto)
            UserRepository.shared.setUserPrivateDataByUid(uid: uid, data: privateData) { result in
                switch result {
                case .success:
                    AppLogger.debug("[BACKUP] Saved /users/\(uid)/private/data OK. Now saving recovery_vault/\(recoveryHash.prefix(8))...", category: .crypto)
                    // 端末復元ボルト (/recovery_vault/{recoveryHash}) にも同時に保存
                    UserRepository.shared.saveRecoveryVaultRecord(
                        recoveryHash: recoveryHash,
                        uid: uid,
                        encryptedPrivateKey: ciphertext,
                        nonce: nonce
                    ) { vaultResult in
                        switch vaultResult {
                        case .success:
                            AppLogger.info("[BACKUP] ✅ recovery_vault/\(recoveryHash.prefix(8))... saved OK uid=\(uid)", category: .crypto)
                            completion?(.success(phrase))
                        case .failure(let vaultErr):
                            AppLogger.error("[BACKUP] ❌ Failed to save recovery_vault: \(vaultErr)", category: .crypto)
                            completion?(.success(phrase))
                        }
                    }
                case .failure(let err):
                    AppLogger.error("[BACKUP] ❌ Failed to save /users/\(uid)/private/data: \(err)", category: .crypto)
                    completion?(.failure(err))
                }
            }
        } catch {
            AppLogger.error("[BACKUP] ❌ Exception in backupPrivateKeyWithRecoveryPhrase: \(error)", category: .crypto)
            completion?(.failure(error))
        }
    }
    
    func regenerateRecoveryPhrase(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let currentUser = currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        let uid = currentUser.uid
        guard let privKey = CryptoKeyManager.shared.getPrivateKey(uid: uid) else {
            completion(.failure(NSError(domain: "AuthService", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        do {
            let newPhrase = try MnemonicManager.shared.generateMnemonic(language: .japanese)
            backupPrivateKeyWithRecoveryPhrase(uid: uid, privateKey: privKey, words: newPhrase) { result in
                completion(result)
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Restore with Recovery Phrase
    
    func restoreWithRecoveryPhrase(words: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        AppLogger.debug("[RESTORE] restoreWithRecoveryPhrase START wordCount=\(words.count)", category: .crypto)
        guard MnemonicManager.shared.validateMnemonic(words: words) else {
            AppLogger.error("[RESTORE] ❌ Mnemonic validation failed", category: .crypto)
            completion(.failure(NSError(domain: "AuthService", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Auth.recoveryInvalidPhrase])))
            return
        }
        AppLogger.debug("[RESTORE] Mnemonic validated OK", category: .crypto)
        
        if let currentUser = Auth.auth().currentUser {
            AppLogger.debug("[RESTORE] Already authenticated uid=\(currentUser.uid) → restoreKeysForAuthenticatedUser", category: .crypto)
            restoreKeysForAuthenticatedUser(user: currentUser, words: words, completion: completion)
            return
        }
        AppLogger.debug("[RESTORE] Not authenticated → anonymous recovery via Workers", category: .crypto)
        
        guard let baseURL = WorkerConfig.baseURL else {
            AppLogger.error("[RESTORE] ❌ WorkerConfig.baseURL is nil (tenant not configured)", category: .repo)
            completion(.failure(NSError(domain: "AuthService", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.tenantNotConfigured])))
            return
        }
        AppLogger.debug("[RESTORE] Workers baseURL=\(baseURL.absoluteString)", category: .repo)
        
        do {
            let (_, _, privEncKey, recoveryHash) = try MnemonicManager.shared.deriveKeys(from: words)
            AppLogger.debug("[RESTORE] Derived recoveryHash=\(recoveryHash)", category: .crypto)
            
            let url = baseURL.appendingPathComponent("api/v1/auth/recover-anonymous")
            AppLogger.debug("[RESTORE] POST \(url.absoluteString) body={recoveryHash:\(recoveryHash.prefix(8))...}", category: .repo)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let reqBody = RecoverAnonymousRequest(recoveryHash: recoveryHash)
            request.httpBody = try JSONEncoder().encode(reqBody)
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.error("[RESTORE] ❌ Network error: \(error)", category: .repo)
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    AppLogger.error("[RESTORE] ❌ Response is not HTTPURLResponse", category: .repo)
                    let err = NSError(domain: "AuthService", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                AppLogger.debug("[RESTORE] HTTP status=\(httpResponse.statusCode)", category: .repo)
                
                guard let data = data else {
                    AppLogger.error("[RESTORE] ❌ No response body (status=\(httpResponse.statusCode))", category: .repo)
                    let err = NSError(domain: "AuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.dataNotFound])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                let rawBody = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                AppLogger.debug("[RESTORE] Response body: \(rawBody)", category: .repo)
                
                guard httpResponse.statusCode == 200 else {
                    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    let errorCode = json?["code"] as? String
                    let rawError = json?["error"] as? String ?? "HTTP \(httpResponse.statusCode)"
                    AppLogger.error("[RESTORE] ❌ API error status=\(httpResponse.statusCode) code=\(errorCode ?? "none") msg=\(rawError)", category: .repo)
                    
                    let errorMessage: String
                    switch (httpResponse.statusCode, errorCode) {
                    case (404, _), (_, "ACCOUNT_NOT_FOUND"):
                        errorMessage = L10n.Error.Recovery.dataNotFound
                    case (400, _), (_, "INVALID_FORMAT"):
                        errorMessage = L10n.Error.Recovery.invalidFormat
                    case (_, "SERVER_CONFIG_MISSING"):
                        errorMessage = L10n.Error.Recovery.serverConfigMissing
                    case (500...599, _):
                        errorMessage = L10n.Error.Recovery.serverError
                    default:
                        errorMessage = L10n.Error.Recovery.serverError
                    }
                    let err = NSError(domain: "AuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                
                do {
                    guard let apiRes = try? JSONDecoder().decode(RecoverAnonymousResponse.self, from: data) else {
                        AppLogger.error("[RESTORE] ❌ Failed to decode RecoverAnonymousResponse: \(rawBody)", category: .repo)
                        throw NSError(domain: "AuthService", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.dataNotFound])
                    }
                    let customToken = apiRes.customToken
                    let recoveredUid = apiRes.uid
                    let encryptedPrivateKey = apiRes.encryptedPrivateKey
                    let nonce = apiRes.nonce
                    AppLogger.debug("[RESTORE] Got customToken uid=\(recoveredUid) encKeyLen=\(encryptedPrivateKey.count)", category: .crypto)
                    
                    Auth.auth().signIn(withCustomToken: customToken) { authResult, signInError in
                        if let signInError = signInError {
                            AppLogger.error("[RESTORE] ❌ signIn(customToken) failed: \(signInError)", category: .auth)
                            DispatchQueue.main.async { completion(.failure(signInError)) }
                            return
                        }
                        AppLogger.debug("[RESTORE] signIn(customToken) OK uid=\(recoveredUid)", category: .auth)
                        
                        do {
                            let restoredPrivateKey = try MnemonicManager.shared.decryptPrivateKey(
                                ciphertext: encryptedPrivateKey,
                                nonce: nonce,
                                using: privEncKey
                            )
                            AppLogger.debug("[RESTORE] Decrypted private key OK", category: .crypto)
                            
                            try CryptoKeyManager.shared.savePrivateKey(uid: recoveredUid, privateKey: restoredPrivateKey)
                            try CryptoKeyManager.shared.saveMnemonicPhrase(uid: recoveredUid, words: words)
                            AppLogger.info("[RESTORE] ✅ Recovery complete for uid=\(recoveredUid)", category: .crypto)
                            
                            DispatchQueue.main.async {
                                self.fetchDefaultTenant { tenantResult in
                                    switch tenantResult {
                                    case .success(let tenant):
                                        self.currentTenant = tenant
                                        self.loadUserProfile(uid: recoveredUid, tenantId: tenant.tenantID)
                                        completion(.success(()))
                                    case .failure:
                                        self.loadUserProfile(uid: recoveredUid, tenantId: PresetTenantConfig.tenantId)
                                        completion(.success(()))
                                    }
                                }
                            }
                        } catch {
                            AppLogger.error("[RESTORE] ❌ Failed to decrypt private key: \(error)", category: .crypto)
                            DispatchQueue.main.async { completion(.failure(error)) }
                        }
                    }
                } catch {
                    AppLogger.error("[RESTORE] ❌ Failed to parse response: \(error)", category: .crypto)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }.resume()
        } catch {
            AppLogger.error("[RESTORE] ❌ Failed to derive keys: \(error)", category: .crypto)
            completion(.failure(error))
        }
    }
    
    private func restoreKeysForAuthenticatedUser(user: FirebaseAuth.User, words: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        AppLogger.debug("[RESTORE-AUTH] restoreKeysForAuthenticatedUser START uid=\(user.uid)", category: .crypto)
        AppLogger.debug("[RESTORE-AUTH] Fetching /users/\(user.uid)/private/data ...", category: .crypto)
        UserRepository.shared.getUserPrivateDataByUid(uid: user.uid) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let privateData):
                AppLogger.debug("[RESTORE-AUTH] Got privateData. recoveryHash=\(privateData.recoveryHash.prefix(8))... encKeyLen=\(privateData.encryptedPrivateKey.count)", category: .crypto)
                do {
                    let (_, _, privEncKey, recoveryHash) = try MnemonicManager.shared.deriveKeys(from: words)
                    AppLogger.debug("[RESTORE-AUTH] Derived recoveryHash=\(recoveryHash.prefix(8))... stored=\(privateData.recoveryHash.prefix(8))...", category: .crypto)
                    if !privateData.recoveryHash.isEmpty && privateData.recoveryHash != recoveryHash {
                        AppLogger.error("[RESTORE-AUTH] ❌ recoveryHash mismatch: derived=\(recoveryHash) stored=\(privateData.recoveryHash)", category: .crypto)
                        let err = NSError(domain: "AuthService", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Auth.recoveryInvalidPhrase])
                        DispatchQueue.main.async { completion(.failure(err)) }
                        return
                    }
                    let restoredPrivateKey = try MnemonicManager.shared.decryptPrivateKey(
                        ciphertext: privateData.encryptedPrivateKey,
                        nonce: privateData.nonce,
                        using: privEncKey
                    )
                    AppLogger.debug("[RESTORE-AUTH] Decrypted private key OK", category: .crypto)
                    
                    try CryptoKeyManager.shared.savePrivateKey(uid: user.uid, privateKey: restoredPrivateKey)
                    try CryptoKeyManager.shared.saveMnemonicPhrase(uid: user.uid, words: words)
                    AppLogger.info("[RESTORE-AUTH] ✅ Authenticated recovery complete for uid=\(user.uid)", category: .crypto)
                    
                    let tenantId = self.currentTenant?.tenantID ?? PresetTenantConfig.tenantId
                    DispatchQueue.main.async {
                        self.loadUserProfile(uid: user.uid, tenantId: tenantId)
                        completion(.success(()))
                    }
                } catch {
                    AppLogger.error("[RESTORE-AUTH] ❌ Exception: \(error)", category: .crypto)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            case .failure(let err):
                AppLogger.error("[RESTORE-AUTH] ❌ Failed to get /users/\(user.uid)/private/data: \(err)", category: .crypto)
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }
    
    // MARK: - Security Reset
    
    func performSecurityReset(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUser = currentUser, let authUid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        do {
            let newPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            let newPublicKeyBase64 = newPrivateKey.publicKey.rawRepresentation.base64EncodedString()
            try CryptoKeyManager.shared.savePrivateKey(uid: authUid, privateKey: newPrivateKey)
            
            var updatedProfile = currentUser
            updatedProfile.publicKey = newPublicKeyBase64
            
            let tenantId = currentUser.tenantID
            UserRepository.shared.createOrUpdateUserProfile(tenantId: tenantId, user: updatedProfile) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    DispatchQueue.main.async {
                        self.currentUser = updatedProfile
                    }
                    self.backupPrivateKeyWithRecoveryPhrase(uid: authUid, privateKey: newPrivateKey) { _ in }
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - Load User Profile
    
    func loadUserProfile(uid: String, tenantId: String) {
        UserRepository.shared.getUserProfileByUid(tenantId: tenantId, uid: uid) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let userProfile):
                let keypair = try? CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
                let localPublicKey = keypair?.publicKeyBase64 ?? ""
                var profile = userProfile
                if !localPublicKey.isEmpty && profile.publicKey != localPublicKey {
                    profile.publicKey = localPublicKey
                    UserRepository.shared.createOrUpdateUserProfile(tenantId: tenantId, user: profile) { _ in }
                }
                
                if let savedName = CryptoKeyManager.shared.getMyDisplayName(uid: uid), !savedName.isEmpty {
                    profile.displayName = savedName
                }
                
                DispatchQueue.main.async {
                    self.currentUser = profile
                    self.authStatus = .authenticated
                    if let tenant = self.currentTenant {
                        DirectChatService.shared.configure(tenant: tenant, user: profile)
                        GroupChatService.shared.configure(tenant: tenant, user: profile)
                    }
                    NotificationManager.shared.syncCurrentDevice()
                }
            case .failure:
                DispatchQueue.main.async {
                    self.authStatus = .unauthenticated
                }
            }
        }
    }
    
    // MARK: - Sign Out & Device Reset
    
    func signOut(clearKeys: Bool = true) {
        if clearKeys {
            CryptoKeyManager.shared.clearAllKeys()
        }
        
        try? Auth.auth().signOut()
        
        clear()
    }
    
    func clear() {
        DirectChatService.shared.clear()
        GroupChatService.shared.clear()
        MessageService.shared.clear()
        self.currentUser = nil
        self.authStatus = .unauthenticated
    }
    
    func resetDeviceAndKeychain() {
        signOut(clearKeys: true)
    }
    
    // MARK: - Account Deletion
    
    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = currentUser, let firebaseUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."])))
            return
        }
        
        let uid = firebaseUser.uid
        let userId = user.userID
        let username = user.effectiveUsername.lowercased()
        let tenantId = currentTenant?.tenantID ?? user.tenantID
        
        AppLogger.info("Starting complete account deletion for user: \(userId) (uid: \(uid))", category: .auth)
        
        let dispatchGroup = DispatchGroup()
        
        if !tenantId.isEmpty && !userId.isEmpty {
            dispatchGroup.enter()
            db.collection("tenants").document(tenantId).collection("users").document(userId).delete { err in
                if let err = err {
                    AppLogger.error("Failed to delete tenant user doc: \(err)", category: .auth)
                }
                dispatchGroup.leave()
            }
        }
        
        if !tenantId.isEmpty && !username.isEmpty {
            dispatchGroup.enter()
            db.collection("tenants").document(tenantId).collection("usernames").document(username).delete { err in
                if let err = err {
                    AppLogger.warning("Failed to delete username doc (non-blocking): \(err)", category: .auth)
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.enter()
        db.collection("users").document(uid).collection("private").document("data").delete { err in
            if let err = err {
                AppLogger.warning("Failed to delete private data doc: \(err)", category: .auth)
            }
            dispatchGroup.leave()
        }
        
        if let phrase = CryptoKeyManager.shared.getMnemonicPhrase(uid: uid),
           let keys = try? MnemonicManager.shared.deriveKeys(from: phrase) {
            dispatchGroup.enter()
            db.collection("recovery_vault").document(keys.recoveryHash).delete { err in
                if let err = err {
                    AppLogger.warning("Failed to delete recovery vault doc: \(err)", category: .auth)
                }
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.enter()
        db.collection("users").document(uid).delete { err in
            if let err = err {
                AppLogger.error("Failed to delete users/{uid} doc: \(err)", category: .auth)
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            CryptoKeyManager.shared.clearAllKeys()
            BlockManager.shared.clear()
            
            firebaseUser.delete { authErr in
                if let authErr = authErr {
                    AppLogger.error("Failed to delete Firebase Auth user: \(authErr)", category: .auth)
                    self.signOut(clearKeys: true)
                    completion(.failure(authErr))
                } else {
                    AppLogger.info("Successfully deleted Firebase Auth user and account data.", category: .auth)
                    self.signOut(clearKeys: true)
                    completion(.success(()))
                }
            }
        }
    }
    
    // MARK: - Profile Update (Display Name & Avatar)
    
    func patchDisplayName(newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            completion(.failure(NSError(domain: "ProfileError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Settings.editProfileEmptyError])))
            return
        }
        
        guard let _ = currentTenant, var user = currentUser else {
            completion(.failure(NSError(domain: "ProfileError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        CryptoKeyManager.shared.saveMyDisplayName(uid: user.uid, name: cleanName)
        
        DispatchQueue.main.async {
            user.displayName = cleanName
            self.currentUser = user
            completion(.success(()))
        }
    }
    
    func uploadAvatar(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, var user = currentUser else {
            completion(.failure(NSError(domain: "AvatarError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        AvatarRepository.shared.uploadAvatarByUserId(image: image, tenantId: tenantId, userId: userId) { result in
            switch result {
            case .success(let (updatedAt, nonce)):
                DispatchQueue.main.async {
                    user.avatarNonce = nonce
                    user.avatarUpdatedAt = Google_Protobuf_Timestamp(date: updatedAt)
                    self.currentUser = user
                    completion(.success(()))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteAvatar(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, var user = currentUser else {
            completion(.failure(NSError(domain: "AvatarError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        AvatarRepository.shared.deleteAvatarByUserId(tenantId: tenantId, userId: userId) { result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    user.avatarNonce = ""
                    user.clearAvatarUpdatedAt()
                    self.currentUser = user
                    completion(.success(()))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getCachedAvatar(userId: String, updatedAt: Date? = nil) -> UIImage? {
        return AvatarRepository.shared.getCachedAvatar(userId: userId, updatedAt: updatedAt)
    }
    
    func loadAvatarImage(userId: String, avatarNonce: String, updatedAt: Date?, completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let tenant = currentTenant else {
            completion(.failure(NSError(domain: "AvatarError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        AvatarRepository.shared.getAvatarByUserId(tenantId: tenant.tenantID, userId: userId, avatarNonce: avatarNonce, updatedAt: updatedAt, completion: completion)
    }
}

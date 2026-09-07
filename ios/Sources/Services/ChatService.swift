import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import SwiftProtobuf
import ULID
import CryptoKit

public enum AuthStatus {
    case unknown
    case unauthenticated
    case authenticated
}

public class ChatService: ObservableObject {
    public static let shared = ChatService()
    
    @Published var authStatus: AuthStatus = .unknown
    @Published var currentTenant: FriendsTenant? = PresetTenantConfig.defaultTenant {
        didSet {
            if let tenantId = currentTenant?.tenantID {
                BlockManager.shared.configure(tenantId: tenantId)
            }
        }
    }
    @Published var currentUser: FriendsPublicUserProfile? = nil
    @Published var friends: [FriendsPublicUserProfile] = []
    @Published var chats: [FriendsChatUIModel] = []
    @Published var messages: [String: [DecryptedMessage]] = [:] // chatId -> [DecryptedMessage]
    @Published var hasMoreMessages: [String: Bool] = [:] // chatId -> Bool
    @Published var isLoadingMoreMessages: [String: Bool] = [:] // chatId -> Bool
    @Published var readReceipts: [String: [String: FriendsReadReceipt]] = [:] // chatId -> [userId: FriendsReadReceipt]
    @Published var userReactions: [String: FriendsReactionType] = [:] // "\(chatId)_\(messageId)" -> reactionType
    @Published public var activeChatId: String? = nil
    @Published var groupMemberProfiles: [String: FriendsPublicUserProfile] = [:] // userId/uid -> profile
    
    private let db = Firestore.firestore()
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var messageLimits: [String: Int] = [:] // chatId -> Int
    private var readReceiptListeners: [String: ListenerRegistration] = [:]
    private var chatListener: ListenerRegistration?
    private var friendListener: ListenerRegistration?
    private var markAsReadDebounceWorkItems: [String: DispatchWorkItem] = [:]
    private var directSessionKeys: [String: SymmetricKey] = [:] // chatId -> SK_direct
    private var groupSessionKeys: [String: SymmetricKey] = [:] // "\(chatId)_\(keyVersion)" -> SK_group
    private var knownMessageIds: [String: Set<String>] = [:]

    
    private init() {
        if let defaultTid = currentTenant?.tenantID {
            BlockManager.shared.configure(tenantId: defaultTid)
        }
        checkAuthState()
    }
    
    /// ユーザーIDまたはUIDに対応するプロファイル（表示名・アバター）を返す（友達キャッシュ -> グループメンバーキャッシュの順で探索）
    func userProfile(for userIdOrUid: String) -> FriendsPublicUserProfile? {
        if let current = currentUser, (current.userID == userIdOrUid || current.uid == userIdOrUid) {
            return current
        }
        if let friend = friends.first(where: { $0.userID == userIdOrUid || $0.uid == userIdOrUid }) {
            return friend
        }
        if let profile = groupMemberProfiles[userIdOrUid] {
            return profile
        }
        return groupMemberProfiles.values.first(where: { $0.userID == userIdOrUid || $0.uid == userIdOrUid })
    }
    
    // MARK: - Initial Auth & Tenant Checking
    
    public func checkAuthState() {
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
            let err = NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."])
            completion(.failure(err))
            return
        }
        
        // 1. 既存リスナーの完全破棄
        chatListener?.remove()
        chatListener = nil
        friendListener?.remove()
        friendListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        readReceiptListeners.values.forEach { $0.remove() }
        readReceiptListeners.removeAll()
        
        // 2. メモリ上の一時状態をクリア
        DispatchQueue.main.async {
            self.chats.removeAll()
            self.friends.removeAll()
            self.messages.removeAll()
            self.readReceipts.removeAll()
            self.userReactions.removeAll()
            self.groupMemberProfiles.removeAll()
            self.directSessionKeys.removeAll()
            self.groupSessionKeys.removeAll()
            self.knownMessageIds.removeAll()
            self.messageLimits.removeAll()
            self.hasMoreMessages.removeAll()
            self.isLoadingMoreMessages.removeAll()
            self.activeChatId = nil
            self.currentUser = nil
        }
        
        // 3. テナント情報の取得・適用
        TenantRepository.shared.getTenantByTenantId(tenantId: tenantId) { [weak self] tenantResult in
            guard let self = self else { return }
            switch tenantResult {
            case .success(let tenant):
                DispatchQueue.main.async {
                    self.currentTenant = tenant
                    TenantManager.shared.setActiveTenantId(tenant.tenantID)
                }
                
                // 4. 当該テナントのユーザープロファイルを確認・ロード
                UserRepository.shared.getUserProfileByUid(tenantId: tenant.tenantID, uid: authUid) { [weak self] userResult in
                    guard let self = self else { return }
                    switch userResult {
                    case .success(let profile):
                        DispatchQueue.main.async {
                            self.currentUser = profile
                            self.authStatus = .authenticated
                            self.watchChats()
                            self.watchFriends()
                            TenantManager.shared.refreshUnreadCounts()
                            completion(.success(tenant))
                        }
                    case .failure:
                        // 未参加テナントの場合: 既存の表示名と公開鍵を引き継いで参加プロファイルを作成
                        let savedName = CryptoKeyManager.shared.getMyDisplayName(uid: authUid) ?? "ユーザー"
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
                    if self.authStatus == .authenticated {
                        self.watchChats()
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
    
    public func signInAnonymously(displayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
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
            
            let name = displayName.isEmpty ? "ゲストユーザー" : displayName
            self.handleAuthenticatedUser(user: user, preferredDisplayName: name, accountType: .anonymous, completion: completion)
        }
    }
    
    // MARK: - Authenticated User Profile Handler
    
    private func handleAuthenticatedUser(
        user: User,
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
                        finalDisplayName = email.components(separatedBy: "@").first ?? "ユーザー"
                    } else {
                        finalDisplayName = (accountType == .anonymous) ? "ゲストユーザー" : "Friendsユーザー"
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
                self.watchChats()
                self.watchFriends()
                completion(.success(()))
            }
        }
    }
    
    // MARK: - Recovery Phrase & Private Key Backup
    
    /// 秘密鍵をふっかつのじゅもん（Mnemonic Phrase）で暗号化し、Keychain および Firestore /users/{uid}/private/data に保存する
    public func backupPrivateKeyWithRecoveryPhrase(
        uid: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        words: [String]? = nil,
        completion: ((Result<[String], Error>) -> Void)? = nil
    ) {
        do {
            let phrase: [String]
            if let existingWords = words, MnemonicManager.shared.validateMnemonic(words: existingWords) {
                phrase = existingWords
            } else if let savedWords = CryptoKeyManager.shared.getMnemonicPhrase(uid: uid) {
                phrase = savedWords
            } else {
                phrase = try MnemonicManager.shared.generateMnemonic(language: .japanese)
            }
            
            // Keychain に保存
            try CryptoKeyManager.shared.saveMnemonicPhrase(uid: uid, words: phrase)
            
            // 鍵導出 & 秘密鍵暗号化
            let (_, _, privEncKey, recoveryHash) = try MnemonicManager.shared.deriveKeys(from: phrase)
            let (ciphertext, nonce) = try MnemonicManager.shared.encryptPrivateKey(privateKey, using: privEncKey)
            
            // Firestore /users/{uid}/private/data に保存
            var privateData = FriendsUserPrivateData()
            privateData.uid = uid
            privateData.recoveryHash = recoveryHash
            privateData.encryptedPrivateKey = ciphertext
            privateData.nonce = nonce
            privateData.updatedAt = Google_Protobuf_Timestamp(date: Date())
            
            UserRepository.shared.setUserPrivateDataByUid(uid: uid, data: privateData) { result in
                switch result {
                case .success:
                    // 端末復元ボルト (/recovery_vault/{recoveryHash}) にも同時に保存
                    UserRepository.shared.saveRecoveryVaultRecord(
                        recoveryHash: recoveryHash,
                        uid: uid,
                        encryptedPrivateKey: ciphertext,
                        nonce: nonce
                    ) { vaultResult in
                        switch vaultResult {
                        case .success:
                            AppLogger.info("Successfully backed up private key, recovery hash, and vault for uid: \(uid)", category: .crypto)
                            completion?(.success(phrase))
                        case .failure(let vaultErr):
                            AppLogger.warning("Failed to save recovery vault (non-blocking): \(vaultErr)", category: .crypto)
                            completion?(.success(phrase))
                        }
                    }
                case .failure(let err):
                    AppLogger.error("Failed to save private data backup to Firestore: \(err)", category: .crypto)
                    completion?(.failure(err))
                }
            }
        } catch {
            AppLogger.error("Failed to generate recovery backup: \(error)", category: .crypto)
            completion?(.failure(error))
        }
    }
    
    /// ふっかつのじゅもん（Mnemonic Phrase）を強制再作成し、現在の秘密鍵を暗号化してKeychainおよびFirestoreに上書き保存する
    public func regenerateRecoveryPhrase(
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        let uid = currentUser.uid
        guard let privKey = CryptoKeyManager.shared.getPrivateKey(uid: uid) else {
            completion(.failure(NSError(domain: "ChatService", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
    
    public func restoreWithRecoveryPhrase(words: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        guard MnemonicManager.shared.validateMnemonic(words: words) else {
            completion(.failure(NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Auth.recoveryInvalidPhrase])))
            return
        }
        
        // 1. もし既にログイン中のユーザーが存在する場合（同一UIDでの鍵復旧）
        if let currentUser = Auth.auth().currentUser {
            restoreKeysForAuthenticatedUser(user: currentUser, words: words, completion: completion)
            return
        }
        
        // 2. 未ログイン状態からの完全復旧（Cloudflare Workers による Custom Token 発行 + 元のアカウントでログイン）
        guard let baseURL = RecoveryConfig.workersBaseURL else {
            AppLogger.error("Workers API URL not configured. Tenant 2D code must be scanned first.", category: .repo)
            completion(.failure(NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.tenantNotConfigured])))
            return
        }
        
        do {
            let (_, _, privEncKey, recoveryHash) = try MnemonicManager.shared.deriveKeys(from: words)
            
            // Cloudflare Workers API へリクエスト
            let url = baseURL.appendingPathComponent("api/v1/auth/recover-anonymous")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let requestBody = ["recoveryHash": recoveryHash]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    AppLogger.error("Recovery API request failed: \(error)", category: .repo)
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    let err = NSError(domain: "ChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                
                guard let data = data else {
                    let err = NSError(domain: "ChatService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.dataNotFound])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                
                guard httpResponse.statusCode == 200 else {
                    let errorMessage: String
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let msg = json["error"] as? String {
                        errorMessage = msg
                    } else if httpResponse.statusCode == 404 {
                        errorMessage = L10n.Error.Recovery.dataNotFound
                    } else {
                        errorMessage = L10n.Error.unknown
                    }
                    let err = NSError(domain: "ChatService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let customToken = json["customToken"] as? String,
                          let recoveredUid = json["uid"] as? String,
                          let encryptedPrivateKey = json["encryptedPrivateKey"] as? String,
                          let nonce = json["nonce"] as? String else {
                        throw NSError(domain: "ChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Recovery.dataNotFound])
                    }
                    
                    // 3. 元の UID に対応する Firebase Custom Token でサインイン
                    Auth.auth().signIn(withCustomToken: customToken) { authResult, signInError in
                        if let signInError = signInError {
                            AppLogger.error("Failed to sign in with custom token: \(signInError)", category: .auth)
                            DispatchQueue.main.async { completion(.failure(signInError)) }
                            return
                        }
                        
                        do {
                            // 4. 暗号化秘密鍵の復号
                            let restoredPrivateKey = try MnemonicManager.shared.decryptPrivateKey(
                                ciphertext: encryptedPrivateKey,
                                nonce: nonce,
                                using: privEncKey
                            )
                            
                            // 5. ローカル Keychain への保存
                            try CryptoKeyManager.shared.savePrivateKey(uid: recoveredUid, privateKey: restoredPrivateKey)
                            try CryptoKeyManager.shared.saveMnemonicPhrase(uid: recoveredUid, words: words)
                            
                            // 6. テナントプロファイル読込とリスナー再接続
                            self.fetchDefaultTenant { tenantResult in
                                switch tenantResult {
                                case .success(let tenant):
                                    DispatchQueue.main.async {
                                        self.currentTenant = tenant
                                        self.loadUserProfile(uid: recoveredUid, tenantId: tenant.tenantID)
                                        completion(.success(()))
                                    }
                                case .failure:
                                    DispatchQueue.main.async {
                                        self.loadUserProfile(uid: recoveredUid, tenantId: PresetTenantConfig.tenantId)
                                        completion(.success(()))
                                    }
                                }
                            }
                        } catch {
                            AppLogger.error("Failed to decrypt restored private key: \(error)", category: .crypto)
                            DispatchQueue.main.async { completion(.failure(error)) }
                        }
                    }
                } catch {
                    AppLogger.error("Failed to parse recovery response: \(error)", category: .crypto)
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }.resume()
        } catch {
            AppLogger.error("Failed to derive recovery keys: \(error)", category: .crypto)
            completion(.failure(error))
        }
    }
    
    private func restoreKeysForAuthenticatedUser(user: FirebaseAuth.User, words: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        UserRepository.shared.getUserPrivateDataByUid(uid: user.uid) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let privateData):
                do {
                    let (_, _, privEncKey, recoveryHash) = try MnemonicManager.shared.deriveKeys(from: words)
                    if !privateData.recoveryHash.isEmpty && privateData.recoveryHash != recoveryHash {
                        let err = NSError(domain: "ChatService", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Auth.recoveryInvalidPhrase])
                        DispatchQueue.main.async { completion(.failure(err)) }
                        return
                    }
                    let restoredPrivateKey = try MnemonicManager.shared.decryptPrivateKey(
                        ciphertext: privateData.encryptedPrivateKey,
                        nonce: privateData.nonce,
                        using: privEncKey
                    )
                    
                    // ローカル Keychain に保存
                    try CryptoKeyManager.shared.savePrivateKey(uid: user.uid, privateKey: restoredPrivateKey)
                    try CryptoKeyManager.shared.saveMnemonicPhrase(uid: user.uid, words: words)
                    
                    let tenantId = self.currentTenant?.tenantID ?? PresetTenantConfig.tenantId
                    DispatchQueue.main.async {
                        self.loadUserProfile(uid: user.uid, tenantId: tenantId)
                        completion(.success(()))
                    }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            case .failure(let err):
                DispatchQueue.main.async { completion(.failure(err)) }
            }
        }
    }
    
    // MARK: - Security Reset (Key Rotation & Backup Update)
    
    /// セキュリティリセット: 端末の鍵ペアを再生成し、公開鍵を更新した上で既存の「ふっかつのじゅもん」でバックアップを再暗号化更新する
    public func performSecurityReset(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let currentUser = currentUser, let authUid = Auth.auth().currentUser?.uid else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        do {
            // 1. 秘密鍵の再生成
            let newPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            let newPublicKeyBase64 = newPrivateKey.publicKey.rawRepresentation.base64EncodedString()
            try CryptoKeyManager.shared.savePrivateKey(uid: authUid, privateKey: newPrivateKey)
            
            // 2. プロファイルの公開鍵更新
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
                    // 3. ふっかつのじゅもんによる暗号化バックアップを自動更新
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
    
    // MARK: - Load User Profile from Firestore
    
    private func loadUserProfile(uid: String, tenantId: String) {
        UserRepository.shared.getUserProfileByUid(tenantId: tenantId, uid: uid) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let userProfile):
                // 鍵ペアの同期確認
                let keypair = try? CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
                let localPublicKey = keypair?.publicKeyBase64 ?? ""
                var profile = userProfile
                if !localPublicKey.isEmpty && profile.publicKey != localPublicKey {
                    profile.publicKey = localPublicKey
                    UserRepository.shared.createOrUpdateUserProfile(tenantId: tenantId, user: profile) { _ in }
                }
                
                // 🔐 自身の表示名を端末 Keychain から復元
                if let savedName = CryptoKeyManager.shared.getMyDisplayName(uid: uid), !savedName.isEmpty {
                    profile.displayName = savedName
                }
                
                DispatchQueue.main.async {
                    self.currentUser = profile
                    self.authStatus = .authenticated
                    self.watchChats()
                    self.watchFriends()
                }
            case .failure:
                DispatchQueue.main.async {
                    self.authStatus = .unauthenticated
                }
            }
        }
    }
    
    // MARK: - Sign Out & Device Reset
    
    /// ログアウトおよび端末 Keychain 暗号鍵・ローカル状態の完全消去
    public func signOut(clearKeys: Bool = true) {
        if clearKeys {
            CryptoKeyManager.shared.clearAllKeys()
        }
        
        try? Auth.auth().signOut()
        chatListener?.remove()
        friendListener?.remove()
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        readReceiptListeners.values.forEach { $0.remove() }
        readReceiptListeners.removeAll()
        
        DispatchQueue.main.async {
            self.directSessionKeys.removeAll()
            self.knownMessageIds.removeAll()
            self.messageLimits.removeAll()
            self.hasMoreMessages.removeAll()
            self.isLoadingMoreMessages.removeAll()
            self.currentUser = nil
            self.friends = []
            self.chats = []
            self.messages = [:]
            self.readReceipts = [:]
            self.userReactions = [:]
            self.activeChatId = nil
            self.authStatus = .unauthenticated
        }
    }
    
    /// 端末データおよび Keychain の完全リセット（ログイン画面からも利用可能）
    public func resetDeviceAndKeychain() {
        signOut(clearKeys: true)
    }
    
    // MARK: - Account Deletion (Apple Guideline 5.1.1(v))
    
    /// アカウントの完全消去（Firestore ドキュメント、端末内 Keychain 鍵、Firebase Auth ユーザーの消去）
    public func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let user = currentUser, let firebaseUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."])))
            return
        }
        
        let uid = firebaseUser.uid
        let userId = user.userID
        let username = user.effectiveUsername.lowercased()
        let tenantId = currentTenant?.tenantID ?? user.tenantID
        
        AppLogger.info("Starting complete account deletion for user: \(userId) (uid: \(uid))", category: .auth)
        
        let dispatchGroup = DispatchGroup()
        
        // 1. テナント内ユーザープロファイル削除: /tenants/{tenantId}/users/{userId}
        if !tenantId.isEmpty && !userId.isEmpty {
            dispatchGroup.enter()
            db.collection("tenants").document(tenantId).collection("users").document(userId).delete { err in
                if let err = err {
                    AppLogger.error("Failed to delete tenant user doc: \(err)", category: .auth)
                }
                dispatchGroup.leave()
            }
        }
        
        // 2. ユーザーネーム予約インデックス削除: /tenants/{tenantId}/usernames/{username}
        if !tenantId.isEmpty && !username.isEmpty {
            dispatchGroup.enter()
            db.collection("tenants").document(tenantId).collection("usernames").document(username).delete { err in
                if let err = err {
                    AppLogger.warning("Failed to delete username doc (non-blocking): \(err)", category: .auth)
                }
                dispatchGroup.leave()
            }
        }
        
        // 3. 秘密鍵バックアップデータ削除: /users/{uid}/private/data
        dispatchGroup.enter()
        db.collection("users").document(uid).collection("private").document("data").delete { err in
            if let err = err {
                AppLogger.warning("Failed to delete private data doc: \(err)", category: .auth)
            }
            dispatchGroup.leave()
        }
        
        // 4. 復旧ボルト削除: recoveryHash があれば
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
        
        // 5. 全域ユーザー情報削除: /users/{uid}
        dispatchGroup.enter()
        db.collection("users").document(uid).delete { err in
            if let err = err {
                AppLogger.error("Failed to delete users/{uid} doc: \(err)", category: .auth)
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) {
            // 6. 端末内 Keychain の完全消去 & BlockManager クリア
            CryptoKeyManager.shared.clearAllKeys()
            BlockManager.shared.clear()
            
            // 7. Firebase Auth ユーザーの削除
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
    
    // MARK: - Friends Management & Listeners
    
    public func watchFriends() {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        friendListener?.remove()
        friendListener = FriendRepository.shared.watchFriendsByUserId(tenantId: tenantId, userId: userId, myUid: user.uid) { [weak self] loadedFriends in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.friends = loadedFriends
                
                let currentUserId = user.userID
                for friend in loadedFriends {
                    let dmChatId = "dm_" + [currentUserId, friend.userID].sorted().joined(separator: "_")
                    self.watchMessages(chatId: dmChatId)
                    self.watchReadReceipts(chatId: dmChatId)
                }
                
                // 初回/変更検知時に友達プロファイル（アバターメタデータ含む）を最新化
                self.listFriendsProfiles()
            }
        }
    }

    
    
    func createFriend(
        from payload: FriendsFriendInvitationPayload,
        explicitPasscode: String? = nil,
        completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void
    ) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion(.failure(NSError(domain: "FriendError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        // 1. Validate Tenant Mismatch
        guard payload.tenantID == tenant.tenantID else {
            completion(.failure(NSError(domain: "FriendError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.tenantMismatch])))
            return
        }
        
        // 2. Validate Self-Addition
        guard payload.userID != user.userID && payload.uid != user.uid else {
            completion(.failure(NSError(domain: "FriendError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.selfAdd])))
            return
        }
        
        // 3. Validate Passcode
        let passcodeToVerify = explicitPasscode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? payload.passcode
        let isPasscodeValid = FriendPasscodeGenerator.validatePasscode(
            code: passcodeToVerify,
            uid: payload.uid,
            tenantId: payload.tenantID
        )
        
        guard isPasscodeValid else {
            completion(.failure(NSError(domain: "FriendError", code: 403, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.passcodeExpired])))
            return
        }
        
        let friendProfile = FriendsPublicUserProfile(
            userID: payload.userID,
            uid: payload.uid,
            tenantID: payload.tenantID,
            displayName: payload.displayName,
            publicKey: payload.publicKey
        )
        
        FriendRepository.shared.createFriendBidirectional(tenantId: tenant.tenantID, myUser: user, friendUser: friendProfile) { [weak self] result in
            guard let self = self else { return }
            if case .failure(let err) = result {
                completion(.failure(err))
                return
            }
            
            DispatchQueue.main.async {
                if !self.friends.contains(where: { $0.userID == friendProfile.userID }) {
                    self.friends.insert(friendProfile, at: 0)
                }
                completion(.success(friendProfile))
            }
        }
    }
    
    func addFriendByUserId(
        targetUserId: String,
        passcode: String,
        completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void
    ) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion(.failure(NSError(domain: "FriendError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let cleanUserId = targetUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPasscode = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Prevent self-add
        guard cleanUserId != user.userID else {
            completion(.failure(NSError(domain: "FriendError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.selfAdd])))
            return
        }
        
        // 2. Fetch target user document from Firestore
        db.collection("tenants").document(tenant.tenantID)
            .collection("users").document(cleanUserId)
            .getDocument { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let doc = documentSnapshot, doc.exists, let data = doc.data() else {
                    completion(.failure(NSError(domain: "FriendError", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.userNotFound])))
                    return
                }
                
                let targetUid = data["uid"] as? String ?? ""
                let targetUsername = data["username"] as? String ?? cleanUserId
                // 初期表示名は公開ハンドル名（username）を使用（最新の表示名は成立後のE2EEメッセージで伝播）
                let targetDisplayName = targetUsername
                let targetPublicKey = data["publicKey"] as? String ?? ""
                
                guard !targetUid.isEmpty else {
                    completion(.failure(NSError(domain: "FriendError", code: 404, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.userNotFound])))
                    return
                }
                
                var payload = FriendsFriendInvitationPayload()
                payload.type = "friend_invite"
                payload.version = 1
                payload.tenantID = tenant.tenantID
                payload.userID = cleanUserId
                payload.uid = targetUid
                payload.displayName = targetDisplayName
                payload.publicKey = targetPublicKey
                payload.passcode = cleanPasscode
                payload.timestamp = Int64(Date().timeIntervalSince1970)
                
                self.createFriend(from: payload, explicitPasscode: cleanPasscode, completion: completion)
            }
    }
    
    // MARK: - Add Friend By Username (ユーザー名/ID検索)
    
    func addFriendByUsername(
        targetUsername: String,
        passcode: String,
        completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void
    ) {
        guard let tenant = currentTenant else {
            completion(.failure(NSError(domain: "FriendError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        let cleanInput = targetUsername.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        UserRepository.shared.getUserProfileByUsername(tenantId: tenant.tenantID, username: cleanInput) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let targetProfile):
                self.addFriendByUserId(targetUserId: targetProfile.userID, passcode: passcode, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Update Username (プロフィール設定からユーザー名変更)
    
    func updateUsername(newUsername: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion(.failure(NSError(domain: "UserError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        let cleanUsername = newUsername.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        
        UserRepository.shared.updateUsername(
            tenantId: tenant.tenantID,
            userId: user.userID,
            uid: user.uid,
            oldUsername: user.username,
            newUsername: cleanUsername
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.currentUser?.username = cleanUsername
                }
            case .failure:
                break
            }
            completion(result)
        }
    }
    
    /// 友達のカスタム表示名を自身の秘密鍵 (Personal Key) で暗号化して更新する
    public func updateFriendDisplayName(
        friendUserId: String,
        newDisplayName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication required"])))
            return
        }
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Display name cannot be empty"])))
            return
        }
        
        FriendRepository.shared.updateFriendDisplayName(
            tenantId: tenant.tenantID,
            userId: user.userID,
            uid: user.uid,
            friendUserId: friendUserId,
            newDisplayName: trimmed
        ) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if case .success = result {
                    // ローカルの friends 配列の表示名を即時更新
                    if let idx = self.friends.firstIndex(where: { $0.userID == friendUserId }) {
                        var updated = self.friends[idx]
                        updated.displayName = trimmed
                        self.friends[idx] = updated
                    }
                }
                completion(result)
            }
        }
    }
    
    // MARK: - Firestore Listeners
    
    public func watchChats() {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        chatListener?.remove()
        chatListener = ChatRepository.shared.watchChatsByUserId(tenantId: tenantId, userId: userId) { [weak self] newChats in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.chats = newChats
            }
            for chat in newChats {
                self.watchMessages(chatId: chat.chatID)
                self.watchReadReceipts(chatId: chat.chatID)
            }
        }
    }
    
    // MARK: - Direct & Group Session Key Helpers
    
    /// 1:1 チャットの相手ユーザーの公開鍵から SK_direct セッション鍵を取得または導出する
    private func getDirectSessionKey(chatId: String, tenantId: String, peerUserId: String? = nil, completion: @escaping (SymmetricKey?) -> Void) {
        if let cached = directSessionKeys[chatId] {
            completion(cached)
            return
        }
        
        guard let myUid = currentUser?.uid else {
            completion(nil)
            return
        }
        
        // 1. friends キャッシュから相手の公開鍵を探索
        var resolvedPeerId = peerUserId ?? ""
        if resolvedPeerId.isEmpty && chatId.hasPrefix("dm_") {
            let rawStr = String(chatId.dropFirst(3))
            let parts = rawStr.components(separatedBy: "_u_")
            if parts.count == 2 {
                let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                let userB = "u_" + parts[1]
                resolvedPeerId = [userA, userB].first(where: { $0 != currentUser?.userID }) ?? ""
            }
        }
        let targetPeerId = resolvedPeerId
        
        if let friend = friends.first(where: { $0.userID == targetPeerId }), !friend.publicKey.isEmpty {
            if let key = try? CryptoKeyManager.shared.deriveDirectSessionKey(myUid: myUid, peerPublicKeyBase64: friend.publicKey, tenantId: tenantId) {
                self.directSessionKeys[chatId] = key
                completion(key)
                return
            }
        }
        
        // 2. Firestore から相手ユーザーのドキュメントを直接取得して公開鍵を読み出す
        if !targetPeerId.isEmpty {
            UserRepository.shared.getUserProfileByUserId(tenantId: tenantId, userId: targetPeerId) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let userProfile):
                    if !userProfile.publicKey.isEmpty,
                       let key = try? CryptoKeyManager.shared.deriveDirectSessionKey(myUid: myUid, peerPublicKeyBase64: userProfile.publicKey, tenantId: tenantId) {
                        self.directSessionKeys[chatId] = key
                        completion(key)
                        return
                    }
                case .failure:
                    break
                }
                
                // 3. フォールバック: テナントマスターキー (MK_T)
                let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
                completion(fallbackKey)
            }
        } else {
            let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
            completion(fallbackKey)
        }
    }
    
    /// グループ会話鍵 (SK_group) を KeyBucket またはキャッシュから取得する (Forward Secrecy 対応)
    private func getGroupSessionKey(chatId: String, tenantId: String, keyVersion: String = "v_1", completion: @escaping (SymmetricKey?) -> Void) {
        let cacheKey = "\(chatId)_\(keyVersion)"
        if let cached = groupSessionKeys[cacheKey] {
            completion(cached)
            return
        }
        
        guard let myUid = currentUser?.uid, let myUserId = currentUser?.userID else {
            let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
            completion(fallbackKey)
            return
        }
        
        KeyBucketRepository.shared.getKeyBucket(tenantId: tenantId, chatId: chatId, keyVersion: keyVersion) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let bucket):
                // 自分の userId (u_...) に割り当てられた暗号化グループ鍵を探索
                if let encryptedKey = bucket.encryptedGroupKeys[myUserId] {
                    // 作成者（自分自身またはグループ内の公開鍵を持つ相手）の公開鍵で復号
                    // プリセット・フォールバックとして自分の鍵ペアまたはMK_Tを試みる
                    if let myPubKey = CryptoKeyManager.shared.getPublicKeyBase64(uid: myUid),
                       let groupKey = try? CryptoKeyManager.shared.decryptGroupKey(
                        encryptedGroupKeyBase64: encryptedKey,
                        peerPublicKeyBase64: myPubKey,
                        myUid: myUid,
                        tenantId: tenantId
                       ) {
                        self.groupSessionKeys[cacheKey] = groupKey
                        completion(groupKey)
                        return
                    }
                }
                let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
                completion(fallbackKey)
            case .failure:
                let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
                completion(fallbackKey)
            }
        }
    }
    
    public func watchMessages(chatId: String, limit: Int? = nil) {
        guard let tenant = currentTenant else { return }
        let tenantId = tenant.tenantID
        
        let targetLimit = limit ?? messageLimits[chatId] ?? 30
        messageLimits[chatId] = targetLimit
        
        // 1:1 DM チャットの場合、親ドキュメントが未作成なら初期化を試みる
        if chatId.hasPrefix("dm_"), let currentUserId = currentUser?.userID {
            ChatRepository.shared.ensureDirectChat(tenantId: tenantId, chatId: chatId, currentUserId: currentUserId)
        }
        
        // 既存リスナーの安全な差し替え
        if limit != nil || messageListeners[chatId] == nil {
            messageListeners[chatId]?.remove()
            
            let listener = MessageRepository.shared.watchMessagesByChatId(tenantId: tenantId, chatId: chatId, limit: targetLimit) { [weak self] rawMessages in
                guard let self = self else { return }
                
                let previouslyKnownIds = self.knownMessageIds[chatId]
                let isInitialLoad = (previouslyKnownIds == nil)
                let currentMessageIds = Set(rawMessages.map { $0.messageID })
                self.knownMessageIds[chatId] = currentMessageIds
                
                if rawMessages.isEmpty {
                    DispatchQueue.main.async {
                        if self.messages[chatId]?.isEmpty ?? true {
                            self.messages[chatId] = []
                        }
                        self.hasMoreMessages[chatId] = false
                        self.isLoadingMoreMessages[chatId] = false
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.hasMoreMessages[chatId] = (rawMessages.count >= targetLimit)
                    self.isLoadingMoreMessages[chatId] = false
                }
                
                let getKeyHandler: (@escaping (SymmetricKey?) -> Void) -> Void = { handler in
                    if chatId.hasPrefix("gm_") {
                        let targetKeyVersion = rawMessages.last?.keyVersion ?? "v_1"
                        self.getGroupSessionKey(chatId: chatId, tenantId: tenantId, keyVersion: targetKeyVersion, completion: handler)
                    } else {
                        self.getDirectSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
                    }
                }
                
                getKeyHandler { sessionKey in
                    var newDecryptedMessages: [DecryptedMessage] = []
                    var newlyReceivedMessagesToNotify: [DecryptedMessage] = []
                    
                    for msg in rawMessages {
                        let ciphertext = msg.encryptedPayload.ciphertext
                        let nonce = msg.encryptedPayload.nonce
                        
                        // メッセージの keyVersion に応じた会話鍵を探索
                        var effectiveKey = sessionKey
                        if chatId.hasPrefix("gm_") && !msg.keyVersion.isEmpty {
                            let msgCacheKey = "\(chatId)_\(msg.keyVersion)"
                            if let cachedKey = self.groupSessionKeys[msgCacheKey] {
                                effectiveKey = cachedKey
                            }
                        }
                        
                        // 端末内ローカル復号 (E2EE)
                        var decryptedText = ""
                        if let key = effectiveKey, !ciphertext.isEmpty, !nonce.isEmpty {
                            if let dec = try? CryptoKeyManager.shared.decryptDirectMessage(ciphertext: ciphertext, nonce: nonce, sessionKey: key) {
                                decryptedText = dec
                            } else if let decWithTenant = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: ciphertext, nonce: nonce, tenantId: tenantId) {
                                decryptedText = decWithTenant
                            }
                        } else if !ciphertext.isEmpty, !nonce.isEmpty {
                            if let decWithTenant = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: ciphertext, nonce: nonce, tenantId: tenantId) {
                                decryptedText = decWithTenant
                            }
                        }
                        
                        // 送信者名の解決 (自分 -> 友達キャッシュ -> グループメンバーキャッシュ)
                        var senderDisplayName = "送信者"
                        let isFromMe = (msg.senderID == self.currentUser?.uid || msg.senderID == self.currentUser?.userID)
                        if isFromMe {
                            senderDisplayName = self.currentUser?.displayName ?? "自分"
                        } else if let friend = self.friends.first(where: { $0.uid == msg.senderID || $0.userID == msg.senderID }) {
                            senderDisplayName = friend.displayName
                        } else if let member = self.userProfile(for: msg.senderID) {
                            senderDisplayName = member.displayName
                        }
                        
                        let myReaction = self.userReactions["\(chatId)_\(msg.messageID)"]
                        let decryptedMsg = DecryptedMessage(
                            message: msg,
                            senderName: senderDisplayName,
                            decryptedText: decryptedText,
                            myReaction: myReaction
                        )
                        newDecryptedMessages.append(decryptedMsg)
                        
                        // 初回同期以降で新しく到着した他者からのメッセージを抽出
                        if !isInitialLoad, let prevIds = previouslyKnownIds, !prevIds.contains(msg.messageID), !isFromMe {
                            newlyReceivedMessagesToNotify.append(decryptedMsg)
                        }
                        
                        // 【ハイブリッド同期 第2層】会話・メッセージ受信時に送信者の最新プロファイルをオンデマンド同期
                        if !isFromMe {
                            let senderId = msg.senderID
                            if let friendIdx = self.friends.firstIndex(where: { $0.uid == senderId || $0.userID == senderId }) {
                                let friendUserId = self.friends[friendIdx].userID
                                FriendRepository.shared.listFriendsProfilesByUserIds(tenantId: tenantId, friendUserIds: [friendUserId]) { res in
                                    if case .success(let map) = res, let info = map[friendUserId] {
                                        DispatchQueue.main.async {
                                            if let idx = self.friends.firstIndex(where: { $0.userID == friendUserId }) {
                                                var updated = self.friends[idx]
                                                var changed = false
                                                if !info.displayName.isEmpty && info.displayName != updated.displayName {
                                                    updated.displayName = info.displayName
                                                    changed = true
                                                }
                                                if info.avatarNonce != updated.avatarNonce || info.avatarUpdatedAt != updated.avatarUpdatedDate {
                                                    updated.avatarNonce = info.avatarNonce
                                                    if let date = info.avatarUpdatedAt {
                                                        updated.avatarUpdatedAt = Google_Protobuf_Timestamp(date: date)
                                                    } else {
                                                        updated.clearAvatarUpdatedAt()
                                                    }
                                                    changed = true
                                                }
                                                if changed {
                                                    self.friends[idx] = updated
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                // グループメンバー（友達未登録）のプロファイルオンデマンド取得
                                FriendRepository.shared.listFriendsProfilesByUserIds(tenantId: tenantId, friendUserIds: [senderId]) { res in
                                    if case .success(let map) = res, let info = map[senderId] {
                                        DispatchQueue.main.async {
                                            var profileObj = FriendsPublicUserProfile()
                                            profileObj.userID = senderId
                                            profileObj.uid = senderId
                                            profileObj.tenantID = tenantId
                                            profileObj.displayName = info.displayName.isEmpty ? senderId : info.displayName
                                            profileObj.role = .member
                                            profileObj.accountType = .persistent
                                            profileObj.avatarNonce = info.avatarNonce
                                            if let date = info.avatarUpdatedAt {
                                                profileObj.avatarUpdatedAt = Google_Protobuf_Timestamp(date: date)
                                            }
                                            profileObj.username = info.username
                                            
                                            self.groupMemberProfiles[senderId] = profileObj
                                            if let currentMsgs = self.messages[chatId] {
                                                var updatedMsgs = currentMsgs
                                                var modified = false
                                                for i in 0..<updatedMsgs.count {
                                                    if updatedMsgs[i].senderID == senderId && (updatedMsgs[i].senderName == "送信者" || updatedMsgs[i].senderName.isEmpty) {
                                                        updatedMsgs[i].senderName = info.displayName
                                                        modified = true
                                                    }
                                                }
                                                if modified {
                                                    self.messages[chatId] = updatedMsgs
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    
                    DispatchQueue.main.async {
                        self.messages[chatId] = newDecryptedMessages
                        
                        // チャット一覧の最新メッセージ・時刻をローカル復号メッセージから同期更新
                        if let lastDec = newDecryptedMessages.last, let chatIdx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                            let oldChat = self.chats[chatIdx]
                            self.chats[chatIdx] = FriendsChatUIModel(
                                chat: oldChat.chat,
                                title: oldChat.title,
                                lastMessage: lastDec.decryptedText,
                                lastMessageAt: lastDec.createdDate,
                                unreadCount: oldChat.unreadCount
                            )
                        }
                        
                        // トースト通知の発火 (該当チャット画面を開いていない場合)
                        if self.activeChatId != chatId {
                            let chatModel = self.chats.first(where: { $0.chatID == chatId })
                            let isGroup = chatModel?.chatType == .group
                            let toastTitle = isGroup ? (chatModel?.displayTitle ?? "グループ") : nil
                            
                            for newMsg in newlyReceivedMessagesToNotify {
                                let senderFriend = self.friends.first(where: { $0.uid == newMsg.senderID || $0.userID == newMsg.senderID })
                                let senderUserId = senderFriend?.userID ?? newMsg.senderID
                                let avatarNonce = senderFriend?.avatarNonce ?? ""
                                let avatarUpdatedAt = senderFriend?.avatarUpdatedDate
                                let displaySenderName = isGroup ? "\(newMsg.senderName) (\(toastTitle ?? ""))" : newMsg.senderName
                                
                                ToastNotificationManager.shared.show(
                                    chatId: chatId,
                                    senderId: senderUserId,
                                    senderName: displaySenderName,
                                    messageText: newMsg.decryptedText,
                                    messageId: newMsg.id,
                                    isGroup: isGroup,
                                    avatarNonce: avatarNonce,
                                    avatarUpdatedAt: avatarUpdatedAt
                                )
                            }
                        }
                    }
                }
            }
            
            messageListeners[chatId] = listener
        }
    }
    
    /// 過去メッセージのオンデマンド遡りロード (+30件)
    public func loadMoreMessages(chatId: String) {
        guard hasMoreMessages[chatId] == true else { return }
        guard isLoadingMoreMessages[chatId] != true else { return }
        
        let currentLimit = messageLimits[chatId] ?? 30
        let newLimit = currentLimit + 30
        
        DispatchQueue.main.async {
            self.isLoadingMoreMessages[chatId] = true
        }
        watchMessages(chatId: chatId, limit: newLimit)
    }
    
    // MARK: - Send Message to Firestore (Zero-Plaintext E2EE)
    
    public func createMessage(chatId: String, text: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Text is empty"])))
            return
        }
        guard let tenant = currentTenant else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current tenant is nil"])))
            return
        }
        guard let user = currentUser else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current user is nil"])))
            return
        }
        
        let tenantId = tenant.tenantID
        let messageId = "m_\(ULID().ulidString)"
        
        // メンバーリストの導出 (DMの場合は chatId から 2名の userId を抽出し昇順ソート)
        var members: [String] = []
        if chatId.hasPrefix("dm_") {
            let rawStr = String(chatId.dropFirst(3))
            // dm_u_12345678_u_87654321 から ["u_12345678", "u_87654321"] を抽出
            let parts = rawStr.components(separatedBy: "_u_")
            if parts.count == 2 {
                let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                let userB = "u_" + parts[1]
                members = [userA, userB].sorted()
            }
        } else if let existingChat = chats.first(where: { $0.chatID == chatId }) {
            members = existingChat.chat.members
        }
        
        let getKeyHandler: (@escaping (SymmetricKey?) -> Void) -> Void = { handler in
            if chatId.hasPrefix("gm_") {
                self.getGroupSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
            } else {
                self.getDirectSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
            }
        }
        
        getKeyHandler { sessionKey in
            var ciphertext = ""
            var nonce = ""
            
            if let key = sessionKey {
                if let enc = try? CryptoKeyManager.shared.encryptDirectMessage(plainText: trimmed, sessionKey: key) {
                    ciphertext = enc.ciphertext
                    nonce = enc.nonce
                }
            }
            
            // フォールバック: MK_T で暗号化
            if ciphertext.isEmpty {
                if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: trimmed, tenantId: tenantId) {
                    ciphertext = enc.encryptedData
                    nonce = enc.nonce
                }
            }
            
            let pbMsg = FriendsMessage(
                messageID: messageId,
                tenantID: tenantId,
                chatID: chatId,
                senderID: user.userID,
                keyVersion: "v_1",
                ciphertext: ciphertext,
                nonce: nonce,
                messageType: .text,
                createdAt: Date()
            )
            
            let decryptedMsg = DecryptedMessage(
                message: pbMsg,
                senderName: user.displayName,
                decryptedText: trimmed,
                myReaction: nil
            )
            
            MessageRepository.shared.createMessage(tenantId: tenantId, chatId: chatId, message: pbMsg, members: members) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let err):
                    completion?(.failure(err))
                case .success:
                    DispatchQueue.main.async {
                        var list = self.messages[chatId] ?? []
                        if !list.contains(where: { $0.id == decryptedMsg.id }) {
                            list.append(decryptedMsg)
                            self.messages[chatId] = list
                        }
                        if let chatIdx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                            let oldChat = self.chats[chatIdx]
                            self.chats[chatIdx] = FriendsChatUIModel(
                                chat: oldChat.chat,
                                title: oldChat.title,
                                lastMessage: trimmed,
                                lastMessageAt: pbMsg.createdDate,
                                unreadCount: oldChat.unreadCount
                            )
                        }
                    }
                    completion?(.success(()))
                }
            }
        }
    }
    
    // MARK: - Send Image Attachments to R2 & Firestore (E2EE Envelope Encryption)
    
    public func sendImageMessage(
        chatId: String,
        images: [UIImage],
        text: String = "",
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard !images.isEmpty else {
            completion?(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Images array is empty"])))
            return
        }
        guard let tenant = currentTenant else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current tenant is nil"])))
            return
        }
        guard let user = currentUser else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current user is nil"])))
            return
        }
        
        let tenantId = tenant.tenantID
        let messageId = "m_\(ULID().ulidString)"
        
        // メンバーリストの導出
        var members: [String] = []
        if chatId.hasPrefix("dm_") {
            let rawStr = String(chatId.dropFirst(3))
            let parts = rawStr.components(separatedBy: "_u_")
            if parts.count == 2 {
                let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                let userB = "u_" + parts[1]
                members = [userA, userB].sorted()
            }
        } else if let existingChat = chats.first(where: { $0.chatID == chatId }) {
            members = existingChat.chat.members
        }
        
        // バックグラウンドで画像リサイズ・暗号化・R2アップロードを実行
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let uploadGroup = DispatchGroup()
            var attachments: [MessageAttachment] = []
            var uploadError: Error?
            let lock = NSLock()
            
            for img in images {
                uploadGroup.enter()
                
                // リサイズ & JPEG圧縮
                let resized = self.resizeImageForUpload(image: img, maxDimension: 1920)
                guard let jpegData = resized.jpegData(compressionQuality: 0.8) else {
                    lock.lock()
                    uploadError = NSError(domain: "ChatError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image data"])
                    lock.unlock()
                    uploadGroup.leave()
                    continue
                }
                
                let attId = "att_\(ULID().ulidString)"
                let storagePath = "tenants/\(tenantId)/chats/\(chatId)/attachments/\(attId).enc"
                let fileKey = CryptoKeyManager.shared.generateFileKey()
                let fileKeyBase64 = fileKey.withUnsafeBytes { Data($0) }.base64EncodedString()
                
                do {
                    let encResult = try CryptoKeyManager.shared.encryptFile(fileData: jpegData, key: fileKey)
                    AttachmentRepository.shared.uploadAttachment(encryptedData: encResult.encryptedData, storagePath: storagePath) { r2Result in
                        defer { uploadGroup.leave() }
                        switch r2Result {
                        case .failure(let err):
                            lock.lock()
                            if uploadError == nil { uploadError = err }
                            lock.unlock()
                        case .success:
                            let attachment = MessageAttachment(
                                attachmentId: attId,
                                storagePath: storagePath,
                                fileKey: fileKeyBase64,
                                nonce: encResult.nonceBase64,
                                mimeType: "image/jpeg",
                                width: Int(resized.size.width),
                                height: Int(resized.size.height),
                                size: jpegData.count
                            )
                            lock.lock()
                            attachments.append(attachment)
                            lock.unlock()
                        }
                    }
                } catch {
                    lock.lock()
                    if uploadError == nil { uploadError = error }
                    lock.unlock()
                    uploadGroup.leave()
                }
            }
            
            uploadGroup.wait()
            
            if let error = uploadError, attachments.isEmpty {
                DispatchQueue.main.async {
                    completion?(.failure(error))
                }
                return
            }
            
            // ペイロード構築
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let payloadObj = MessageContentPayload(text: trimmedText, attachments: attachments)
            guard let payloadData = try? JSONEncoder().encode(payloadObj),
                  let payloadJsonString = String(data: payloadData, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion?(.failure(NSError(domain: "ChatError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to encode message payload JSON"])))
                }
                return
            }
            
            let getKeyHandler: (@escaping (SymmetricKey?) -> Void) -> Void = { handler in
                if chatId.hasPrefix("gm_") {
                    self.getGroupSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
                } else {
                    self.getDirectSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
                }
            }
            
            getKeyHandler { sessionKey in
                var ciphertext = ""
                var nonce = ""
                
                if let key = sessionKey {
                    if let enc = try? CryptoKeyManager.shared.encryptDirectMessage(plainText: payloadJsonString, sessionKey: key) {
                        ciphertext = enc.ciphertext
                        nonce = enc.nonce
                    }
                }
                
                if ciphertext.isEmpty {
                    if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: payloadJsonString, tenantId: tenantId) {
                        ciphertext = enc.encryptedData
                        nonce = enc.nonce
                    }
                }
                
                let pbMsg = FriendsMessage(
                    messageID: messageId,
                    tenantID: tenantId,
                    chatID: chatId,
                    senderID: user.userID,
                    keyVersion: "v_1",
                    ciphertext: ciphertext,
                    nonce: nonce,
                    messageType: .image,
                    createdAt: Date()
                )
                
                let decryptedMsg = DecryptedMessage(
                    message: pbMsg,
                    senderName: user.displayName,
                    plainText: trimmedText,
                    decryptedText: payloadJsonString,
                    myReaction: nil,
                    attachments: attachments
                )
                
                MessageRepository.shared.createMessage(tenantId: tenantId, chatId: chatId, message: pbMsg, members: members) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .failure(let err):
                        DispatchQueue.main.async {
                            completion?(.failure(err))
                        }
                    case .success:
                        DispatchQueue.main.async {
                            var list = self.messages[chatId] ?? []
                            if !list.contains(where: { $0.id == decryptedMsg.id }) {
                                list.append(decryptedMsg)
                                self.messages[chatId] = list
                            }
                            let lastText = trimmedText.isEmpty ? "[\(L10n.Chat.imageMessage)]" : "[\(L10n.Chat.imageMessage)] \(trimmedText)"
                            if let chatIdx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                                let oldChat = self.chats[chatIdx]
                                self.chats[chatIdx] = FriendsChatUIModel(
                                    chat: oldChat.chat,
                                    title: oldChat.title,
                                    lastMessage: lastText,
                                    lastMessageAt: pbMsg.createdDate,
                                    unreadCount: oldChat.unreadCount
                                )
                            }
                            completion?(.success(()))
                        }
                    }
                }
            }
        }
    }
    
    private func resizeImageForUpload(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        
        let ratio = maxDimension / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }
    
    // MARK: - Profile Update (E02: Display Name Change & Hybrid Sync)
    
    
    public func patchDisplayName(newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            completion(.failure(NSError(domain: "ProfileError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Settings.editProfileEmptyError])))
            return
        }
        
        guard let _ = currentTenant, var user = currentUser else {
            completion(.failure(NSError(domain: "ProfileError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        // 1. 自身の端末 Keychain に安全に保管
        CryptoKeyManager.shared.saveMyDisplayName(uid: user.uid, name: cleanName)
        
        // 2. メモリ上の現在のユーザー表示名を更新（友達への最新表示名伝播はE2EEメッセージ経由）
        DispatchQueue.main.async {
            user.displayName = cleanName
            self.currentUser = user
            completion(.success(()))
        }
    }
    
    // MARK: - Avatar Management (AP-01 / AP-02 / AP-03)
    
    public func uploadAvatar(image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
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
    
    public func deleteAvatar(completion: @escaping (Result<Void, Error>) -> Void) {
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
    
    public func getCachedAvatar(userId: String, updatedAt: Date? = nil) -> UIImage? {
        return AvatarRepository.shared.getCachedAvatar(userId: userId, updatedAt: updatedAt)
    }
    
    public func loadAvatarImage(userId: String, avatarNonce: String, updatedAt: Date?, completion: @escaping (Result<UIImage, Error>) -> Void) {
        guard let tenant = currentTenant else {
            completion(.failure(NSError(domain: "AvatarError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        AvatarRepository.shared.getAvatarByUserId(tenantId: tenant.tenantID, userId: userId, avatarNonce: avatarNonce, updatedAt: updatedAt, completion: completion)
    }

    
    // MARK: - Hybrid Friend Profile Sync (On-Demand / Pull-to-Refresh)
    
    
    public func listFriendsProfiles(force: Bool = false, completion: (() -> Void)? = nil) {
        guard let tenant = currentTenant, !friends.isEmpty else {
            completion?()
            return
        }
        let tenantId = tenant.tenantID
        let friendUserIds = friends.map { $0.userID }
        
        FriendRepository.shared.listFriendsProfilesByUserIds(tenantId: tenantId, friendUserIds: friendUserIds) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            if case .success(let updatedFriendsMap) = result {
                DispatchQueue.main.async {
                    self.friends = self.friends.map { friend in
                        if let info = updatedFriendsMap[friend.userID] {
                            let nameChanged = !info.displayName.isEmpty && info.displayName != friend.displayName
                            let avatarChanged = info.avatarNonce != friend.avatarNonce || info.avatarUpdatedAt != friend.avatarUpdatedDate
                            let usernameChanged = !info.username.isEmpty && info.username != friend.username
                            
                            if nameChanged || avatarChanged || usernameChanged {
                                let targetName = info.displayName.isEmpty ? friend.displayName : info.displayName
                                let targetUsername = info.username.isEmpty ? friend.username : info.username
                                return FriendsPublicUserProfile(
                                    userID: friend.userID,
                                    uid: friend.uid,
                                    tenantID: friend.tenantID,
                                    displayName: targetName,
                                    publicKey: friend.publicKey,
                                    role: friend.role,
                                    accountType: friend.accountType,
                                    avatarNonce: info.avatarNonce,
                                    avatarUpdatedAt: info.avatarUpdatedAt,
                                    username: targetUsername
                                )
                            }
                        }
                        return friend
                    }
                    completion?()
                }
            } else {
                completion?()
            }
        }
    }

    // MARK: - Group Chats Pull-to-Refresh & Synchronization (GP-08)
    
    /// かいぎ一覧の同期・全参加メンバープロファイル一括取得 (GP-08)
    func listGroupChats(force: Bool = false, completion: (() -> Void)? = nil) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion?()
            return
        }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        // 1. チャット一覧を再フェッチ
        ChatRepository.shared.listChatsByUserId(tenantId: tenantId, userId: userId) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            
            switch result {
            case .success(let fetchedChats):
                DispatchQueue.main.async {
                    self.chats = fetchedChats
                }
                
                // 2. 参加中グループチャットの全メンバーIDを収集
                var allMemberIds = Set<String>()
                for chat in fetchedChats where chat.chatType == .group {
                    for memberId in chat.chat.members {
                        if memberId != userId && memberId != user.uid {
                            allMemberIds.insert(memberId)
                        }
                    }
                }
                
                // 3. 友達一覧のプロファイルも並行更新
                self.listFriendsProfiles(force: true)
                
                // 4. グループ参加メンバーのプロファイルを一括取得してキャッシュ更新
                if !allMemberIds.isEmpty {
                    FriendRepository.shared.listFriendsProfilesByUserIds(tenantId: tenantId, friendUserIds: Array(allMemberIds)) { profileResult in
                        DispatchQueue.main.async {
                            if case .success(let profileMap) = profileResult {
                                for (uid, profile) in profileMap {
                                    var profileObj = FriendsPublicUserProfile()
                                    profileObj.userID = uid
                                    profileObj.uid = uid
                                    profileObj.tenantID = tenantId
                                    profileObj.displayName = profile.displayName.isEmpty ? uid : profile.displayName
                                    profileObj.role = .member
                                    profileObj.accountType = .persistent
                                    profileObj.avatarNonce = profile.avatarNonce
                                    if let date = profile.avatarUpdatedAt {
                                        profileObj.avatarUpdatedAt = Google_Protobuf_Timestamp(date: date)
                                    }
                                    profileObj.username = profile.username
                                    
                                    self.groupMemberProfiles[uid] = profileObj
                                }
                            }
                            
                            // 5. 各グループの最新メッセージリスナーを再確認
                            for chat in fetchedChats where chat.chatType == .group {
                                self.watchMessages(chatId: chat.chatID)
                                self.watchReadReceipts(chatId: chat.chatID)
                            }
                            completion?()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        // グループメッセージのリスナー再確認
                        for chat in fetchedChats where chat.chatType == .group {
                            self.watchMessages(chatId: chat.chatID)
                            self.watchReadReceipts(chatId: chat.chatID)
                        }
                        completion?()
                    }
                }
                
            case .failure(let error):
                AppLogger.error("Failed to refresh group chats: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion?()
                }
            }
        }
    }

    
    // MARK: - Read Receipt Management (水位線カーソル方式)
    
    public func watchReadReceipts(chatId: String) {
        guard readReceiptListeners[chatId] == nil, let tenant = currentTenant else { return }
        let tenantId = tenant.tenantID
        
        let listener = ReadReceiptRepository.shared.watchReadReceiptsByChatId(tenantId: tenantId, chatId: chatId) { [weak self] receiptsMap in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.readReceipts[chatId] = receiptsMap
            }
        }
        readReceiptListeners[chatId] = listener
    }
    
    public func markAsRead(chatId: String, lastMessageId: String? = nil, lastMessageDate: Date? = nil) {
        guard let tenant = currentTenant, let user = currentUser else {
            return
        }
        let tenantId = tenant.tenantID
        let userId = user.userID // u_xxx (Firestore Security Rules requires tenant userId)
        
        let (messageId, readDate): (String, Date) = {
            if let mid = lastMessageId, let mdate = lastMessageDate {
                return (mid, mdate)
            }
            if let list = messages[chatId], let lastMsg = list.last {
                return (lastMsg.id, lastMsg.createdDate)
            }
            return ("initial", Date())
        }()
        
        // 1. 即時ローカルキャッシュに反映（UI即時応答）
        var currentMap = readReceipts[chatId] ?? [:]
        let localReceipt = FriendsReadReceipt(
            userID: userId,
            chatID: chatId,
            tenantID: tenantId,
            lastReadMessageID: messageId,
            lastReadAt: readDate,
            updatedAt: Date()
        )
        currentMap[userId] = localReceipt
        readReceipts[chatId] = currentMap
        
        // 2. Debounce Firestore writes (300ms)
        markAsReadDebounceWorkItems[chatId]?.cancel()
        
        let workItem = DispatchWorkItem {
            ReadReceiptRepository.shared.patchReadReceiptByUserId(
                tenantId: tenantId,
                chatId: chatId,
                userId: userId,
                lastReadMessageId: messageId,
                lastReadAt: readDate
            )
        }
        
        markAsReadDebounceWorkItems[chatId] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    /// 1:1チャットにおいて相手がメッセージを既読したかを判定
    public func isMessageRead(chatId: String, messageDate: Date, senderId: String) -> Bool {
        guard let receipts = readReceipts[chatId] else { return false }
        
        // 自分（送信者）以外の参加者の ReadReceipt を探索
        for (userId, receipt) in receipts {
            // 送信者自身の userID ではないことを確認
            let isSender = (userId == senderId) || (userId == currentUser?.userID)
            if !isSender {
                // 相手の lastReadDate がメッセージ作成日時以降であれば既読
                let thresholdDate = messageDate.addingTimeInterval(-1.0)
                let isRead = receipt.lastReadDate >= thresholdDate
                if isRead {
                    return true
                }
            }
        }
        return false
    }
    
    /// グループチャットにおいてメッセージを既読したメンバー数を取得
    public func readCountForMessage(chatId: String, messageDate: Date, senderId: String) -> Int {
        guard let receipts = readReceipts[chatId] else { return 0 }
        
        var count = 0
        var countedUserIds = Set<String>()
        for (userId, receipt) in receipts {
            let isSender = (userId == senderId) || (userId == currentUser?.userID)
            if !isSender && !countedUserIds.contains(userId) {
                if receipt.lastReadDate >= messageDate.addingTimeInterval(-1.0) {
                    count += 1
                    countedUserIds.insert(userId)
                }
            }
        }
        return count
    }
    
    /// 指定チャットの未読メッセージ数を計算
    public func unreadCount(for chatId: String) -> Int {
        if activeChatId == chatId {
            return 0
        }
        guard let myUserId = currentUser?.userID else { return 0 }
        guard let chatMessages = messages[chatId], !chatMessages.isEmpty else { return 0 }
        
        let receipts = readReceipts[chatId] ?? [:]
        let myReceipt = receipts[myUserId]
        let myLastReadDate = myReceipt?.lastReadDate ?? Date.distantPast
        let myLastReadMessageId = myReceipt?.lastReadMessageID ?? ""
        
        // 1. 最新メッセージが既に既読されている場合は未読 0
        if let lastMsg = chatMessages.last, !myLastReadMessageId.isEmpty, lastMsg.id == myLastReadMessageId {
            return 0
        }
        
        // 2. lastReadMessageID がメッセージ履歴内に存在する場合、それ以降の他者メッセージをカウント
        if !myLastReadMessageId.isEmpty, let idx = chatMessages.firstIndex(where: { $0.id == myLastReadMessageId }) {
            var unread = 0
            for i in (idx + 1)..<chatMessages.count {
                let msg = chatMessages[i]
                let isMine = msg.message.senderID == myUserId
                if !isMine {
                    unread += 1
                }
            }
            return unread
        }
        
        // 3. messageId で特定できない場合はタイムスタンプ比較 (0.1秒マージン)
        var unread = 0
        for msg in chatMessages {
            let isMine = msg.message.senderID == myUserId
            if !isMine && msg.createdDate > myLastReadDate.addingTimeInterval(0.1) {
                unread += 1
            }
        }
        return unread
    }
    
    /// 全チャットの合計未読メッセージ数
    public var totalUnreadCount: Int {
        let count = totalDmUnreadCount + totalGroupUnreadCount
        if let currentId = currentTenant?.tenantID {
            TenantManager.shared.updateUnreadCount(for: currentId, count: count)
        }
        return count
    }
    
    /// 1:1（DM）チャット一覧
    var dmChats: [FriendsChatUIModel] {
        chats.filter { $0.chatType == .direct }
    }
    
    /// グループチャット（かいぎ）一覧
    var groupChats: [FriendsChatUIModel] {
        chats.filter { $0.chatType == .group }
    }
    
    /// グループチャットの合計未読数
    var totalGroupUnreadCount: Int {
        var total = 0
        for chat in groupChats {
            total += unreadCount(for: chat.chatID)
        }
        return total
    }
    
    /// 1:1 チャットの合計未読数
    var totalDmUnreadCount: Int {
        let currentUserId = currentUser?.userID ?? ""
        var seenDmChatIds = Set<String>()
        var total = 0
        
        // 1. friends リストから生成される DM チャット ID
        if !currentUserId.isEmpty {
            for friend in friends {
                let dmChatId = "dm_" + [currentUserId, friend.userID].sorted().joined(separator: "_")
                if !seenDmChatIds.contains(dmChatId) {
                    seenDmChatIds.insert(dmChatId)
                    total += unreadCount(for: dmChatId)
                }
            }
        }
        
        // 2. chats コレクション由来の DM チャット
        for chat in dmChats {
            if !seenDmChatIds.contains(chat.chatID) {
                seenDmChatIds.insert(chat.chatID)
                total += unreadCount(for: chat.chatID)
            }
        }
        
        return total
    }
    
    // MARK: - Group Management (かいぎ)
    
    /// 新規グループチャット作成 (Forward Secrecy / KeyBucket 初期化)
    func createGroup(title: String, memberUserIds: [String], completion: @escaping (Result<FriendsChatUIModel, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let chatId = "gm_\(ULID().ulidString)"
        let otherMembers = memberUserIds.filter { $0 != currentUser.userID }
        let allMembers = [currentUser.userID] + otherMembers
        
        // 1. グループ会話鍵 (SK_group) の生成
        let groupKey = CryptoKeyManager.shared.generateGroupKey()
        let keyVersion = "v_1"
        self.groupSessionKeys["\(chatId)_\(keyVersion)"] = groupKey
        
        // 2. メンバーの公開鍵を収集して KeyBucket を作成
        var memberPubKeys: [String: String] = [:]
        if let myPubKey = CryptoKeyManager.shared.getPublicKeyBase64(uid: currentUser.uid) {
            memberPubKeys[currentUser.userID] = myPubKey
        }
        for mId in memberUserIds {
            if let f = friends.first(where: { $0.userID == mId }), !f.publicKey.isEmpty {
                memberPubKeys[mId] = f.publicKey
            }
        }
        
        let encryptedKeys = (try? CryptoKeyManager.shared.encryptGroupKeyForMembers(
            groupKey: groupKey,
            myUid: currentUser.uid,
            memberPublicKeys: memberPubKeys,
            tenantId: tenantId
        )) ?? [:]
        
        // 3. Firestore へチャット親ドキュメント & KeyBucket を保存
        ChatRepository.shared.createGroupChat(
            tenantId: tenantId,
            chatId: chatId,
            title: title,
            members: allMembers,
            createdBy: currentUser.userID
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                KeyBucketRepository.shared.saveKeyBucket(
                    tenantId: tenantId,
                    chatId: chatId,
                    keyVersion: keyVersion,
                    encryptedGroupKeys: encryptedKeys,
                    createdBy: currentUser.userID
                ) { _ in
                    var initialRoles: [String: FriendsGroupMemberRole] = [:]
                    for m in allMembers {
                        initialRoles[m] = (m == currentUser.userID) ? .owner : .member
                    }
                    
                    let pbChat = FriendsChat(
                        chatID: chatId,
                        tenantID: tenantId,
                        chatType: .group,
                        members: allMembers,
                        title: title,
                        createdBy: currentUser.userID,
                        createdAt: Date(),
                        updatedBy: currentUser.userID,
                        updatedAt: Date(),
                        memberRoles: initialRoles,
                        isDeleted: false
                    )
                    let uiChat = FriendsChatUIModel(
                        chat: pbChat,
                        title: title,
                        lastMessage: "",
                        lastMessageAt: Date(),
                        unreadCount: 0
                    )
                    DispatchQueue.main.async {
                        if !self.chats.contains(where: { $0.chatID == chatId }) {
                            self.chats.insert(uiChat, at: 0)
                        }
                        self.watchMessages(chatId: chatId)
                    }
                    completion(.success(uiChat))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// グループ削除 (GP-03: オーナー/管理者による2段階確認後の削除実行)
    func deleteGroup(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        ChatRepository.shared.deleteGroupChat(
            tenantId: tenant.tenantID,
            chatId: chatId,
            deletedBy: currentUser.userID
        ) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                DispatchQueue.main.async {
                    self.chats.removeAll(where: { $0.chatID == chatId })
                    self.messages.removeValue(forKey: chatId)
                    self.messageListeners[chatId]?.remove()
                    self.messageListeners.removeValue(forKey: chatId)
                }
            }
            completion(result)
        }
    }
    
    /// 管理者任命 (GP-04)
    func assignAdmin(chatId: String, targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        ChatRepository.shared.assignAdmin(
            tenantId: tenant.tenantID,
            chatId: chatId,
            targetUserId: targetUserId,
            updatedBy: currentUser.userID,
            completion: completion
        )
    }
    
    /// 立候補型オーナー交代 (GP-05)
    func claimOwnership(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let currentChat = chats.first(where: { $0.chatID == chatId })
        let oldOwnerId = currentChat?.ownerUserId
        
        ChatRepository.shared.claimOwnership(
            tenantId: tenant.tenantID,
            chatId: chatId,
            newOwnerId: currentUser.userID,
            oldOwnerId: oldOwnerId,
            completion: completion
        )
    }
    
    /// メンバー除外 / キック (GP-06)
    func kickMember(chatId: String, targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        ChatRepository.shared.removeGroupMember(
            tenantId: tenant.tenantID,
            chatId: chatId,
            targetUserId: targetUserId,
            updatedBy: currentUser.userID,
            completion: completion
        )
    }
    
    /// グループ名変更 (GP-07)
    func updateGroupTitle(chatId: String, newTitle: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        ChatRepository.shared.updateGroupTitle(
            tenantId: tenant.tenantID,
            chatId: chatId,
            newTitle: newTitle,
            updatedBy: currentUser.userID
        ) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                DispatchQueue.main.async {
                    if let idx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                        let old = self.chats[idx]
                        var updatedChat = old.chat
                        updatedChat.title = newTitle
                        self.chats[idx] = FriendsChatUIModel(
                            chat: updatedChat,
                            title: newTitle,
                            lastMessage: old.lastMessage,
                            lastMessageAt: old.lastMessageAt,
                            unreadCount: old.unreadCount
                        )
                    }
                }
            }
            completion(result)
        }
    }
    
    /// グループに新しいメンバーを追加 (GP-08)
    func addMembersToGroup(chatId: String, newMemberUserIds: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let keyVersion = "v_1"
        
        getGroupSessionKey(chatId: chatId, tenantId: tenantId, keyVersion: keyVersion) { [weak self] resolvedGroupKey in
            guard let self = self else { return }
            guard let groupKey = resolvedGroupKey else {
                completion(.failure(NSError(domain: "ChatService", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
                return
            }
            
            var newMemberPubKeys: [String: String] = [:]
            for mId in newMemberUserIds {
                if let f = self.friends.first(where: { $0.userID == mId }), !f.publicKey.isEmpty {
                    newMemberPubKeys[mId] = f.publicKey
                }
            }
            
            let newEncryptedKeys = (try? CryptoKeyManager.shared.encryptGroupKeyForMembers(
                groupKey: groupKey,
                myUid: currentUser.uid,
                memberPublicKeys: newMemberPubKeys,
                tenantId: tenantId
            )) ?? [:]
            
            // 2. KeyBucket に新規メンバー用暗号化鍵を追加保存
            KeyBucketRepository.shared.saveKeyBucket(
                tenantId: tenantId,
                chatId: chatId,
                keyVersion: keyVersion,
                encryptedGroupKeys: newEncryptedKeys,
                createdBy: currentUser.userID
            ) { _ in
            // 3. Firestore の chats ドキュメントにメンバーを追加
            ChatRepository.shared.addGroupMembers(
                tenantId: tenantId,
                chatId: chatId,
                newMemberUserIds: newMemberUserIds,
                updatedBy: currentUser.userID
            ) { [weak self] result in
                guard let self = self else { return }
                if case .success = result {
                    DispatchQueue.main.async {
                        if let idx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                            let old = self.chats[idx]
                            var updatedChat = old.chat
                            for m in newMemberUserIds {
                                if !updatedChat.members.contains(m) {
                                    updatedChat.members.append(m)
                                }
                                updatedChat.memberRoles[m] = .member
                            }
                            self.chats[idx] = FriendsChatUIModel(
                                chat: updatedChat,
                                title: old.title,
                                lastMessage: old.lastMessage,
                                lastMessageAt: old.lastMessageAt,
                                unreadCount: old.unreadCount,
                                avatarNonce: old.avatarNonce,
                                avatarUpdatedAt: old.avatarUpdatedAt
                            )
                        }
                    }
                }
                completion(result)
            }
        }
        }
    }
    
    /// グループアバターの更新 (GP-09)
    func updateGroupAvatar(chatId: String, image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        AvatarRepository.shared.uploadGroupAvatar(
            tenantId: tenant.tenantID,
            chatId: chatId,
            image: image,
            updatedBy: currentUser.userID
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let (updatedAt, nonce)):
                DispatchQueue.main.async {
                    if let idx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                        var model = self.chats[idx]
                        model.avatarNonce = nonce
                        model.avatarUpdatedAt = updatedAt
                        self.chats[idx] = model
                    }
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// グループアバターの削除 (GP-10)
    func deleteGroupAvatar(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        AvatarRepository.shared.deleteGroupAvatar(
            tenantId: tenant.tenantID,
            chatId: chatId,
            updatedBy: currentUser.userID
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                DispatchQueue.main.async {
                    if let idx = self.chats.firstIndex(where: { $0.chatID == chatId }) {
                        var model = self.chats[idx]
                        model.avatarNonce = ""
                        model.avatarUpdatedAt = nil
                        self.chats[idx] = model
                    }
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Message Reactions Management (8種・クイックアクション7種 & 低通信量集計)
    
    /// リアクションのトグル（付加 / 切り替え / 解除）
    func toggleReaction(chatId: String, messageId: String, reactionType: FriendsReactionType) {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        let reactionKey = "\(chatId)_\(messageId)"
        let previousReaction = userReactions[reactionKey]
        
        if previousReaction == reactionType {
            // 1. 解除 (Delete)
            DispatchQueue.main.async {
                self.userReactions.removeValue(forKey: reactionKey)
                self.updateLocalMessageReaction(chatId: chatId, messageId: messageId, oldReaction: previousReaction, newReaction: nil)
            }
            ReactionRepository.shared.deleteReactionByUserId(tenantId: tenantId, chatId: chatId, messageId: messageId, userId: userId, reactionType: reactionType)
        } else {
            // 2. 付加または切り替え (Set / Overwrite)
            DispatchQueue.main.async {
                self.userReactions[reactionKey] = reactionType
                self.updateLocalMessageReaction(chatId: chatId, messageId: messageId, oldReaction: previousReaction, newReaction: reactionType)
            }
            ReactionRepository.shared.setReactionByUserId(
                tenantId: tenantId,
                chatId: chatId,
                messageId: messageId,
                userId: userId,
                userName: user.displayName,
                reactionType: reactionType,
                previousReaction: previousReaction
            )
        }
    }
    
    private func updateLocalMessageReaction(
        chatId: String,
        messageId: String,
        oldReaction: FriendsReactionType?,
        newReaction: FriendsReactionType?
    ) {
        guard var list = messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        var counts = list[idx].reactionCounts
        
        if let prev = oldReaction {
            let cur = counts[prev.key] ?? 0
            if cur <= 1 {
                counts.removeValue(forKey: prev.key)
            } else {
                counts[prev.key] = cur - 1
            }
        }
        if let next = newReaction {
            let cur = counts[next.key] ?? 0
            counts[next.key] = cur + 1
        }
        
        var pbMsg = list[idx].message
        pbMsg.reactionCounts = counts
        
        list[idx] = DecryptedMessage(
            message: pbMsg,
            senderName: list[idx].senderName,
            decryptedText: list[idx].decryptedText,
            myReaction: newReaction
        )
        self.messages[chatId] = list
    }
    
    /// オンデマンドでメッセージの全リアクション詳細を取得（通信量低減）
    func fetchReactionDetails(
        chatId: String,
        messageId: String,
        completion: @escaping (Result<[FriendsMessageReaction], Error>) -> Void
    ) {
        guard let tenant = currentTenant else {
            completion(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        ReactionRepository.shared.listReactionDetailsByMessageId(tenantId: tenant.tenantID, chatId: chatId, messageId: messageId, completion: completion)
    }
}


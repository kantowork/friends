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
    @Published var currentTenant: FriendsTenant? = PresetTenantConfig.defaultTenant
    @Published var currentUser: FriendsPublicUserProfile? = nil
    @Published var friends: [FriendsPublicUserProfile] = []
    @Published var chats: [FriendsChatUIModel] = []
    @Published var messages: [String: [DecryptedMessage]] = [:] // chatId -> [DecryptedMessage]
    @Published var readReceipts: [String: [String: FriendsReadReceipt]] = [:] // chatId -> [userId: FriendsReadReceipt]
    @Published var userReactions: [String: FriendsReactionType] = [:] // "\(chatId)_\(messageId)" -> reactionType
    @Published public var activeChatId: String? = nil
    
    private let db = Firestore.firestore()
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var readReceiptListeners: [String: ListenerRegistration] = [:]
    private var chatListener: ListenerRegistration?
    private var friendListener: ListenerRegistration?
    private var markAsReadDebounceWorkItems: [String: DispatchWorkItem] = [:]
    private var directSessionKeys: [String: SymmetricKey] = [:] // chatId -> SK_direct
    private var knownMessageIds: [String: Set<String>] = [:]

    
    private init() {
        checkAuthState()
    }
    
    // MARK: - Initial Auth & Tenant Checking
    
    public func checkAuthState() {
        // 1. Fetch Tenant from Firestore
        fetchDefaultTenant { [weak self] tenantResult in
            guard let self = self else { return }
            
            switch tenantResult {
            case .success(let tenant):
                DispatchQueue.main.async {
                    self.currentTenant = tenant
                }
                // 2. Check Firebase Auth
                if let firebaseUser = Auth.auth().currentUser {
                    self.loadUserProfile(uid: firebaseUser.uid, tenantId: tenant.tenantID)
                } else {
                    DispatchQueue.main.async {
                        self.authStatus = .unauthenticated
                    }
                }
            case .failure(let error):
                print("⚠️ Error fetching tenant from Firestore: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.authStatus = .unauthenticated
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
            if let tenant = self.currentTenant {
                self.createAndSaveUserProfile(uid: user.uid, tenantId: tenant.tenantID, displayName: name, accountType: .anonymous, completion: completion)
            } else {
                self.fetchDefaultTenant { result in
                    switch result {
                    case .success(let tenant):
                        DispatchQueue.main.async { self.currentTenant = tenant }
                        self.createAndSaveUserProfile(uid: user.uid, tenantId: tenant.tenantID, displayName: name, accountType: .anonymous, completion: completion)
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            }
        }
    }
    
    // MARK: - Sign In / Sign Up with Email
    
    public func signInWithEmail(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] authResult, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let user = authResult?.user else { return }
            
            let tenantId = self.currentTenant?.tenantID ?? "t_default"
            self.loadUserProfile(uid: user.uid, tenantId: tenantId)
            completion(.success(()))
        }
    }
    
    public func signUpWithEmail(email: String, password: String, displayName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] authResult, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let user = authResult?.user else { return }
            
            if let tenant = self.currentTenant {
                self.createAndSaveUserProfile(uid: user.uid, tenantId: tenant.tenantID, displayName: displayName, completion: completion)
            } else {
                self.fetchDefaultTenant { result in
                    switch result {
                    case .success(let tenant):
                        DispatchQueue.main.async { self.currentTenant = tenant }
                        self.createAndSaveUserProfile(uid: user.uid, tenantId: tenant.tenantID, displayName: displayName, completion: completion)
                    case .failure(let err):
                        completion(.failure(err))
                    }
                }
            }
        }
    }
    
    private func createAndSaveUserProfile(uid: String, tenantId: String, displayName: String, accountType: FriendsAccountType = .anonymous, completion: @escaping (Result<Void, Error>) -> Void) {
        let userId = UserIDHelper.generateUserId()
        
        // 🔐 Curve25519 鍵ペアを生成し、秘密鍵をローカル Keychain に保存
        let keypair = try? CryptoKeyManager.shared.getOrCreateKeypair(uid: uid)
        let publicKey = keypair?.publicKeyBase64 ?? "defaultPublicKeyBase64=="
        
        // 🔐 テナントマスターキー (MK_T) で表示名を暗号化
        var encryptedName = ""
        var nameNonce = ""
        if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: displayName, tenantId: tenantId) {
            encryptedName = enc.encryptedData
            nameNonce = enc.nonce
        }
        
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
            encryptedDisplayName: encryptedName,
            displayNameNonce: nameNonce,
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
    
    // MARK: - Restore with Recovery Phrase
    
    public func restoreWithRecoveryPhrase(words: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        Auth.auth().signInAnonymously { [weak self] authResult, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let user = authResult?.user else { return }
            
            self.fetchDefaultTenant { tenantResult in
                switch tenantResult {
                case .success(let tenant):
                    DispatchQueue.main.async { self.currentTenant = tenant }
                    let recoveredName = "復元ユーザー (\(words.first ?? "ゲスト"))"
                    self.createAndSaveUserProfile(uid: user.uid, tenantId: tenant.tenantID, displayName: recoveredName, completion: completion)
                case .failure(let err):
                    completion(.failure(err))
                }
            }
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
                
                DispatchQueue.main.async {
                    self.currentUser = profile
                    self.authStatus = .authenticated
                    self.watchChats()
                    self.watchFriends()
                }
            case .failure:
                // uid で見つからない場合は従来の u_prefix(8) もフォールバック確認
                let legacyUserId = "u_\(uid.prefix(8))"
                UserRepository.shared.getUserProfileByUserId(tenantId: tenantId, userId: legacyUserId) { [weak self] legacyResult in
                    guard let self = self else { return }
                    switch legacyResult {
                    case .success(let userProfile):
                        DispatchQueue.main.async {
                            self.currentUser = userProfile
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
    
    // MARK: - Friends Management & Listeners
    
    public func watchFriends() {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        friendListener?.remove()
        friendListener = FriendRepository.shared.watchFriendsByUserId(tenantId: tenantId, userId: userId) { [weak self] loadedFriends in
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

    
    public func listenToFriends() {
        watchFriends()
    }
    
    func addFriend(
        from payload: FriendsFriendInvitationPayload,
        explicitPasscode: String? = nil,
        completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void
    ) {
        createFriend(from: payload, explicitPasscode: explicitPasscode, completion: completion)
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
                var targetDisplayName = data["displayName"] as? String ?? "ユーザー"
                if let encName = data["encryptedDisplayName"] as? String,
                   let nonce = data["displayNameNonce"] as? String,
                   let decrypted = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encName, nonce: nonce, tenantId: tenant.tenantID) {
                    targetDisplayName = decrypted
                }
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
                
                self.addFriend(from: payload, explicitPasscode: cleanPasscode, completion: completion)
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
            print("❌ [ChatService] updateUsername failed: tenant or user is nil")
            completion(.failure(NSError(domain: "UserError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        let cleanUsername = newUsername.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
        print("🔍 [ChatService] updateUsername starting for tenant: \(tenant.tenantID), userId: \(user.userID), old: '\(user.username)', new: '\(cleanUsername)'")
        
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
                print("✅ [ChatService] UserRepository.updateUsername succeeded in Firestore")
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    self.currentUser?.username = cleanUsername
                    print("✅ [ChatService] self.currentUser?.username updated to '\(self.currentUser?.username ?? "")' (effectiveUsername: '\(self.currentUser?.effectiveUsername ?? "")')")
                }
            case .failure(let err):
                print("❌ [ChatService] UserRepository.updateUsername failed: \(err.localizedDescription) (Error: \(err))")
            }
            completion(result)
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
            }
        }
    }
    
    // MARK: - Direct Session Key Helper
    
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
        let targetPeerId = peerUserId ?? chatId.replacingOccurrences(of: "dm_", with: "").components(separatedBy: "_").first(where: { $0 != currentUser?.userID && $0 != myUid }) ?? ""
        
        if let friend = friends.first(where: { $0.userID == targetPeerId || $0.uid == targetPeerId }), !friend.publicKey.isEmpty {
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
                if case .success(let userProfile) = result, !userProfile.publicKey.isEmpty {
                    if let key = try? CryptoKeyManager.shared.deriveDirectSessionKey(myUid: myUid, peerPublicKeyBase64: userProfile.publicKey, tenantId: tenantId) {
                        self.directSessionKeys[chatId] = key
                        completion(key)
                        return
                    }
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
    
    public func watchMessages(chatId: String) {
        guard messageListeners[chatId] == nil, let tenant = currentTenant else { return }
        let tenantId = tenant.tenantID
        
        let listener = MessageRepository.shared.watchMessagesByChatId(tenantId: tenantId, chatId: chatId) { [weak self] rawMessages in
            guard let self = self else { return }
            
            let previouslyKnownIds = self.knownMessageIds[chatId]
            let isInitialLoad = (previouslyKnownIds == nil)
            let currentMessageIds = Set(rawMessages.map { $0.messageID })
            self.knownMessageIds[chatId] = currentMessageIds
            
            self.getDirectSessionKey(chatId: chatId, tenantId: tenantId) { sessionKey in
                var newDecryptedMessages: [DecryptedMessage] = []
                var newlyReceivedMessagesToNotify: [DecryptedMessage] = []
                
                for msg in rawMessages {
                    let ciphertext = msg.encryptedPayload.ciphertext
                    let nonce = msg.encryptedPayload.nonce
                    
                    // 端末内ローカル復号 (E2EE)
                    var decryptedText = ""
                    if let key = sessionKey, !ciphertext.isEmpty, !nonce.isEmpty {
                        if let dec = try? CryptoKeyManager.shared.decryptDirectMessage(ciphertext: ciphertext, nonce: nonce, sessionKey: key) {
                            decryptedText = dec
                        } else if let decWithTenant = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: ciphertext, nonce: nonce, tenantId: tenantId) {
                            decryptedText = decWithTenant
                        }
                    }
                    
                    // 送信者名の解決 (ローカルのユーザー/友達キャッシュから解決)
                    var senderDisplayName = "送信者"
                    let isFromMe = (msg.senderID == self.currentUser?.uid || msg.senderID == self.currentUser?.userID)
                    if isFromMe {
                        senderDisplayName = self.currentUser?.displayName ?? "自分"
                    } else if let friend = self.friends.first(where: { $0.uid == msg.senderID || $0.userID == msg.senderID }) {
                        senderDisplayName = friend.displayName
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
    
    // 後方互換性エイリアス
    public func listenToMessages(chatId: String) {
        watchMessages(chatId: chatId)
    }
    
    public func listenToChats() {
        watchChats()
    }
    
    // MARK: - Send Message to Firestore (Zero-Plaintext E2EE)
    
    public func sendMessage(chatId: String, text: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        createMessage(chatId: chatId, text: text, completion: completion)
    }
    
    public func createMessage(chatId: String, text: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("⚠️ createMessage ignored: text is empty")
            completion?(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Text is empty"])))
            return
        }
        guard let tenant = currentTenant else {
            print("❌ createMessage failed: currentTenant is nil")
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current tenant is nil"])))
            return
        }
        guard let user = currentUser else {
            print("❌ createMessage failed: currentUser is nil")
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current user is nil"])))
            return
        }
        
        let tenantId = tenant.tenantID
        let messageId = "m_\(ULID().ulidString)"
        print("🚀 [ChatService] Starting createMessage - chatId: \(chatId), tenantId: \(tenantId), user: \(user.userID) (uid: \(user.uid))")
        
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
            } else {
                let fallbackParts = rawStr.components(separatedBy: "_")
                if fallbackParts.count == 2 {
                    members = fallbackParts.sorted()
                }
            }
        } else if let existingChat = chats.first(where: { $0.chatID == chatId }) {
            members = existingChat.chat.members
        }
        print("👥 [ChatService] Derived members: \(members)")
        
        getDirectSessionKey(chatId: chatId, tenantId: tenantId) { sessionKey in
            var ciphertext = ""
            var nonce = ""
            
            if let key = sessionKey {
                if let enc = try? CryptoKeyManager.shared.encryptDirectMessage(plainText: trimmed, sessionKey: key) {
                    ciphertext = enc.ciphertext
                    nonce = enc.nonce
                    print("🔒 [ChatService] Encrypted with Direct Session Key")
                }
            }
            
            // フォールバック: MK_T で暗号化
            if ciphertext.isEmpty {
                if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: trimmed, tenantId: tenantId) {
                    ciphertext = enc.encryptedData
                    nonce = enc.nonce
                    print("🔒 [ChatService] Encrypted with Tenant Master Key (fallback)")
                }
            }
            
            let pbMsg = FriendsMessage(
                messageID: messageId,
                tenantID: tenantId,
                chatID: chatId,
                senderID: user.uid,
                keyVersion: "v_1",
                ciphertext: ciphertext,
                nonce: nonce,
                messageType: .text,
                createdAt: Date()
            )
            
            MessageRepository.shared.createMessage(tenantId: tenantId, chatId: chatId, message: pbMsg, members: members) { result in
                switch result {
                case .failure(let err):
                    print("❌ [ChatService] Firestore Send Message Error: \(err.localizedDescription) (Error: \(err))")
                    completion?(.failure(err))
                case .success:
                    print("✅ [ChatService] E2EE Message successfully sent to Firestore! ID: \(messageId)")
                    completion?(.success(()))
                }
            }
        }
    }
    
    // MARK: - Profile Update (E02: Display Name Change & Hybrid Sync)
    
    public func updateDisplayName(newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        patchDisplayName(newName: newName, completion: completion)
    }
    
    public func patchDisplayName(newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            completion(.failure(NSError(domain: "ProfileError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Settings.editProfileEmptyError])))
            return
        }
        
        guard let tenant = currentTenant, var user = currentUser else {
            completion(.failure(NSError(domain: "ProfileError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        // 1. Encrypt new display name using Tenant Master Key (MK_T)
        var encryptedName = ""
        var nameNonce = ""
        if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: cleanName, tenantId: tenantId) {
            encryptedName = enc.encryptedData
            nameNonce = enc.nonce
        }
        
        UserRepository.shared.patchDisplayNameByUserId(tenantId: tenantId, userId: userId, encryptedDisplayName: encryptedName, nonce: nameNonce) { errorResult in
            if case .failure(let err) = errorResult {
                completion(.failure(err))
                return
            }
            
            DispatchQueue.main.async {
                user.displayName = cleanName
                user.encryptedDisplayName = encryptedName
                user.displayNameNonce = nameNonce
                self.currentUser = user
                completion(.success(()))
            }
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
    
    public func refreshFriendsProfiles(force: Bool = false, completion: (() -> Void)? = nil) {
        listFriendsProfiles(force: force, completion: completion)
    }
    
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
    
    public func listenToReadReceipts(chatId: String) {
        watchReadReceipts(chatId: chatId)
    }
    
    public func markAsRead(chatId: String, lastMessageId: String? = nil, lastMessageDate: Date? = nil) {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.uid // Firebase Auth UID
        let userShortId = user.userID // u_xxx
        
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
        currentMap[userShortId] = localReceipt
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
            // 送信者自身の UID / userID ではないことを確認
            let isSender = (userId == senderId) || (userId == currentUser?.uid) || (userId == currentUser?.userID)
            if !isSender {
                // 相手の lastReadDate がメッセージ作成日時以降であれば既読
                if receipt.lastReadDate >= messageDate.addingTimeInterval(-1.0) {
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
            let isSender = (userId == senderId) || (userId == currentUser?.uid) || (userId == currentUser?.userID)
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
        guard let myUid = currentUser?.uid, let myUserId = currentUser?.userID else { return 0 }
        guard let chatMessages = messages[chatId], !chatMessages.isEmpty else { return 0 }
        
        let receipts = readReceipts[chatId] ?? [:]
        let myReceipt = receipts[myUid] ?? receipts[myUserId]
        let myLastReadDate = myReceipt?.lastReadDate ?? Date.distantPast
        
        var unread = 0
        for msg in chatMessages {
            let isMine = (msg.message.senderID == myUid) || (msg.message.senderID == myUserId)
            if !isMine && msg.createdDate > myLastReadDate.addingTimeInterval(0.5) {
                unread += 1
            }
        }
        return unread
    }
    
    /// 全チャットの合計未読メッセージ数
    public var totalUnreadCount: Int {
        var total = 0
        for chat in chats {
            total += unreadCount(for: chat.chatID)
        }
        return total
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
        var total = 0
        for chat in dmChats {
            total += unreadCount(for: chat.chatID)
        }
        return total
    }
    
    // MARK: - Group Management (かいぎ)
    
    /// 新規グループチャット作成
    func createGroup(title: String, memberUids: [String], completion: @escaping (Result<FriendsChatUIModel, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let chatId = "gm_\(ULID().ulidString)"
        var allMembers = Array(Set([currentUser.uid] + memberUids))
        if allMembers.isEmpty {
            allMembers = [currentUser.uid]
        }
        
        ChatRepository.shared.createGroupChat(tenantId: tenantId, chatId: chatId, title: title, members: allMembers) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                let pbChat = FriendsChat(
                    chatID: chatId,
                    tenantID: tenantId,
                    chatType: .group,
                    members: allMembers,
                    createdAt: Date(),
                    updatedAt: Date()
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
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Message Reactions Management (7種 & 低通信量集計)
    
    /// リアクションのトグル（付加 / 切り替え / 解除）
    func toggleReaction(chatId: String, messageId: String, reactionType: FriendsReactionType) {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.uid
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


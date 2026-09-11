import Foundation
import SwiftUI
import FirebaseFirestore
import CryptoKit
import SwiftProtobuf
import ULID

// MARK: - DirectChatService
/// 友達管理、1:1 DM、1:1 E2EE暗号鍵（X25519）導出、ハイブリッドプロファイル同期を担当するサービス
@MainActor
final class DirectChatService: ObservableObject {
    static let shared = DirectChatService()
    
    @Published var friends: [FriendsPublicUserProfile] = []
    @Published var directChats: [FriendsChatUIModel] = []
    
    var dmChats: [FriendsChatUIModel] {
        get { directChats }
        set { directChats = newValue }
    }
    
    private let db = Firestore.firestore()
    private var friendListener: ListenerRegistration?
    private var directSessionKeys: [String: SymmetricKey] = [:] // chatId -> SK_direct
    
    private var currentTenant: FriendsTenant? {
        AuthService.shared.currentTenant
    }
    
    private var currentUser: FriendsPublicUserProfile? {
        AuthService.shared.currentUser
    }
    
    private init() {}
    
    // MARK: - Configuration & Lifecycle
    
    func configure(tenant: FriendsTenant, user: FriendsPublicUserProfile) {
        watchFriends()
    }
    
    func clear() {
        friendListener?.remove()
        friendListener = nil
        directSessionKeys.removeAll()
        friends.removeAll()
        directChats.removeAll()
    }
    
    // MARK: - Friends Management & Listeners
    
    func watchFriends() {
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
                    MessageService.shared.watchMessages(chatId: dmChatId, members: [currentUserId, friend.userID])
                    MessageService.shared.watchReadReceipts(chatId: dmChatId)
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
        
        guard cleanUserId != user.userID else {
            completion(.failure(NSError(domain: "FriendError", code: 400, userInfo: [NSLocalizedDescriptionKey: L10n.Error.Friend.selfAdd])))
            return
        }
        
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
                DispatchQueue.main.async {
                    self.createFriend(from: payload, explicitPasscode: cleanPasscode, completion: completion)
                }
            }
    }
    
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
        ) { result in
            if case .success = result {
                DispatchQueue.main.async {
                    AuthService.shared.currentUser?.username = cleanUsername
                }
            }
            completion(result)
        }
    }
    
    func updateFriendDisplayName(
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
    
    func deleteFriend(friendUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion(.failure(NSError(domain: "FriendError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        FriendRepository.shared.deleteFriendByUserId(tenantId: tenant.tenantID, userId: user.userID, friendUserId: friendUserId) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if case .success = result {
                    self.friends.removeAll(where: { $0.userID == friendUserId })
                }
                completion(result)
            }
        }
    }
    
    // MARK: - Direct Session Key Helper (1:1 E2EE)
    
    func getDirectSessionKey(chatId: String, tenantId: String, peerUserId: String? = nil, completion: @escaping (SymmetricKey?) -> Void) {
        if let cached = directSessionKeys[chatId] {
            completion(cached)
            return
        }
        
        guard let myUid = currentUser?.uid else {
            completion(nil)
            return
        }
        
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
                
                let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
                completion(fallbackKey)
            }
        } else {
            let fallbackKey = CryptoKeyManager.shared.getTenantMasterKey(tenantId: tenantId)
            completion(fallbackKey)
        }
    }
    
    // MARK: - Hybrid Friend Profile Sync
    
    func listFriendsProfiles(force: Bool = false, completion: (() -> Void)? = nil) {
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
    
    func friendProfile(for userId: String) -> FriendsPublicUserProfile? {
        return friends.first(where: { $0.userID == userId })
    }
    
    /// 1:1 チャットの合計未読数
    var totalDmUnreadCount: Int {
        let currentUserId = currentUser?.userID ?? ""
        var seenDmChatIds = Set<String>()
        var total = 0
        
        if !currentUserId.isEmpty {
            for friend in friends {
                let dmChatId = "dm_" + [currentUserId, friend.userID].sorted().joined(separator: "_")
                if !seenDmChatIds.contains(dmChatId) {
                    seenDmChatIds.insert(dmChatId)
                    total += MessageService.shared.unreadCount(for: dmChatId)
                }
            }
        }
        
        for chat in dmChats {
            if !seenDmChatIds.contains(chat.chatID) {
                seenDmChatIds.insert(chat.chatID)
                total += MessageService.shared.unreadCount(for: chat.chatID)
            }
        }
        
        return total
    }
}

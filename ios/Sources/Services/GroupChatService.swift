import Foundation
import SwiftUI
import FirebaseFirestore
import CryptoKit
import SwiftProtobuf
import ULID

// MARK: - GroupChatService
/// かいぎ（グループチャット）一覧、作成、削除、メンバー管理、ロール管理、KeyBucket鍵導出を担当するサービス
@MainActor
final class GroupChatService: ObservableObject {
    static let shared = GroupChatService()
    
    @Published var groupChats: [FriendsChatUIModel] = []
    @Published var groupMemberProfiles: [String: FriendsPublicUserProfile] = [:]
    
    private let db = Firestore.firestore()
    private var chatListener: ListenerRegistration?
    private var groupSessionKeys: [String: SymmetricKey] = [:] // "\(chatId)_\(keyVersion)" -> SK_group
    
    private var currentTenant: FriendsTenant? {
        AuthService.shared.currentTenant
    }
    
    private var currentUser: FriendsPublicUserProfile? {
        AuthService.shared.currentUser
    }
    
    private init() {}
    
    // MARK: - Configuration & Lifecycle
    
    func configure(tenant: FriendsTenant, user: FriendsPublicUserProfile) {
        watchGroupChats()
    }
    
    func clear() {
        chatListener?.remove()
        chatListener = nil
        groupSessionKeys.removeAll()
        groupChats.removeAll()
        groupMemberProfiles.removeAll()
    }
    
    // MARK: - Watch Group Chats (Firestore Realtime)
    
    func watchGroupChats() {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        chatListener?.remove()
        chatListener = ChatRepository.shared.watchChatsByUserId(tenantId: tenantId, userId: userId) { [weak self] fetchedChats in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let groups = fetchedChats.filter { $0.chatType == .group }
                self.groupChats = groups
                
                for group in groups {
                    MessageService.shared.watchMessages(chatId: group.chatID, members: group.chat.members)
                    MessageService.shared.watchReadReceipts(chatId: group.chatID)
                }
            }
        }
    }
    
    // MARK: - Group Session Key Helper (KeyBucket / Forward Secrecy)
    
    func getGroupSessionKey(chatId: String, tenantId: String, keyVersion: String = "v_1", completion: @escaping (SymmetricKey?) -> Void) {
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
                if let encryptedKey = bucket.encryptedGroupKeys[myUserId] {
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
    
    // MARK: - Group Chats Pull-to-Refresh & Synchronization (GP-08)
    
    func listGroupChats(force: Bool = false, completion: (() -> Void)? = nil) {
        guard let tenant = currentTenant, let user = currentUser else {
            completion?()
            return
        }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        ChatRepository.shared.listChatsByUserId(tenantId: tenantId, userId: userId) { [weak self] result in
            guard let self = self else {
                completion?()
                return
            }
            
            switch result {
            case .success(let fetchedChats):
                let groups = fetchedChats.filter { $0.chatType == .group }
                DispatchQueue.main.async {
                    self.groupChats = groups
                }
                
                var allMemberIds = Set<String>()
                for chat in groups {
                    for memberId in chat.chat.members {
                        if memberId != userId && memberId != user.uid {
                            allMemberIds.insert(memberId)
                        }
                    }
                }
                
                DirectChatService.shared.listFriendsProfiles(force: true)
                
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
                            
                            for chat in groups {
                                MessageService.shared.watchMessages(chatId: chat.chatID, members: chat.chat.members)
                                MessageService.shared.watchReadReceipts(chatId: chat.chatID)
                            }
                            completion?()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        for chat in groups {
                            MessageService.shared.watchMessages(chatId: chat.chatID, members: chat.chat.members)
                            MessageService.shared.watchReadReceipts(chatId: chat.chatID)
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
    
    // MARK: - Group Management (かいぎ)
    
    func createGroup(title: String, memberUserIds: [String], avatarImage: UIImage? = nil, completion: @escaping (Result<FriendsChatUIModel, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let chatId = "gm_\(ULID().ulidString)"
        let otherMembers = memberUserIds.filter { $0 != currentUser.userID }
        let allMembers = [currentUser.userID] + otherMembers
        
        let groupKey = CryptoKeyManager.shared.generateGroupKey()
        let keyVersion = "v_1"
        self.groupSessionKeys["\(chatId)_\(keyVersion)"] = groupKey
        
        var memberPubKeys: [String: String] = [:]
        if let myPubKey = CryptoKeyManager.shared.getPublicKeyBase64(uid: currentUser.uid) {
            memberPubKeys[currentUser.userID] = myPubKey
        }
        for mId in memberUserIds {
            if let f = DirectChatService.shared.friends.first(where: { $0.userID == mId }), !f.publicKey.isEmpty {
                memberPubKeys[mId] = f.publicKey
            }
        }
        
        let encryptedKeys = (try? CryptoKeyManager.shared.encryptGroupKeyForMembers(
            groupKey: groupKey,
            myUid: currentUser.uid,
            memberPublicKeys: memberPubKeys,
            tenantId: tenantId
        )) ?? [:]
        
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
                    var uiChat = FriendsChatUIModel(
                        chat: pbChat,
                        title: title,
                        lastMessage: "",
                        lastMessageAt: Date(),
                        unreadCount: 0
                    )
                    
                    let finishGroupCreation = {
                        DispatchQueue.main.async {
                            if !self.groupChats.contains(where: { $0.chatID == chatId }) {
                                self.groupChats.insert(uiChat, at: 0)
                            }
                            MessageService.shared.watchMessages(chatId: chatId, members: allMembers)
                            completion(.success(uiChat))
                        }
                    }
                    
                    if let img = avatarImage {
                        self.updateGroupAvatar(chatId: chatId, image: img) { avatarResult in
                            if case .success = avatarResult {
                                if let idx = self.groupChats.firstIndex(where: { $0.chatID == chatId }) {
                                    uiChat = self.groupChats[idx]
                                }
                            }
                            finishGroupCreation()
                        }
                    } else {
                        finishGroupCreation()
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteGroup(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
                    self.groupChats.removeAll(where: { $0.chatID == chatId })
                    MessageService.shared.stopWatchingMessages(chatId: chatId)
                }
            }
            completion(result)
        }
    }
    
    func assignAdmin(chatId: String, targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
    
    func claimOwnership(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let currentChat = groupChats.first(where: { $0.chatID == chatId })
        let oldOwnerId = currentChat?.ownerUserId
        
        ChatRepository.shared.claimOwnership(
            tenantId: tenant.tenantID,
            chatId: chatId,
            newOwnerId: currentUser.userID,
            oldOwnerId: oldOwnerId,
            completion: completion
        )
    }
    
    func kickMember(chatId: String, targetUserId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
    
    func leaveGroup(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        ChatRepository.shared.removeGroupMember(
            tenantId: tenant.tenantID,
            chatId: chatId,
            targetUserId: currentUser.userID,
            updatedBy: currentUser.userID
        ) { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                DispatchQueue.main.async {
                    self.groupChats.removeAll(where: { $0.chatID == chatId })
                    MessageService.shared.stopWatchingMessages(chatId: chatId)
                }
            }
            completion(result)
        }
    }
    
    func updateGroupTitle(chatId: String, newTitle: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
                    if let idx = self.groupChats.firstIndex(where: { $0.chatID == chatId }) {
                        let old = self.groupChats[idx]
                        var updatedChat = old.chat
                        updatedChat.title = newTitle
                        self.groupChats[idx] = FriendsChatUIModel(
                            chat: updatedChat,
                            title: newTitle,
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
    
    func addMembersToGroup(chatId: String, newMemberUserIds: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        
        let tenantId = tenant.tenantID
        let keyVersion = "v_1"
        
        getGroupSessionKey(chatId: chatId, tenantId: tenantId, keyVersion: keyVersion) { [weak self] resolvedGroupKey in
            guard let self = self else { return }
            guard let groupKey = resolvedGroupKey else {
                completion(.failure(NSError(domain: "GroupError", code: 500, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
                return
            }
            
            var newMemberPubKeys: [String: String] = [:]
            for mId in newMemberUserIds {
                if let f = DirectChatService.shared.friends.first(where: { $0.userID == mId }), !f.publicKey.isEmpty {
                    newMemberPubKeys[mId] = f.publicKey
                }
            }
            
            let newEncryptedKeys = (try? CryptoKeyManager.shared.encryptGroupKeyForMembers(
                groupKey: groupKey,
                myUid: currentUser.uid,
                memberPublicKeys: newMemberPubKeys,
                tenantId: tenantId
            )) ?? [:]
            
            KeyBucketRepository.shared.saveKeyBucket(
                tenantId: tenantId,
                chatId: chatId,
                keyVersion: keyVersion,
                encryptedGroupKeys: newEncryptedKeys,
                createdBy: currentUser.userID
            ) { _ in
                ChatRepository.shared.addGroupMembers(
                    tenantId: tenantId,
                    chatId: chatId,
                    newMemberUserIds: newMemberUserIds,
                    updatedBy: currentUser.userID
                ) { [weak self] result in
                    guard let self = self else { return }
                    if case .success = result {
                        DispatchQueue.main.async {
                            if let idx = self.groupChats.firstIndex(where: { $0.chatID == chatId }) {
                                let old = self.groupChats[idx]
                                var updatedChat = old.chat
                                for m in newMemberUserIds {
                                    if !updatedChat.members.contains(m) {
                                        updatedChat.members.append(m)
                                    }
                                    updatedChat.memberRoles[m] = .member
                                }
                                self.groupChats[idx] = FriendsChatUIModel(
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
    
    func updateGroupAvatar(chatId: String, image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
                    if let idx = self.groupChats.firstIndex(where: { $0.chatID == chatId }) {
                        var model = self.groupChats[idx]
                        model.avatarNonce = nonce
                        model.avatarUpdatedAt = updatedAt
                        self.groupChats[idx] = model
                    }
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func deleteGroupAvatar(chatId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let tenant = currentTenant, let currentUser = currentUser else {
            completion(.failure(NSError(domain: "GroupError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
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
                    if let idx = self.groupChats.firstIndex(where: { $0.chatID == chatId }) {
                        var model = self.groupChats[idx]
                        model.avatarNonce = ""
                        model.avatarUpdatedAt = nil
                        self.groupChats[idx] = model
                    }
                }
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func memberProfile(for userId: String) -> FriendsPublicUserProfile? {
        if let p = groupMemberProfiles[userId] {
            return p
        }
        return groupMemberProfiles.values.first(where: { $0.userID == userId })
    }
    
    /// グループチャットの合計未読数
    var totalGroupUnreadCount: Int {
        var total = 0
        for chat in groupChats {
            total += MessageService.shared.unreadCount(for: chat.chatID)
        }
        return total
    }
}

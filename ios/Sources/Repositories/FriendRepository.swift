import Foundation
import FirebaseFirestore
import SwiftProtobuf

final class FriendRepository {

    static let shared = FriendRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// 友達一覧のリアルタイム購読 (FP-01)
    func watchFriendsByUserId(
        tenantId: String,
        userId: String,
        myUid: String? = nil,
        onChange: @escaping ([FriendsPublicUserProfile]) -> Void
    ) -> ListenerRegistration {
        return db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("friends")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.error("Firestore Friends Watch Error: \(error.localizedDescription)", category: .chat)
                    return
                }
                guard let documents = snapshot?.documents else { return }
                
                var loadedFriends: [FriendsPublicUserProfile] = []
                for doc in documents {
                    let data = doc.data()
                    let fUserId = doc.documentID
                    let fPublicKey = data["friendPublicKey"] as? String ?? ""
                    var fDisplayName = ""
                    if let encName = data["encryptedFriendDisplayName"] as? String,
                       let nonce = data["friendDisplayNameNonce"] as? String {
                        // 1. 自身の秘密鍵から導出された個人専用鍵 (Personal Key) で復号を優先試行
                        if let uid = myUid,
                           let decrypted = try? CryptoKeyManager.shared.decryptWithPersonalKey(encryptedData: encName, nonce: nonce, uid: uid) {
                            fDisplayName = decrypted
                        }
                        // 2. 相手が作成した初期レコード（1:1 E2EE セッション鍵暗号化）の復号試行
                        if fDisplayName.isEmpty, let uid = myUid, !fPublicKey.isEmpty,
                           let sessionKey = try? CryptoKeyManager.shared.deriveDirectSessionKey(myUid: uid, peerPublicKeyBase64: fPublicKey, tenantId: tenantId),
                           let decrypted = try? CryptoKeyManager.shared.decryptDirectMessage(ciphertext: encName, nonce: nonce, sessionKey: sessionKey) {
                            fDisplayName = decrypted
                        }
                    }
                    
                    let fAvatarNonce = data["avatarNonce"] as? String ?? ""
                    let fAvatarUpdatedAt = (data["avatarUpdatedAt"] as? Timestamp)?.dateValue()
                    let fUsername = data["friendUsername"] as? String ?? fUserId
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    let friendProfile = FriendsPublicUserProfile(
                        userID: fUserId,
                        uid: "",
                        tenantID: tenantId,
                        displayName: fDisplayName.isEmpty ? fUsername : fDisplayName,
                        publicKey: fPublicKey,
                        avatarNonce: fAvatarNonce,
                        avatarUpdatedAt: fAvatarUpdatedAt,
                        username: fUsername,
                        createdAt: createdAt
                    )
                    loadedFriends.append(friendProfile)
                }
                onChange(loadedFriends)
            }
    }

    
    /// 友達関係の双方向アトミック追加 (FP-02)
    func createFriendBidirectional(
        tenantId: String,
        myUser: FriendsPublicUserProfile,
        friendUser: FriendsPublicUserProfile,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let sortedMembers = [myUser.userID, friendUser.userID].sorted()
        let dmChatId = "dm_" + sortedMembers.joined(separator: "_")
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(dmChatId)
        
        chatRef.getDocument { [weak self] chatSnap, _ in
            guard let self = self else { return }
            let batch = self.db.batch()
            
            // 1. 自分側のサブコレクションへ保存 (自身の秘密鍵 Personal Key で暗号化)
            let myFriendRef = self.db.collection("tenants").document(tenantId)
                .collection("users").document(myUser.userID)
                .collection("friends").document(friendUser.userID)
            
            var friendData: [String: Any] = [
                "friendUserId": friendUser.userID,
                "friendUsername": friendUser.effectiveUsername,
                "friendPublicKey": friendUser.publicKey,
                "tenantId": tenantId,
                "createdBy": myUser.userID,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedBy": myUser.userID,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if !myUser.uid.isEmpty,
               let enc = try? CryptoKeyManager.shared.encryptWithPersonalKey(plainText: friendUser.displayName, uid: myUser.uid) {
                friendData["encryptedFriendDisplayName"] = enc.encryptedData
                friendData["friendDisplayNameNonce"] = enc.nonce
            }
            batch.setData(friendData, forDocument: myFriendRef, merge: true)
            
            // 2. 相手側のサブコレクションへ保存 (1:1 E2EE セッション鍵で暗号化)
            let reverseFriendRef = self.db.collection("tenants").document(tenantId)
                .collection("users").document(friendUser.userID)
                .collection("friends").document(myUser.userID)
            
            var reverseData: [String: Any] = [
                "friendUserId": myUser.userID,
                "friendUsername": myUser.effectiveUsername,
                "friendPublicKey": myUser.publicKey,
                "tenantId": tenantId,
                "createdBy": myUser.userID,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedBy": myUser.userID,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if !myUser.uid.isEmpty, !friendUser.publicKey.isEmpty,
               let sessionKey = try? CryptoKeyManager.shared.deriveDirectSessionKey(myUid: myUser.uid, peerPublicKeyBase64: friendUser.publicKey, tenantId: tenantId),
               let enc = try? CryptoKeyManager.shared.encryptDirectMessage(plainText: myUser.displayName, sessionKey: sessionKey) {
                reverseData["encryptedFriendDisplayName"] = enc.ciphertext
                reverseData["friendDisplayNameNonce"] = enc.nonce
            }
            batch.setData(reverseData, forDocument: reverseFriendRef, merge: true)
            
            // 3. 1:1 DMチャットドキュメントが存在しない場合は同時に初期化
            if chatSnap?.exists != true {
                let chatCreateData: [String: Any] = [
                    "chatId": dmChatId,
                    "tenantId": tenantId,
                    "chatType": "direct",
                    "members": sortedMembers,
                    "lastMessage": "",
                    "lastMessageAt": FieldValue.serverTimestamp(),
                    "createdBy": myUser.userID,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedBy": myUser.userID,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                batch.setData(chatCreateData, forDocument: chatRef)
            }
            
            batch.commit { error in
                if let error = error {
                    AppLogger.error("Failed to create bidirectional friend relationship: \(error.localizedDescription)", category: .chat)
                    completion(.failure(error))
                } else {
                    AppLogger.info("Successfully created bidirectional friend relationship and DM chat: \(dmChatId)", category: .chat)
                    completion(.success(()))
                }
            }
        }
    }
    
    /// 友達削除 (FP-03)
    func deleteFriendByUserId(
        tenantId: String,
        userId: String,
        friendUserId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("friends").document(friendUserId)
            .delete { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
    }
    
    /// 友達プロファイルの一括最新化 (FP-04: 表示名 & username & アバターメタデータ)
    func listFriendsProfilesByUserIds(
        tenantId: String,
        friendUserIds: [String],
        completion: @escaping (Result<[String: (displayName: String, username: String, avatarNonce: String, avatarUpdatedAt: Date?)], Error>) -> Void
    ) {
        guard !friendUserIds.isEmpty else {
            completion(.success([:]))
            return
        }
        
        let group = DispatchGroup()
        var updatedFriendsMap: [String: (displayName: String, username: String, avatarNonce: String, avatarUpdatedAt: Date?)] = [:]
        
        for friendId in friendUserIds {
            group.enter()
            db.collection("tenants").document(tenantId).collection("users").document(friendId).getDocument { snapshot, _ in
                defer { group.leave() }
                guard let doc = snapshot, doc.exists, let data = doc.data() else { return }
                
                let fUsername = data["username"] as? String ?? friendId
                let avatarNonce = data["avatarNonce"] as? String ?? ""
                let avatarUpdatedAt = (data["avatarUpdatedAt"] as? Timestamp)?.dateValue()
                
                updatedFriendsMap[friendId] = (
                    displayName: "",
                    username: fUsername,
                    avatarNonce: avatarNonce,
                    avatarUpdatedAt: avatarUpdatedAt
                )
            }
        }
        
        group.notify(queue: .main) {
            completion(.success(updatedFriendsMap))
        }
    }
    
    /// 友達のカスタム表示名を自身の秘密鍵 (Personal Key) で暗号化して更新する (FP-05)
    func updateFriendDisplayName(
        tenantId: String,
        userId: String,
        uid: String,
        friendUserId: String,
        newDisplayName: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "FriendError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Display name cannot be empty"])))
            return
        }
        
        let encResult: (encryptedData: String, nonce: String)?
        if !uid.isEmpty,
           let enc = try? CryptoKeyManager.shared.encryptWithPersonalKey(plainText: trimmed, uid: uid) {
            encResult = enc
        } else if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: trimmed, tenantId: tenantId) {
            encResult = enc
        } else {
            encResult = nil
        }
        
        guard let (encData, nonce) = encResult else {
            completion(.failure(NSError(domain: "FriendError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to encrypt friend display name"])))
            return
        }
        
        let friendRef = db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("friends").document(friendUserId)
        
        let updateData: [String: Any] = [
            "encryptedFriendDisplayName": encData,
            "friendDisplayNameNonce": nonce,
            "updatedBy": userId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        friendRef.updateData(updateData) { error in
            if let error = error {
                AppLogger.error("Failed to update friend display name: \(error.localizedDescription)", category: .chat)
                completion(.failure(error))
            } else {
                AppLogger.info("Successfully updated friend display name for \(friendUserId)", category: .chat)
                completion(.success(()))
            }
        }
    }
}

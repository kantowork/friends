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
        onChange: @escaping ([FriendsPublicUserProfile]) -> Void
    ) -> ListenerRegistration {
        return db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("friends")
            .order(by: "addedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("⚠️ Firestore Friends Watch Error: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                
                var loadedFriends: [FriendsPublicUserProfile] = []
                for doc in documents {
                    let data = doc.data()
                    let fUserId = doc.documentID
                    let fUid = data["friendUid"] as? String ?? ""
                    var fDisplayName = data["friendDisplayName"] as? String ?? "友達"
                    
                    if let encName = data["encryptedFriendDisplayName"] as? String,
                       let nonce = data["friendDisplayNameNonce"] as? String,
                       let decrypted = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encName, nonce: nonce, tenantId: tenantId) {
                        fDisplayName = decrypted
                    }
                    
                    let fPublicKey = data["friendPublicKey"] as? String ?? ""
                    let fAvatarNonce = data["avatarNonce"] as? String ?? ""
                    let fAvatarUpdatedAt = (data["avatarUpdatedAt"] as? Timestamp)?.dateValue()
                    let fUsername = data["friendUsername"] as? String ?? fUserId
                    
                    let friendProfile = FriendsPublicUserProfile(
                        userID: fUserId,
                        uid: fUid,
                        tenantID: tenantId,
                        displayName: fDisplayName,
                        publicKey: fPublicKey,
                        avatarNonce: fAvatarNonce,
                        avatarUpdatedAt: fAvatarUpdatedAt,
                        username: fUsername
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
        let batch = db.batch()
        
        // 1. 自分側のサブコレクションへ保存
        let myFriendRef = db.collection("tenants").document(tenantId)
            .collection("users").document(myUser.userID)
            .collection("friends").document(friendUser.userID)
        
        var friendData: [String: Any] = [
            "friendUserId": friendUser.userID,
            "friendUid": friendUser.uid,
            "friendUsername": friendUser.effectiveUsername,
            "friendDisplayName": friendUser.displayName,
            "friendPublicKey": friendUser.publicKey,
            "tenantId": tenantId,
            "addedAt": FieldValue.serverTimestamp()
        ]
        if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: friendUser.displayName, tenantId: tenantId) {
            friendData["encryptedFriendDisplayName"] = enc.encryptedData
            friendData["friendDisplayNameNonce"] = enc.nonce
        }
        batch.setData(friendData, forDocument: myFriendRef, merge: true)
        
        // 2. 相手側のサブコレクションへ保存
        let reverseFriendRef = db.collection("tenants").document(tenantId)
            .collection("users").document(friendUser.userID)
            .collection("friends").document(myUser.userID)
        
        var reverseData: [String: Any] = [
            "friendUserId": myUser.userID,
            "friendUid": myUser.uid,
            "friendUsername": myUser.effectiveUsername,
            "friendDisplayName": myUser.displayName,
            "friendPublicKey": myUser.publicKey,
            "tenantId": tenantId,
            "addedAt": FieldValue.serverTimestamp()
        ]
        if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: myUser.displayName, tenantId: tenantId) {
            reverseData["encryptedFriendDisplayName"] = enc.encryptedData
            reverseData["friendDisplayNameNonce"] = enc.nonce
        }
        batch.setData(reverseData, forDocument: reverseFriendRef, merge: true)
        
        batch.commit { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
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
                
                var resolvedName = data["displayName"] as? String ?? ""
                if let encName = data["encryptedDisplayName"] as? String,
                   let nonce = data["displayNameNonce"] as? String,
                   let decrypted = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encName, nonce: nonce, tenantId: tenantId) {
                    resolvedName = decrypted
                }
                
                let fUsername = data["username"] as? String ?? friendId
                let avatarNonce = data["avatarNonce"] as? String ?? ""
                let avatarUpdatedAt = (data["avatarUpdatedAt"] as? Timestamp)?.dateValue()
                
                updatedFriendsMap[friendId] = (
                    displayName: resolvedName,
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

}

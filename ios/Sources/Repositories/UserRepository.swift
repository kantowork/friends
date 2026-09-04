import Foundation
import FirebaseFirestore

final class UserRepository {
    static let shared = UserRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// ユーザー非公開復元データ登録 (UP-02)
    func setUserPrivateDataByUid(uid: String, data: FriendsUserPrivateData, completion: @escaping (Result<Void, Error>) -> Void) {
        let payload: [String: Any] = [
            "uid": data.uid,
            "recoveryHash": data.recoveryHash,
            "encryptedPrivateKey": data.encryptedPrivateKey,
            "nonce": data.nonce,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid).collection("private").document("data").setData(payload, merge: true) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// ユーザー非公開復元データ取得 (UP-03)
    func getUserPrivateDataByUid(uid: String, completion: @escaping (Result<FriendsUserPrivateData, Error>) -> Void) {
        db.collection("users").document(uid).collection("private").document("data").getDocument { doc, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let doc = doc, doc.exists, let data = doc.data() else {
                completion(.failure(NSError(domain: "UserError", code: 404, userInfo: [NSLocalizedDescriptionKey: "復元データが見つかりません。"])))
                return
            }
            
            var privateData = FriendsUserPrivateData()
            privateData.uid = uid
            privateData.recoveryHash = data["recoveryHash"] as? String ?? ""
            privateData.encryptedPrivateKey = data["encryptedPrivateKey"] as? String ?? ""
            privateData.nonce = data["nonce"] as? String ?? ""
            completion(.success(privateData))
        }
    }
    
    /// テナント内プロファイル取得 (UP-04)
    func getUserProfileByUserId(tenantId: String, userId: String, completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void) {
        db.collection("tenants").document(tenantId).collection("users").document(userId).getDocument { [weak self] doc, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let doc = doc, doc.exists else {
                completion(.failure(NSError(domain: "UserError", code: 404, userInfo: [NSLocalizedDescriptionKey: "ユーザープロファイルが見つかりません。"])))
                return
            }
            
            let user = self.mapPublicUserProfile(doc: doc, tenantId: tenantId)
            completion(.success(user))
        }
    }
    
    /// Auth UID からテナント内プロファイル取得
    func getUserProfileByUid(tenantId: String, uid: String, completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void) {
        db.collection("tenants").document(tenantId).collection("users").whereField("uid", isEqualTo: uid).limit(to: 1).getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let snapshot = snapshot, let doc = snapshot.documents.first else {
                completion(.failure(NSError(domain: "UserError", code: 404, userInfo: [NSLocalizedDescriptionKey: "ユーザープロファイルが見つかりません。"])))
                return
            }
            let user = self.mapPublicUserProfile(doc: doc, tenantId: tenantId)
            completion(.success(user))
        }
    }
    
    /// テナント内プロファイル作成/更新 (UP-05)
    func createOrUpdateUserProfile(tenantId: String, user: FriendsPublicUserProfile, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanUsername = user.username.isEmpty ? user.userID : user.username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var userData: [String: Any] = [
            "userId": user.userID,
            "uid": user.uid,
            "username": cleanUsername,
            "tenantId": tenantId,
            "publicKey": user.publicKey,
            "role": user.role.rawValue,
            "accountType": user.accountType.rawValue,
            "createdBy": user.userID,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedBy": user.userID,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if !user.encryptedDisplayName.isEmpty {
            userData["encryptedDisplayName"] = user.encryptedDisplayName
            userData["displayNameNonce"] = user.displayNameNonce
        }
        
        let batch = db.batch()
        let tenantUserRef = db.collection("tenants").document(tenantId).collection("users").document(user.userID)
        batch.setData(userData, forDocument: tenantUserRef, merge: true)
        
        // ユーザー名インデックス (/tenants/{tenantId}/usernames/{username})
        let usernameRef = db.collection("tenants").document(tenantId).collection("usernames").document(cleanUsername)
        batch.setData([
            "userId": user.userID,
            "uid": user.uid,
            "tenantId": tenantId,
            "createdBy": user.userID,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedBy": user.userID,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: usernameRef, merge: true)
        
        let globalUserRef = db.collection("users").document(user.uid)
        batch.setData([
            "uid": user.uid,
            "publicKey": user.publicKey,
            "defaultTenantId": tenantId,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: globalUserRef, merge: true)
        
        batch.commit { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// username でユーザープロファイル検索 (UP-07)
    func getUserProfileByUsername(tenantId: String, username: String, completion: @escaping (Result<FriendsPublicUserProfile, Error>) -> Void) {
        let clean = username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        db.collection("tenants").document(tenantId).collection("usernames").document(clean).getDocument { [weak self] doc, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let doc = doc, doc.exists, let data = doc.data(), let userId = data["userId"] as? String else {
                let err = NSError(domain: "UserError", code: 404, userInfo: [NSLocalizedDescriptionKey: "ユーザーが見つかりません。"])
                completion(.failure(err))
                return
            }
            self.getUserProfileByUserId(tenantId: tenantId, userId: userId, completion: completion)
        }
    }
    
    /// username 更新 & 旧インデックス削除 (UP-08)
    func updateUsername(tenantId: String, userId: String, uid: String, oldUsername: String, newUsername: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanOld = oldUsername.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNew = newUsername.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard cleanNew != cleanOld else {
            completion(.success(()))
            return
        }
        
        let newUsernameRef = db.collection("tenants").document(tenantId).collection("usernames").document(cleanNew)
        let oldUsernameRef = db.collection("tenants").document(tenantId).collection("usernames").document(cleanOld)
        let userRef = db.collection("tenants").document(tenantId).collection("users").document(userId)
        
        // 重複チェックおよび旧インデックスの存在確認
        newUsernameRef.getDocument { [weak self] newSnap, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            if let snapshot = newSnap, snapshot.exists, let ownerUid = snapshot.data()?["uid"] as? String, ownerUid != uid {
                let err = NSError(domain: "UserError", code: 409, userInfo: [NSLocalizedDescriptionKey: "このユーザー名は既に使用されています。"])
                completion(.failure(err))
                return
            }
            
            // 旧インデックスの存在確認
            let handleBatchWrite = { (deleteOld: Bool) in
                let batch = self.db.batch()
                var usernameData: [String: Any] = [
                    "userId": userId,
                    "uid": uid,
                    "tenantId": tenantId,
                    "createdBy": userId,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedBy": userId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                batch.setData(usernameData, forDocument: newUsernameRef, merge: true)
                
                batch.updateData([
                    "username": cleanNew,
                    "updatedBy": userId,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: userRef)
                
                if deleteOld {
                    batch.deleteDocument(oldUsernameRef)
                }
                
                batch.commit { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
            
            if !cleanOld.isEmpty && cleanOld != cleanNew {
                oldUsernameRef.getDocument { oldSnap, _ in
                    let shouldDelete = (oldSnap?.exists == true && oldSnap?.data()?["uid"] as? String == uid)
                    handleBatchWrite(shouldDelete)
                }
            } else {
                handleBatchWrite(false)
            }
        }
    }
    
    /// 表示名更新 (UP-06 / patch)
    func patchDisplayNameByUserId(tenantId: String, userId: String, encryptedDisplayName: String, nonce: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let updates: [String: Any] = [
            "encryptedDisplayName": encryptedDisplayName,
            "displayNameNonce": nonce,
            "updatedBy": userId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        db.collection("tenants").document(tenantId).collection("users").document(userId).updateData(updates) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    func mapPublicUserProfile(doc: DocumentSnapshot, tenantId: String) -> FriendsPublicUserProfile {
        let data = doc.data() ?? [:]
        let uId = data["uid"] as? String ?? ""
        let pubKey = data["publicKey"] as? String ?? ""
        let roleVal = data["role"] as? Int ?? 1
        let accTypeVal = data["accountType"] as? Int ?? 1
        let encryptedName = data["encryptedDisplayName"] as? String ?? ""
        let nameNonce = data["displayNameNonce"] as? String ?? ""
        let avatarNonce = data["avatarNonce"] as? String ?? ""
        let avatarUpdatedAt = (data["avatarUpdatedAt"] as? Timestamp)?.dateValue()
        let usernameVal = data["username"] as? String ?? String(doc.documentID.prefix(10))
        let createdBy = data["createdBy"] as? String ?? doc.documentID
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedBy = data["updatedBy"] as? String ?? doc.documentID
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        var resolvedName = ""
        if !encryptedName.isEmpty {
            if let decrypted = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: encryptedName, nonce: nameNonce, tenantId: tenantId) {
                resolvedName = decrypted
            }
        }
        
        return FriendsPublicUserProfile(
            userID: doc.documentID,
            uid: uId,
            tenantID: tenantId,
            displayName: resolvedName,
            publicKey: pubKey,
            role: FriendsUserRole(rawValue: roleVal) ?? .member,
            accountType: FriendsAccountType(rawValue: accTypeVal) ?? .persistent,
            encryptedDisplayName: encryptedName,
            displayNameNonce: nameNonce,
            avatarNonce: avatarNonce,
            avatarUpdatedAt: avatarUpdatedAt,
            username: usernameVal,
            createdBy: createdBy,
            createdAt: createdAt,
            updatedBy: updatedBy,
            updatedAt: updatedAt
        )
    }
}

import Foundation
import FirebaseFirestore

final class KeyBucketRepository {
    static let shared = KeyBucketRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// グループ鍵バケットの保存 (KP-01)
    func saveKeyBucket(
        tenantId: String,
        chatId: String,
        keyVersion: String,
        encryptedGroupKeys: [String: String],
        createdBy: String = "",
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let bucketRef = db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("keys").document(keyVersion)
        
        var data: [String: Any] = [
            "keyVersion": keyVersion,
            "chatId": chatId,
            "tenantId": tenantId,
            "encryptedGroupKeys": encryptedGroupKeys,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if !createdBy.isEmpty {
            data["createdBy"] = createdBy
            data["updatedBy"] = createdBy
        }
        
        bucketRef.setData(data, merge: true) { error in
            if let error = error {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }
    }
    
    /// グループ鍵バケットの取得 (KP-02)
    func getKeyBucket(
        tenantId: String,
        chatId: String,
        keyVersion: String,
        completion: @escaping (Result<FriendsKeyBucket, Error>) -> Void
    ) {
        let bucketRef = db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("keys").document(keyVersion)
        
        bucketRef.getDocument(completion: { (snapshot: DocumentSnapshot?, error: Error?) in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let snapshot = snapshot, snapshot.exists, let data = snapshot.data() else {
                completion(.failure(NSError(domain: "KeyBucketRepository", code: 404, userInfo: [NSLocalizedDescriptionKey: "KeyBucket not found"])))
                return
            }
            
            let encKeys = data["encryptedGroupKeys"] as? [String: String] ?? [:]
            let createdBy = data["createdBy"] as? String ?? ""
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedBy = data["updatedBy"] as? String ?? createdBy
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
            
            let bucket = FriendsKeyBucket(
                keyVersion: keyVersion,
                chatID: chatId,
                tenantID: tenantId,
                encryptedGroupKeys: encKeys,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedBy: updatedBy,
                updatedAt: updatedAt
            )
            completion(.success(bucket))
        })
    }
}

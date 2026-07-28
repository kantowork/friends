import Foundation
import FirebaseFirestore

final class ReactionRepository {
    static let shared = ReactionRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// メッセージリアクションのリアルタイム購読 (RP-01)
    func watchReactionsByMessageId(
        tenantId: String,
        chatId: String,
        messageId: String,
        onChange: @escaping ([FriendsMessageReaction]) -> Void
    ) -> ListenerRegistration {
        return db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("messages").document(messageId)
            .collection("reactions")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("⚠️ Firestore Reactions Watch Error: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                
                var reactions: [FriendsMessageReaction] = []
                for doc in documents {
                    let data = doc.data()
                    let reactionId = data["reactionId"] as? String ?? doc.documentID
                    let uId = data["userId"] as? String ?? ""
                    let uName = data["userName"] as? String ?? "ユーザー"
                    let reactionTypeStr = data["reactionType"] as? String ?? ""
                    let rType = FriendsReactionType.fromKey(reactionTypeStr)
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    let item = FriendsMessageReaction(
                        reactionID: reactionId,
                        messageID: messageId,
                        chatID: chatId,
                        tenantID: tenantId,
                        userID: uId,
                        userName: uName,
                        reactionType: rType,
                        createdAt: createdAt
                    )
                    reactions.append(item)
                }
                onChange(reactions)
            }
    }
    
    /// リアクション追加または変更 (RP-02)
    func setReactionByUserId(
        tenantId: String,
        chatId: String,
        messageId: String,
        userId: String,
        userName: String,
        reactionType: FriendsReactionType,
        previousReaction: FriendsReactionType?,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let messageDocRef = db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("messages").document(messageId)
        
        let userReactionDocRef = messageDocRef.collection("reactions").document(userId)
        
        let reactionData: [String: Any] = [
            "reactionId": "r_\(userId)",
            "messageId": messageId,
            "chatId": chatId,
            "tenantId": tenantId,
            "userId": userId,
            "userName": userName,
            "reactionType": reactionType.key,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        userReactionDocRef.setData(reactionData, merge: true) { error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            
            var updates: [String: Any] = [
                "reactionCounts.\(reactionType.key)": FieldValue.increment(Int64(1)),
                "updatedAt": FieldValue.serverTimestamp()
            ]
            if let prev = previousReaction {
                updates["reactionCounts.\(prev.key)"] = FieldValue.increment(Int64(-1))
            }
            
            messageDocRef.updateData(updates) { err in
                if let err = err {
                    completion?(.failure(err))
                } else {
                    completion?(.success(()))
                }
            }
        }
    }
    
    /// リアクション解除 (RP-03)
    func deleteReactionByUserId(
        tenantId: String,
        chatId: String,
        messageId: String,
        userId: String,
        reactionType: FriendsReactionType,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let messageDocRef = db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("messages").document(messageId)
        
        let userReactionDocRef = messageDocRef.collection("reactions").document(userId)
        
        userReactionDocRef.delete { error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            
            messageDocRef.updateData([
                "reactionCounts.\(reactionType.key)": FieldValue.increment(Int64(-1)),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { err in
                if let err = err {
                    completion?(.failure(err))
                } else {
                    completion?(.success(()))
                }
            }
        }
    }
    
    /// メッセージの全リアクション詳細一覧取得
    func listReactionDetailsByMessageId(
        tenantId: String,
        chatId: String,
        messageId: String,
        completion: @escaping (Result<[FriendsMessageReaction], Error>) -> Void
    ) {
        db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("messages").document(messageId)
            .collection("reactions")
            .order(by: "createdAt", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                var reactions: [FriendsMessageReaction] = []
                for doc in documents {
                    let data = doc.data()
                    let reactionId = data["reactionId"] as? String ?? doc.documentID
                    let uId = data["userId"] as? String ?? ""
                    let uName = data["userName"] as? String ?? "ユーザー"
                    let reactionTypeStr = data["reactionType"] as? String ?? ""
                    let rType = FriendsReactionType.fromKey(reactionTypeStr)
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    let item = FriendsMessageReaction(
                        reactionID: reactionId,
                        messageID: messageId,
                        chatID: chatId,
                        tenantID: tenantId,
                        userID: uId,
                        userName: uName,
                        reactionType: rType,
                        createdAt: createdAt
                    )
                    reactions.append(item)
                }
                completion(.success(reactions))
            }
    }
}

import Foundation
import FirebaseFirestore

final class ReadReceiptRepository {
    static let shared = ReadReceiptRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// チャットの既読状態リアルタイム購読 (RR-01)
    func watchReadReceiptsByChatId(
        tenantId: String,
        chatId: String,
        onChange: @escaping ([String: FriendsReadReceipt]) -> Void
    ) -> ListenerRegistration {
        return db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("receipts")
            .addSnapshotListener { snapshot, error in
                if error != nil {
                    return
                }
                guard let documents = snapshot?.documents else { return }
                
                var receiptsMap: [String: FriendsReadReceipt] = [:]
                for doc in documents {
                    let data = doc.data()
                    let userId = doc.documentID
                    let lastReadMessageId = data["lastReadMessageId"] as? String ?? ""
                    let lastReadAt = (data["lastReadAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    let createdBy = data["createdBy"] as? String ?? userId
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? updatedAt
                    let updatedBy = data["updatedBy"] as? String ?? userId
                    
                    let receipt = FriendsReadReceipt(
                        userID: userId,
                        chatID: chatId,
                        tenantID: tenantId,
                        lastReadMessageID: lastReadMessageId,
                        lastReadAt: lastReadAt,
                        createdBy: createdBy,
                        createdAt: createdAt,
                        updatedBy: updatedBy,
                        updatedAt: updatedAt
                    )
                    receiptsMap[userId] = receipt
                }
                onChange(receiptsMap)
            }
    }
    
    /// 既読カーソルの更新 (RR-02 / patch)
    func patchReadReceiptByUserId(
        tenantId: String,
        chatId: String,
        userId: String,
        lastReadMessageId: String,
        lastReadAt: Date,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let receiptRef = db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("receipts").document(userId)
        
        receiptRef.getDocument { snapshot, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            
            let exists = snapshot?.exists ?? false
            if exists {
                let updateData: [String: Any] = [
                    "lastReadMessageId": lastReadMessageId,
                    "lastReadAt": Timestamp(date: lastReadAt),
                    "updatedBy": userId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                receiptRef.updateData(updateData) { err in
                    if let err = err {
                        completion?(.failure(err))
                    } else {
                        completion?(.success(()))
                    }
                }
            } else {
                let createData: [String: Any] = [
                    "userId": userId,
                    "chatId": chatId,
                    "tenantId": tenantId,
                    "lastReadMessageId": lastReadMessageId,
                    "lastReadAt": Timestamp(date: lastReadAt),
                    "createdBy": userId,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedBy": userId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                receiptRef.setData(createData) { err in
                    if let err = err {
                        completion?(.failure(err))
                    } else {
                        completion?(.success(()))
                    }
                }
            }
        }
    }
}

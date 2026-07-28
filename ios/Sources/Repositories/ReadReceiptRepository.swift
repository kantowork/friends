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
                if let error = error {
                    print("⚠️ Firestore Read Receipts Watch Error [\(chatId)]: \(error.localizedDescription)")
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
                    
                    let receipt = FriendsReadReceipt(
                        userID: userId,
                        chatID: chatId,
                        tenantID: tenantId,
                        lastReadMessageID: lastReadMessageId,
                        lastReadAt: lastReadAt,
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
        
        let receiptData: [String: Any] = [
            "userId": userId,
            "chatId": chatId,
            "tenantId": tenantId,
            "lastReadMessageId": lastReadMessageId,
            "lastReadAt": Timestamp(date: lastReadAt),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        receiptRef.setData(receiptData, merge: true) { error in
            if let error = error {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }
    }
}

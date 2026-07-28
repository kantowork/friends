import Foundation
import FirebaseFirestore

final class MessageRepository {
    static let shared = MessageRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// 新着メッセージのリアルタイム購読 (MP-01)
    func watchMessagesByChatId(
        tenantId: String,
        chatId: String,
        limit: Int = 100,
        onChange: @escaping ([FriendsMessage]) -> Void
    ) -> ListenerRegistration {
        return db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(toLast: limit)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("⚠️ Firestore Messages Watch Error [\(chatId)]: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                
                var newMessages: [FriendsMessage] = []
                for doc in documents {
                    let data = doc.data()
                    let messageId = doc.documentID
                    let senderId = data["senderId"] as? String ?? ""
                    let keyVersion = data["keyVersion"] as? String ?? "v_1"
                    let payloadData = data["encryptedPayload"] as? [String: Any] ?? [:]
                    let ciphertext = payloadData["ciphertext"] as? String ?? ""
                    let nonce = payloadData["nonce"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    var reactionCounts: [String: Int32] = [:]
                    if let rawCounts = data["reactionCounts"] as? [String: Any] {
                        for (k, v) in rawCounts {
                            if let intVal = v as? Int32 {
                                reactionCounts[k] = intVal
                            } else if let intVal = v as? Int {
                                reactionCounts[k] = Int32(intVal)
                            }
                        }
                    }
                    
                    let msg = FriendsMessage(
                        messageID: messageId,
                        tenantID: tenantId,
                        chatID: chatId,
                        senderID: senderId,
                        keyVersion: keyVersion,
                        ciphertext: ciphertext,
                        nonce: nonce,
                        messageType: .text,
                        createdAt: createdAt,
                        reactionCounts: reactionCounts
                    )
                    newMessages.append(msg)
                }
                onChange(newMessages)
            }
    }
    
    /// 1:1 DM チャット親ドキュメントの安全な初期化 (userId 昇順・厳格な2要素)
    func createDirectChatIfNotExists(
        tenantId: String,
        chatId: String,
        members: [String],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let sortedMembers = members.sorted()
        let chatData: [String: Any] = [
            "chatId": chatId,
            "tenantId": tenantId,
            "chatType": "direct",
            "members": sortedMembers,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.setData(chatData, merge: true) { error in
            if let error = error {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }
    }
    
    /// 暗号化メッセージの送信・追記 (MP-02)
    func createMessage(
        tenantId: String,
        chatId: String,
        message: FriendsMessage,
        members: [String]? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let messageData: [String: Any] = [
            "messageId": message.messageID,
            "tenantId": tenantId,
            "chatId": chatId,
            "senderId": message.senderID,
            "keyVersion": message.keyVersion,
            "encryptedPayload": [
                "ciphertext": message.encryptedPayload.ciphertext,
                "nonce": message.encryptedPayload.nonce
            ],
            "messageType": "text",
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        
        var chatUpdateData: [String: Any] = [
            "chatId": chatId,
            "tenantId": tenantId,
            "createdAt": FieldValue.serverTimestamp(),
            "lastMessageAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        if let members = members, !members.isEmpty {
            if chatId.hasPrefix("dm_") {
                chatUpdateData["chatType"] = "direct"
                chatUpdateData["members"] = members.sorted()
            } else if chatId.hasPrefix("gm_") {
                chatUpdateData["chatType"] = "group"
                chatUpdateData["members"] = members
            }
        }
        
        // チャット更新時刻をセットしつつメッセージをサブコレクションへ書き込み
        chatRef.setData(chatUpdateData, merge: true) { error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            
            chatRef.collection("messages").document(message.messageID).setData(messageData) { error in
                if let error = error {
                    completion?(.failure(error))
                } else {
                    completion?(.success(()))
                }
            }
        }
    }
}

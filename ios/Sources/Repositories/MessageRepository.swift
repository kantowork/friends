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
                if error != nil {
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
                    
                    let createdBy = data["createdBy"] as? String ?? senderId
                    let updatedBy = data["updatedBy"] as? String ?? senderId
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
                    
                    let msg = FriendsMessage(
                        messageID: messageId,
                        tenantID: tenantId,
                        chatID: chatId,
                        senderID: senderId,
                        keyVersion: keyVersion,
                        ciphertext: ciphertext,
                        nonce: nonce,
                        messageType: .text,
                        createdBy: createdBy,
                        createdAt: createdAt,
                        updatedBy: updatedBy,
                        updatedAt: updatedAt,
                        reactionCounts: reactionCounts
                    )
                    newMessages.append(msg)
                }
                onChange(newMessages)
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
        let senderId = message.senderID
        let messageData: [String: Any] = [
            "messageId": message.messageID,
            "tenantId": tenantId,
            "chatId": chatId,
            "senderId": senderId,
            "keyVersion": message.keyVersion,
            "encryptedPayload": [
                "ciphertext": message.encryptedPayload.ciphertext,
                "nonce": message.encryptedPayload.nonce
            ],
            "messageType": "text",
            "createdBy": senderId,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedBy": senderId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        
        // 親チャットドキュメントの存在確認を行い、作成時(Create)と更新時(Update)で監査フィールドを正しく分岐
        chatRef.getDocument { snapshot, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            
            let exists = snapshot?.exists ?? false
            if exists {
                // 既存チャットの更新 (Update): createdBy/createdAt は含めず、updatedBy/updatedAt/lastMessageAt のみを更新
                let chatUpdateData: [String: Any] = [
                    "lastMessageAt": FieldValue.serverTimestamp(),
                    "updatedBy": senderId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                chatRef.updateData(chatUpdateData) { err in
                    if let err = err {
                        completion?(.failure(err))
                        return
                    }
                    self.writeMessageDocument(chatRef: chatRef, messageId: message.messageID, messageData: messageData, senderId: senderId, completion: completion)
                }
            } else {
                // 新規チャットの作成 (Create): createdBy, createdAt, updatedBy, updatedAt が完全一致する監査メタデータをセット
                var chatCreateData: [String: Any] = [
                    "chatId": chatId,
                    "tenantId": tenantId,
                    "chatType": chatId.hasPrefix("gm_") ? "group" : "direct",
                    "members": (members ?? [senderId]).sorted(),
                    "lastMessage": "",
                    "lastMessageAt": FieldValue.serverTimestamp(),
                    "createdBy": senderId,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedBy": senderId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                if chatId.hasPrefix("gm_") {
                    chatCreateData["title"] = "かいぎ"
                }
                
                chatRef.setData(chatCreateData) { err in
                    if let err = err {
                        completion?(.failure(err))
                        return
                    }
                    self.writeMessageDocument(chatRef: chatRef, messageId: message.messageID, messageData: messageData, senderId: senderId, completion: completion)
                }
            }
        }
    }
    
    private func writeMessageDocument(
        chatRef: DocumentReference,
        messageId: String,
        messageData: [String: Any],
        senderId: String,
        completion: ((Result<Void, Error>) -> Void)?
    ) {
        chatRef.collection("messages").document(messageId).setData(messageData) { error in
            if let error = error {
                completion?(.failure(error))
            } else {
                completion?(.success(()))
            }
        }
    }
}

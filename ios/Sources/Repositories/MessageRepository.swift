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
                    AppLogger.error("Failed to watch messages for chat \(chatId): \(error.localizedDescription)", category: .chat)
                    return
                }
                guard let documents = snapshot?.documents else {
                    return
                }
                
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
        let messageRef = chatRef.collection("messages").document(message.messageID)
        
        chatRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                AppLogger.error("Failed to check chat doc existence: \(error.localizedDescription)", category: .chat)
                completion?(.failure(error))
                return
            }
            
            let exists = snapshot?.exists ?? false
            
            if exists {
                // 既存チャットの更新 (Update): createdBy/createdAt は含めず、updatedBy/updatedAt/lastMessageAt のみを更新
                let batch = self.db.batch()
                let chatUpdateData: [String: Any] = [
                    "lastMessageAt": FieldValue.serverTimestamp(),
                    "updatedBy": senderId,
                    "updatedAt": FieldValue.serverTimestamp()
                ]
                batch.updateData(chatUpdateData, forDocument: chatRef)
                batch.setData(messageData, forDocument: messageRef)
                
                batch.commit { batchError in
                    if let batchError = batchError {
                        AppLogger.error("Failed to commit message batch: \(batchError.localizedDescription)", category: .chat)
                        completion?(.failure(batchError))
                    } else {
                        AppLogger.info("Successfully created message \(message.messageID) in chat \(chatId)", category: .chat)
                        completion?(.success(()))
                    }
                }
            } else {
                // 新規チャットの作成 (Create):
                // 親チャットが Firestore に存在しない場合、同一バッチだとメッセージのセキュリティルール (isChatMember) の exists(chatPath) が false になるため、
                // 親チャットの作成コミット後にメッセージドキュメントを書き込む。
                let sortedMembers: [String]
                if let m = members, !m.isEmpty {
                    var combined = m
                    if !combined.contains(senderId) {
                        combined.append(senderId)
                    }
                    sortedMembers = Array(Set(combined)).sorted()
                } else if chatId.hasPrefix("dm_") {
                    // dm_u_xxx_u_yyy から u_xxx, u_yyy を安全に抽出
                    let parts = chatId.components(separatedBy: "_")
                    var rec: [String] = []
                    for idx in 0..<parts.count - 1 where parts[idx] == "u" {
                        rec.append("u_" + parts[idx + 1])
                    }
                    if !rec.contains(senderId) {
                        rec.append(senderId)
                    }
                    sortedMembers = Array(Set(rec)).sorted()
                } else {
                    sortedMembers = [senderId]
                }
                
                var chatCreateData: [String: Any] = [
                    "chatId": chatId,
                    "tenantId": tenantId,
                    "chatType": chatId.hasPrefix("gm_") ? "group" : "direct",
                    "members": sortedMembers,
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
                
                chatRef.setData(chatCreateData) { createError in
                    if let createError = createError {
                        AppLogger.error("Failed to create parent chat \(chatId): \(createError.localizedDescription)", category: .chat)
                        completion?(.failure(createError))
                        return
                    }
                    
                    messageRef.setData(messageData) { msgError in
                        if let msgError = msgError {
                            AppLogger.error("Failed to set message document: \(msgError.localizedDescription)", category: .chat)
                            completion?(.failure(msgError))
                        } else {
                            AppLogger.info("Successfully created chat \(chatId) and message \(message.messageID)", category: .chat)
                            completion?(.success(()))
                        }
                    }
                }
            }
        }
    }
}

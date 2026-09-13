import Foundation
import FirebaseAuth
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
                
                let messages: [FriendsMessage] = documents.compactMap { doc in
                    let data = doc.data()
                    guard let messageId = data["messageId"] as? String,
                          let senderId = data["senderId"] as? String,
                          let encPayload = data["encryptedPayload"] as? [String: Any],
                          let ciphertext = encPayload["ciphertext"] as? String,
                          let nonce = encPayload["nonce"] as? String else {
                        return nil
                    }
                    
                    let keyVersion = (data["keyVersion"] as? String) ?? "v_1"
                    let createdDate = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let typeString = (data["messageType"] as? String) ?? "text"
                    let messageType: FriendsMessageType = (typeString == "image") ? .image : .text
                    
                    return FriendsMessage(
                        messageID: messageId,
                        tenantID: tenantId,
                        chatID: chatId,
                        senderID: senderId,
                        keyVersion: keyVersion,
                        ciphertext: ciphertext,
                        nonce: nonce,
                        messageType: messageType,
                        createdAt: createdDate
                    )
                }
                onChange(messages)
            }
    }
    
    /// 過去メッセージの遡り取得（ページネーション: 指定メッセージより古いものを取得）
    func fetchMessagesBefore(
        tenantId: String,
        chatId: String,
        beforeDate: Date,
        limit: Int = 30,
        completion: @escaping (Result<[FriendsMessage], Error>) -> Void
    ) {
        db.collection("tenants").document(tenantId)
            .collection("chats").document(chatId)
            .collection("messages")
            .order(by: "createdAt", descending: true)
            .whereField("createdAt", isLessThan: Timestamp(date: beforeDate))
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    AppLogger.error("Failed to fetch older messages for chat \(chatId): \(error.localizedDescription)", category: .chat)
                    completion(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let messages: [FriendsMessage] = documents.compactMap { doc in
                    let data = doc.data()
                    guard let messageId = data["messageId"] as? String,
                          let senderId = data["senderId"] as? String,
                          let encPayload = data["encryptedPayload"] as? [String: Any],
                          let ciphertext = encPayload["ciphertext"] as? String,
                          let nonce = encPayload["nonce"] as? String else {
                        return nil
                    }
                    
                    let keyVersion = (data["keyVersion"] as? String) ?? "v_1"
                    let createdDate = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let typeString = (data["messageType"] as? String) ?? "text"
                    let messageType: FriendsMessageType = (typeString == "image") ? .image : .text
                    
                    return FriendsMessage(
                        messageID: messageId,
                        tenantID: tenantId,
                        chatID: chatId,
                        senderID: senderId,
                        keyVersion: keyVersion,
                        ciphertext: ciphertext,
                        nonce: nonce,
                        messageType: messageType,
                        createdAt: createdDate
                    )
                }.reversed()
                
                completion(.success(messages))
            }
    }
    
    /// 暗号化メッセージの送信 (Cloudflare Workers API: POST /api/v1/tenants/:tenantId/chats/:chatId/messages)
    func createMessage(
        tenantId: String,
        chatId: String,
        message: FriendsMessage,
        members: [String]? = nil,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard let baseURL = WorkerConfig.baseURL else {
            let error = NSError(domain: "MessageRepository", code: 400, userInfo: [NSLocalizedDescriptionKey: "WorkerConfig.baseURL is nil"])
            AppLogger.error("Cannot send message: \(error.localizedDescription)", category: .chat)
            completion?(.failure(error))
            return
        }
        
        let path = "api/v1/tenants/\(tenantId)/chats/\(chatId)/messages"
        let endpointUrl = baseURL.appendingPathComponent(path)
        
        guard let currentUser = Auth.auth().currentUser else {
            let error = NSError(domain: "MessageRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "CurrentUser is nil"])
            AppLogger.error("Cannot send message: \(error.localizedDescription)", category: .chat)
            completion?(.failure(error))
            return
        }
        
        currentUser.getIDToken { token, error in
            if let error = error {
                AppLogger.error("Failed to get ID token: \(error.localizedDescription)", category: .chat)
                completion?(.failure(error))
                return
            }
            guard let token = token else {
                let err = NSError(domain: "MessageRepository", code: 401, userInfo: [NSLocalizedDescriptionKey: "ID token is nil"])
                completion?(.failure(err))
                return
            }
            
            var request = URLRequest(url: endpointUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let typeString = (message.messageType == .image) ? "image" : "text"
            let payload = SendMessagePayload(
                messageId: message.messageID,
                tenantId: tenantId,
                chatId: chatId,
                senderId: message.senderID,
                keyVersion: message.keyVersion,
                ciphertext: message.encryptedPayload.ciphertext,
                nonce: message.encryptedPayload.nonce,
                messageType: typeString
            )
            let reqBody = SendMessageRequest(message: payload, members: members)
            
            do {
                request.httpBody = try JSONEncoder().encode(reqBody)
            } catch {
                AppLogger.error("Failed to serialize message request body: \(error.localizedDescription)", category: .chat)
                completion?(.failure(error))
                return
            }
            
            let task = URLSession.shared.dataTask(with: request) { data, response, reqError in
                if let reqError = reqError {
                    AppLogger.error("Network error sending message to \(endpointUrl): \(reqError.localizedDescription)", category: .chat)
                    completion?(.failure(reqError))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    let err = NSError(domain: "MessageRepository", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
                    completion?(.failure(err))
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    if let data = data, let apiResponse = try? JSONDecoder().decode(SendMessageResponse.self, from: data) {
                        AppLogger.info("Successfully sent message via API: \(apiResponse.messageId)", category: .chat)
                    } else {
                        AppLogger.info("Successfully sent message via API: \(message.messageID)", category: .chat)
                    }
                    completion?(.success(()))
                } else {
                    let errorBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                    AppLogger.error("Server API returned error: status=\(httpResponse.statusCode), body=\(errorBody)", category: .chat)
                    let err = NSError(
                        domain: "MessageRepository",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Send message failed: \(errorBody)"]
                    )
                    completion?(.failure(err))
                }
            }
            task.resume()
        }
    }
}

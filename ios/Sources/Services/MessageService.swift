import Foundation
import SwiftUI
import FirebaseFirestore
import CryptoKit
import SwiftProtobuf
import ULID

// MARK: - MessageService
/// チャット内メッセージ送受信（E2EE暗号化/復号）、暗号化添付ファイル、既読水位線管理、リアクションを担当するサービス
@MainActor
final class MessageService: ObservableObject {
    static let shared = MessageService()
    
    @Published var messages: [String: [DecryptedMessage]] = [:] // chatId -> [DecryptedMessage]
    @Published var hasMoreMessages: [String: Bool] = [:] // chatId -> Bool
    @Published var isLoadingMoreMessages: [String: Bool] = [:] // chatId -> Bool
    @Published var readReceipts: [String: [String: FriendsReadReceipt]] = [:] // chatId -> [userId: FriendsReadReceipt]
    @Published var userReactions: [String: FriendsReactionType] = [:] // "\(chatId)_\(messageId)" -> reactionType
    @Published var activeChatId: String? = nil
    
    private var messageListeners: [String: ListenerRegistration] = [:]
    private var messageLimits: [String: Int] = [:] // chatId -> Int
    private var readReceiptListeners: [String: ListenerRegistration] = [:]
    private var markAsReadDebounceWorkItems: [String: DispatchWorkItem] = [:]
    private var knownMessageIds: [String: Set<String>] = [:]
    
    private var currentTenant: FriendsTenant? {
        AuthService.shared.currentTenant
    }
    
    private var currentUser: FriendsPublicUserProfile? {
        AuthService.shared.currentUser
    }
    
    private init() {}
    
    // MARK: - Lifecycle & Clear
    
    func clear() {
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
        readReceiptListeners.values.forEach { $0.remove() }
        readReceiptListeners.removeAll()
        markAsReadDebounceWorkItems.values.forEach { $0.cancel() }
        markAsReadDebounceWorkItems.removeAll()
        
        knownMessageIds.removeAll()
        messageLimits.removeAll()
        messages.removeAll()
        hasMoreMessages.removeAll()
        isLoadingMoreMessages.removeAll()
        readReceipts.removeAll()
        userReactions.removeAll()
        activeChatId = nil
    }
    
    func stopWatchingMessages(chatId: String) {
        messageListeners[chatId]?.remove()
        messageListeners.removeValue(forKey: chatId)
        readReceiptListeners[chatId]?.remove()
        readReceiptListeners.removeValue(forKey: chatId)
        messages.removeValue(forKey: chatId)
    }
    
    // MARK: - Message Watcher & Listener
    
    func watchMessages(chatId: String, members: [String] = [], limit: Int? = nil) {
        guard let tenant = currentTenant else { return }
        let tenantId = tenant.tenantID
        
        let targetLimit = limit ?? messageLimits[chatId] ?? 30
        messageLimits[chatId] = targetLimit
        
        // 1:1 DM チャットの場合、親ドキュメントが未作成なら初期化を試みる
        if chatId.hasPrefix("dm_"), let currentUserId = currentUser?.userID {
            ChatRepository.shared.ensureDirectChat(tenantId: tenantId, chatId: chatId, currentUserId: currentUserId)
        }
        
        if limit != nil || messageListeners[chatId] == nil {
            messageListeners[chatId]?.remove()
            
            let listener = MessageRepository.shared.watchMessagesByChatId(tenantId: tenantId, chatId: chatId, limit: targetLimit) { [weak self] rawMessages in
                guard let self = self else { return }
                
                let previouslyKnownIds = self.knownMessageIds[chatId]
                let isInitialLoad = (previouslyKnownIds == nil)
                let currentMessageIds = Set(rawMessages.map { $0.messageID })
                self.knownMessageIds[chatId] = currentMessageIds
                
                if rawMessages.isEmpty {
                    DispatchQueue.main.async {
                        if self.messages[chatId]?.isEmpty ?? true {
                            self.messages[chatId] = []
                        }
                        self.hasMoreMessages[chatId] = false
                        self.isLoadingMoreMessages[chatId] = false
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.hasMoreMessages[chatId] = (rawMessages.count >= targetLimit)
                    self.isLoadingMoreMessages[chatId] = false
                }
                
                let getKeyHandler: (@escaping (SymmetricKey?) -> Void) -> Void = { handler in
                    if chatId.hasPrefix("gm_") {
                        let targetKeyVersion = rawMessages.last?.keyVersion ?? "v_1"
                        GroupChatService.shared.getGroupSessionKey(chatId: chatId, tenantId: tenantId, keyVersion: targetKeyVersion, completion: handler)
                    } else {
                        DirectChatService.shared.getDirectSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
                    }
                }
                
                getKeyHandler { sessionKey in
                    var newDecryptedMessages: [DecryptedMessage] = []
                    var newlyReceivedMessagesToNotify: [DecryptedMessage] = []
                    
                    for msg in rawMessages {
                        let ciphertext = msg.encryptedPayload.ciphertext
                        let nonce = msg.encryptedPayload.nonce
                        let effectiveKey = sessionKey
                        
                        var decryptedText = ""
                        if let key = effectiveKey, !ciphertext.isEmpty, !nonce.isEmpty {
                            if let dec = try? CryptoKeyManager.shared.decryptDirectMessage(ciphertext: ciphertext, nonce: nonce, sessionKey: key) {
                                decryptedText = dec
                            } else if let decWithTenant = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: ciphertext, nonce: nonce, tenantId: tenantId) {
                                decryptedText = decWithTenant
                            }
                        } else if !ciphertext.isEmpty, !nonce.isEmpty {
                            if let decWithTenant = try? CryptoKeyManager.shared.decryptWithTenantKey(encryptedData: ciphertext, nonce: nonce, tenantId: tenantId) {
                                decryptedText = decWithTenant
                            }
                        }
                        
                        var senderDisplayName = L10n.Common.sender
                        let isFromMe = (msg.senderID == self.currentUser?.uid || msg.senderID == self.currentUser?.userID)
                        if isFromMe {
                            senderDisplayName = self.currentUser?.displayName ?? L10n.Common.myself
                        } else if let friend = DirectChatService.shared.friendProfile(for: msg.senderID) {
                            senderDisplayName = friend.displayName
                        } else if let member = GroupChatService.shared.memberProfile(for: msg.senderID) {
                            senderDisplayName = member.displayName
                        }
                        
                        let myReaction = self.userReactions["\(chatId)_\(msg.messageID)"]
                        let decryptedMsg = DecryptedMessage(
                            message: msg,
                            senderName: senderDisplayName,
                            decryptedText: decryptedText,
                            myReaction: myReaction
                        )
                        newDecryptedMessages.append(decryptedMsg)
                        
                        if !isInitialLoad, let prevIds = previouslyKnownIds, !prevIds.contains(msg.messageID), !isFromMe {
                            newlyReceivedMessagesToNotify.append(decryptedMsg)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        let pendingMessages = (self.messages[chatId] ?? []).filter { $0.sendStatus != .sent && !currentMessageIds.contains($0.id) }
                        self.messages[chatId] = newDecryptedMessages + pendingMessages
                        
                        if self.activeChatId != chatId {
                            let groupChatModel = GroupChatService.shared.groupChats.first(where: { $0.chatID == chatId })
                            let isGroup = chatId.hasPrefix("gm_")
                            let toastTitle = isGroup ? (groupChatModel?.displayTitle ?? L10n.Group.defaultTitle) : nil
                            
                            for newMsg in newlyReceivedMessagesToNotify {
                                let senderFriend = DirectChatService.shared.friendProfile(for: newMsg.senderID)
                                let senderUserId = senderFriend?.userID ?? newMsg.senderID
                                let avatarNonce = senderFriend?.avatarNonce ?? ""
                                let avatarUpdatedAt = senderFriend?.avatarUpdatedDate
                                let displaySenderName = isGroup ? "\(newMsg.senderName) (\(toastTitle ?? ""))" : newMsg.senderName
                                
                                ToastNotificationManager.shared.show(
                                    chatId: chatId,
                                    senderId: senderUserId,
                                    senderName: displaySenderName,
                                    messageText: newMsg.summaryText,
                                    messageId: newMsg.id,
                                    isGroup: isGroup,
                                    avatarNonce: avatarNonce,
                                    avatarUpdatedAt: avatarUpdatedAt
                                )
                            }
                        }
                    }
                }
            }
            
            messageListeners[chatId] = listener
        }
    }
    
    func loadMoreMessages(chatId: String) {
        guard hasMoreMessages[chatId] == true else { return }
        guard isLoadingMoreMessages[chatId] != true else { return }
        
        let currentLimit = messageLimits[chatId] ?? 30
        let newLimit = currentLimit + 30
        
        DispatchQueue.main.async {
            self.isLoadingMoreMessages[chatId] = true
        }
        watchMessages(chatId: chatId, limit: newLimit)
    }
    
    // MARK: - Send Message to Workers API (E2EE)
    
    func createMessage(chatId: String, text: String, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Text is empty"])))
            return
        }
        guard let tenant = currentTenant else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current tenant is nil"])))
            return
        }
        guard let user = currentUser else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current user is nil"])))
            return
        }
        
        let tenantId = tenant.tenantID
        let messageId = "m_\(ULID().ulidString)"
        
        // 1. 楽観的UI更新: 即座に messages[chatId] に追加（sendStatus = .sending）
        let initialPbMsg = FriendsMessage(
            messageID: messageId,
            tenantID: tenantId,
            chatID: chatId,
            senderID: user.userID,
            keyVersion: "v_1",
            ciphertext: "",
            nonce: "",
            messageType: .text,
            createdAt: Date()
        )
        let initialDecryptedMsg = DecryptedMessage(
            message: initialPbMsg,
            senderName: user.displayName,
            plainText: trimmed,
            decryptedText: trimmed,
            myReaction: nil,
            sendStatus: .sending
        )
        
        DispatchQueue.main.async {
            var list = self.messages[chatId] ?? []
            list.append(initialDecryptedMsg)
            self.messages[chatId] = list
        }
        
        // 2. 未送信（失敗）メッセージの自動連動送信
        resendFailedMessages(chatId: chatId)
        
        // 3. メッセージ暗号化 & Workers API 送信
        sendPreparedTextMessage(
            chatId: chatId,
            messageId: messageId,
            tenantId: tenantId,
            user: user,
            text: trimmed,
            completion: completion
        )
    }
    
    private func sendPreparedTextMessage(
        chatId: String,
        messageId: String,
        tenantId: String,
        user: FriendsPublicUserProfile,
        text: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        var members: [String] = []
        if chatId.hasPrefix("dm_") {
            let rawStr = String(chatId.dropFirst(3))
            let parts = rawStr.components(separatedBy: "_u_")
            if parts.count == 2 {
                let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                let userB = "u_" + parts[1]
                members = [userA, userB].sorted()
            }
        } else if let existingChat = GroupChatService.shared.groupChats.first(where: { $0.chatID == chatId }) {
            members = existingChat.chat.members
        }
        
        let getKeyHandler: (@escaping (SymmetricKey?) -> Void) -> Void = { handler in
            if chatId.hasPrefix("gm_") {
                GroupChatService.shared.getGroupSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
            } else {
                DirectChatService.shared.getDirectSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
            }
        }
        
        getKeyHandler { [weak self] sessionKey in
            guard let self = self else { return }
            var ciphertext = ""
            var nonce = ""
            
            if let key = sessionKey {
                if let enc = try? CryptoKeyManager.shared.encryptDirectMessage(plainText: text, sessionKey: key) {
                    ciphertext = enc.ciphertext
                    nonce = enc.nonce
                }
            }
            
            if ciphertext.isEmpty {
                if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: text, tenantId: tenantId) {
                    ciphertext = enc.encryptedData
                    nonce = enc.nonce
                }
            }
            
            let pbMsg = FriendsMessage(
                messageID: messageId,
                tenantID: tenantId,
                chatID: chatId,
                senderID: user.userID,
                keyVersion: "v_1",
                ciphertext: ciphertext,
                nonce: nonce,
                messageType: .text,
                createdAt: Date()
            )
            
            MessageRepository.shared.createMessage(tenantId: tenantId, chatId: chatId, message: pbMsg, members: members) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let err):
                        AppLogger.error("Failed to send message \(messageId) in chat \(chatId): \(err.localizedDescription)", category: .chat)
                        if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                            list[idx].sendStatus = .failed
                            self.messages[chatId] = list
                        }
                        completion?(.failure(err))
                    case .success:
                        if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                            list[idx].sendStatus = .sent
                            self.messages[chatId] = list
                        }
                        completion?(.success(()))
                    }
                }
            }
        }
    }
    
    /// 指定した失敗メッセージの再送処理
    func resendMessage(chatId: String, messageId: String) {
        guard let list = messages[chatId], let target = list.first(where: { $0.id == messageId }) else { return }
        guard let tenant = currentTenant, let user = currentUser else { return }
        
        // ステータスを即座に .sending に更新（UIが回転アニメーションに変化）
        DispatchQueue.main.async {
            if var currentList = self.messages[chatId], let idx = currentList.firstIndex(where: { $0.id == messageId }) {
                currentList[idx].sendStatus = .sending
                self.messages[chatId] = currentList
            }
        }
        
        if target.hasAttachments {
            // 添付ファイル付きメッセージの再送
            resendAttachmentMessage(chatId: chatId, target: target, tenantId: tenant.tenantID, user: user)
        } else {
            // テキストメッセージの再送
            sendPreparedTextMessage(
                chatId: chatId,
                messageId: messageId,
                tenantId: tenant.tenantID,
                user: user,
                text: target.plainText
            )
        }
    }
    
    /// 同チャット内の未送信（失敗）メッセージを一括再送
    func resendFailedMessages(chatId: String) {
        guard let list = messages[chatId] else { return }
        let failedList = list.filter { $0.sendStatus == .failed }
        for failed in failedList {
            resendMessage(chatId: chatId, messageId: failed.id)
        }
    }
    
    // MARK: - Send Image Attachments
    
    func sendImageMessage(
        chatId: String,
        images: [UIImage],
        text: String = "",
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard !images.isEmpty else {
            completion?(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Images array is empty"])))
            return
        }
        guard let tenant = currentTenant else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current tenant is nil"])))
            return
        }
        guard let user = currentUser else {
            completion?(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: "Current user is nil"])))
            return
        }
        
        let tenantId = tenant.tenantID
        let messageId = "m_\(ULID().ulidString)"
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. 楽観的UI更新: 即座に messages[chatId] に追加（sendStatus = .sending）
        let initialPbMsg = FriendsMessage(
            messageID: messageId,
            tenantID: tenantId,
            chatID: chatId,
            senderID: user.userID,
            keyVersion: "v_1",
            ciphertext: "",
            nonce: "",
            messageType: .image,
            createdAt: Date()
        )
        let initialDecryptedMsg = DecryptedMessage(
            message: initialPbMsg,
            senderName: user.displayName,
            plainText: trimmedText,
            decryptedText: trimmedText,
            myReaction: nil,
            sendStatus: .sending
        )
        DispatchQueue.main.async {
            var list = self.messages[chatId] ?? []
            list.append(initialDecryptedMsg)
            self.messages[chatId] = list
        }
        
        // 2. 未送信（失敗）メッセージの自動連動送信
        resendFailedMessages(chatId: chatId)
        
        var members: [String] = []
        if chatId.hasPrefix("dm_") {
            let rawStr = String(chatId.dropFirst(3))
            let parts = rawStr.components(separatedBy: "_u_")
            if parts.count == 2 {
                let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                let userB = "u_" + parts[1]
                members = [userA, userB].sorted()
            }
        } else if let existingChat = GroupChatService.shared.groupChats.first(where: { $0.chatID == chatId }) {
            members = existingChat.chat.members
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let uploadGroup = DispatchGroup()
            var attachments: [MessageAttachment] = []
            var uploadError: Error?
            let lock = NSLock()
            
            for img in images {
                uploadGroup.enter()
                
                let resized = self.resizeImageForUpload(image: img, maxDimension: 1920)
                guard let jpegData = resized.jpegData(compressionQuality: 0.8) else {
                    lock.lock()
                    uploadError = NSError(domain: "ChatError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image data"])
                    lock.unlock()
                    uploadGroup.leave()
                    continue
                }
                
                let attId = "att_\(ULID().ulidString)"
                let storagePath = "tenants/\(tenantId)/chats/\(chatId)/attachments/\(attId).enc"
                let fileKey = CryptoKeyManager.shared.generateFileKey()
                let fileKeyBase64 = fileKey.withUnsafeBytes { Data($0) }.base64EncodedString()
                
                do {
                    let encResult = try CryptoKeyManager.shared.encryptFile(fileData: jpegData, key: fileKey)
                    AttachmentRepository.shared.uploadAttachment(encryptedData: encResult.encryptedData, storagePath: storagePath) { r2Result in
                        defer { uploadGroup.leave() }
                        switch r2Result {
                        case .failure(let err):
                            lock.lock()
                            if uploadError == nil { uploadError = err }
                            lock.unlock()
                        case .success:
                            let attachment = MessageAttachment(
                                attachmentId: attId,
                                storagePath: storagePath,
                                fileKey: fileKeyBase64,
                                nonce: encResult.nonceBase64,
                                mimeType: "image/jpeg",
                                width: Int(resized.size.width),
                                height: Int(resized.size.height),
                                size: jpegData.count
                            )
                            lock.lock()
                            attachments.append(attachment)
                            lock.unlock()
                        }
                    }
                } catch {
                    lock.lock()
                    if uploadError == nil { uploadError = error }
                    lock.unlock()
                    uploadGroup.leave()
                }
            }
            
            uploadGroup.wait()
            
            if let error = uploadError, attachments.isEmpty {
                DispatchQueue.main.async {
                    if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                        list[idx].sendStatus = .failed
                        self.messages[chatId] = list
                    }
                    completion?(.failure(error))
                }
                return
            }
            
            // 添付ファイル情報を反映
            DispatchQueue.main.async {
                if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                    list[idx] = DecryptedMessage(
                        message: list[idx].message,
                        senderName: user.displayName,
                        plainText: trimmedText,
                        decryptedText: trimmedText,
                        myReaction: nil,
                        attachments: attachments,
                        sendStatus: .sending
                    )
                    self.messages[chatId] = list
                }
            }
            
            self.sendPreparedAttachmentMessage(
                chatId: chatId,
                messageId: messageId,
                tenantId: tenantId,
                user: user,
                text: trimmedText,
                attachments: attachments,
                members: members,
                completion: completion
            )
        }
    }
    
    private func sendPreparedAttachmentMessage(
        chatId: String,
        messageId: String,
        tenantId: String,
        user: FriendsPublicUserProfile,
        text: String,
        attachments: [MessageAttachment],
        members: [String],
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let payloadObj = MessageContentPayload(text: text, attachments: attachments)
        guard let payloadData = try? JSONEncoder().encode(payloadObj),
              let payloadJsonString = String(data: payloadData, encoding: .utf8) else {
            DispatchQueue.main.async {
                if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                    list[idx].sendStatus = .failed
                    self.messages[chatId] = list
                }
                completion?(.failure(NSError(domain: "ChatError", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to encode message payload JSON"])))
            }
            return
        }
        
        let getKeyHandler: (@escaping (SymmetricKey?) -> Void) -> Void = { handler in
            DispatchQueue.main.async {
                if chatId.hasPrefix("gm_") {
                    GroupChatService.shared.getGroupSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
                } else {
                    DirectChatService.shared.getDirectSessionKey(chatId: chatId, tenantId: tenantId, completion: handler)
                }
            }
        }
        
        getKeyHandler { [weak self] sessionKey in
            guard let self = self else { return }
            var ciphertext = ""
            var nonce = ""
            
            if let key = sessionKey {
                if let enc = try? CryptoKeyManager.shared.encryptDirectMessage(plainText: payloadJsonString, sessionKey: key) {
                    ciphertext = enc.ciphertext
                    nonce = enc.nonce
                }
            }
            
            if ciphertext.isEmpty {
                if let enc = try? CryptoKeyManager.shared.encryptWithTenantKey(plainText: payloadJsonString, tenantId: tenantId) {
                    ciphertext = enc.encryptedData
                    nonce = enc.nonce
                }
            }
            
            let pbMsg = FriendsMessage(
                messageID: messageId,
                tenantID: tenantId,
                chatID: chatId,
                senderID: user.userID,
                keyVersion: "v_1",
                ciphertext: ciphertext,
                nonce: nonce,
                messageType: .image,
                createdAt: Date()
            )
            
            MessageRepository.shared.createMessage(tenantId: tenantId, chatId: chatId, message: pbMsg, members: members) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let err):
                        AppLogger.error("Failed to send image message \(messageId): \(err.localizedDescription)", category: .chat)
                        if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                            list[idx].sendStatus = .failed
                            self.messages[chatId] = list
                        }
                        completion?(.failure(err))
                    case .success:
                        if var list = self.messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) {
                            list[idx].sendStatus = .sent
                            self.messages[chatId] = list
                        }
                        completion?(.success(()))
                    }
                }
            }
        }
    }
    
    private func resendAttachmentMessage(
        chatId: String,
        target: DecryptedMessage,
        tenantId: String,
        user: FriendsPublicUserProfile
    ) {
        var members: [String] = []
        if chatId.hasPrefix("dm_") {
            let rawStr = String(chatId.dropFirst(3))
            let parts = rawStr.components(separatedBy: "_u_")
            if parts.count == 2 {
                let userA = parts[0].hasPrefix("u_") ? parts[0] : "u_" + parts[0]
                let userB = "u_" + parts[1]
                members = [userA, userB].sorted()
            }
        } else if let existingChat = GroupChatService.shared.groupChats.first(where: { $0.chatID == chatId }) {
            members = existingChat.chat.members
        }
        
        sendPreparedAttachmentMessage(
            chatId: chatId,
            messageId: target.id,
            tenantId: tenantId,
            user: user,
            text: target.plainText,
            attachments: target.attachments,
            members: members
        )
    }
    
    nonisolated private func resizeImageForUpload(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        
        let ratio = maxDimension / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }
    
    // MARK: - Read Receipt Management
    
    func watchReadReceipts(chatId: String) {
        guard readReceiptListeners[chatId] == nil, let tenant = currentTenant else { return }
        let tenantId = tenant.tenantID
        
        let listener = ReadReceiptRepository.shared.watchReadReceiptsByChatId(tenantId: tenantId, chatId: chatId) { [weak self] receiptsMap in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.readReceipts[chatId] = receiptsMap
            }
        }
        readReceiptListeners[chatId] = listener
    }
    
    func markAsRead(chatId: String, lastMessageId: String? = nil, lastMessageDate: Date? = nil) {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        
        let (messageId, readDate): (String, Date) = {
            if let mid = lastMessageId, let mdate = lastMessageDate {
                return (mid, mdate)
            }
            if let list = messages[chatId], let lastMsg = list.last {
                return (lastMsg.id, lastMsg.createdDate)
            }
            return ("initial", Date())
        }()
        
        var currentMap = readReceipts[chatId] ?? [:]
        let localReceipt = FriendsReadReceipt(
            userID: userId,
            chatID: chatId,
            tenantID: tenantId,
            lastReadMessageID: messageId,
            lastReadAt: readDate,
            updatedAt: Date()
        )
        currentMap[userId] = localReceipt
        readReceipts[chatId] = currentMap
        
        markAsReadDebounceWorkItems[chatId]?.cancel()
        
        let workItem = DispatchWorkItem {
            ReadReceiptRepository.shared.patchReadReceiptByUserId(
                tenantId: tenantId,
                chatId: chatId,
                userId: userId,
                lastReadMessageId: messageId,
                lastReadAt: readDate
            )
        }
        
        markAsReadDebounceWorkItems[chatId] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    func isMessageRead(chatId: String, messageDate: Date, senderId: String) -> Bool {
        guard let receipts = readReceipts[chatId] else { return false }
        
        for (userId, receipt) in receipts {
            let isSender = (userId == senderId) || (userId == currentUser?.userID)
            if !isSender {
                let thresholdDate = messageDate.addingTimeInterval(-1.0)
                let isRead = receipt.lastReadDate >= thresholdDate
                if isRead {
                    return true
                }
            }
        }
        return false
    }
    
    func readCountForMessage(chatId: String, messageDate: Date, senderId: String) -> Int {
        guard let receipts = readReceipts[chatId] else { return 0 }
        
        var count = 0
        var countedUserIds = Set<String>()
        for (userId, receipt) in receipts {
            let isSender = (userId == senderId) || (userId == currentUser?.userID)
            if !isSender && !countedUserIds.contains(userId) {
                if receipt.lastReadDate >= messageDate.addingTimeInterval(-1.0) {
                    count += 1
                    countedUserIds.insert(userId)
                }
            }
        }
        return count
    }
    
    func unreadCount(for chatId: String) -> Int {
        if activeChatId == chatId {
            return 0
        }
        guard let myUserId = currentUser?.userID else { return 0 }
        guard let chatMessages = messages[chatId], !chatMessages.isEmpty else { return 0 }
        
        let receipts = readReceipts[chatId] ?? [:]
        let myReceipt = receipts[myUserId]
        let myLastReadDate = myReceipt?.lastReadDate ?? Date.distantPast
        let myLastReadMessageId = myReceipt?.lastReadMessageID ?? ""
        
        if let lastMsg = chatMessages.last, !myLastReadMessageId.isEmpty, lastMsg.id == myLastReadMessageId {
            return 0
        }
        
        if !myLastReadMessageId.isEmpty, let idx = chatMessages.firstIndex(where: { $0.id == myLastReadMessageId }) {
            var unread = 0
            for i in (idx + 1)..<chatMessages.count {
                let msg = chatMessages[i]
                let isMine = msg.message.senderID == myUserId
                if !isMine {
                    unread += 1
                }
            }
            return unread
        }
        
        var unread = 0
        for msg in chatMessages {
            let isMine = msg.message.senderID == myUserId
            if !isMine && msg.createdDate > myLastReadDate.addingTimeInterval(0.1) {
                unread += 1
            }
        }
        return unread
    }
    
    // MARK: - Message Reactions Management
    
    func toggleReaction(chatId: String, messageId: String, reactionType: FriendsReactionType) {
        guard let tenant = currentTenant, let user = currentUser else { return }
        let tenantId = tenant.tenantID
        let userId = user.userID
        let reactionKey = "\(chatId)_\(messageId)"
        let previousReaction = userReactions[reactionKey]
        
        if previousReaction == reactionType {
            DispatchQueue.main.async {
                self.userReactions.removeValue(forKey: reactionKey)
                self.updateLocalMessageReaction(chatId: chatId, messageId: messageId, oldReaction: previousReaction, newReaction: nil)
            }
            ReactionRepository.shared.deleteReactionByUserId(tenantId: tenantId, chatId: chatId, messageId: messageId, userId: userId, reactionType: reactionType)
        } else {
            DispatchQueue.main.async {
                self.userReactions[reactionKey] = reactionType
                self.updateLocalMessageReaction(chatId: chatId, messageId: messageId, oldReaction: previousReaction, newReaction: reactionType)
            }
            ReactionRepository.shared.setReactionByUserId(
                tenantId: tenantId,
                chatId: chatId,
                messageId: messageId,
                userId: userId,
                userName: user.displayName,
                reactionType: reactionType,
                previousReaction: previousReaction
            )
        }
    }
    
    private func updateLocalMessageReaction(
        chatId: String,
        messageId: String,
        oldReaction: FriendsReactionType?,
        newReaction: FriendsReactionType?
    ) {
        guard var list = messages[chatId], let idx = list.firstIndex(where: { $0.id == messageId }) else { return }
        var counts = list[idx].reactionCounts
        
        if let prev = oldReaction {
            let cur = counts[prev.key] ?? 0
            if cur <= 1 {
                counts.removeValue(forKey: prev.key)
            } else {
                counts[prev.key] = cur - 1
            }
        }
        if let next = newReaction {
            let cur = counts[next.key] ?? 0
            counts[next.key] = cur + 1
        }
        
        var pbMsg = list[idx].message
        pbMsg.reactionCounts = counts
        
        list[idx] = DecryptedMessage(
            message: pbMsg,
            senderName: list[idx].senderName,
            decryptedText: list[idx].decryptedText,
            myReaction: newReaction
        )
        self.messages[chatId] = list
    }
    
    func fetchReactionDetails(
        chatId: String,
        messageId: String,
        completion: @escaping (Result<[FriendsMessageReaction], Error>) -> Void
    ) {
        guard let tenant = currentTenant else {
            completion(.failure(NSError(domain: "ChatError", code: 401, userInfo: [NSLocalizedDescriptionKey: L10n.Error.unknown])))
            return
        }
        ReactionRepository.shared.listReactionDetailsByMessageId(tenantId: tenant.tenantID, chatId: chatId, messageId: messageId, completion: completion)
    }
    
    /// リアクション詳細モーダル表示中のみのオンデマンド購読 (RP-01)
    func watchReactionDetails(
        chatId: String,
        messageId: String,
        onChange: @escaping ([FriendsMessageReaction]) -> Void
    ) -> ListenerRegistration? {
        guard let tenant = currentTenant else { return nil }
        return ReactionRepository.shared.watchReactionsByMessageId(
            tenantId: tenant.tenantID,
            chatId: chatId,
            messageId: messageId,
            onChange: onChange
        )
    }
}


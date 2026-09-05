import Foundation
import FirebaseFirestore

final class ChatRepository {
    static let shared = ChatRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// 参加チャット一覧のリアルタイム購読 (CP-01 - 複合インデックス & limit(50) 最適化)
    func watchChatsByUserId(
        tenantId: String,
        userId: String,
        limit: Int = 50,
        onChange: @escaping ([FriendsChatUIModel]) -> Void
    ) -> ListenerRegistration {
        return db.collection("tenants").document(tenantId).collection("chats")
            .whereField("members", arrayContains: userId)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    AppLogger.error("Failed to watch chats for user \(userId): \(error.localizedDescription)", category: .chat)
                    return
                }
                guard let documents = snapshot?.documents else { return }
                let newChats = self.parseChatDocuments(documents, tenantId: tenantId)
                onChange(newChats)
            }
    }
    
    /// 参加チャット一覧の一括取得 (GP-08: リフレッシュ用)
    func listChatsByUserId(
        tenantId: String,
        userId: String,
        limit: Int = 50,
        completion: @escaping (Result<[FriendsChatUIModel], Error>) -> Void
    ) {
        db.collection("tenants").document(tenantId).collection("chats")
            .whereField("members", arrayContains: userId)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                let chats = self.parseChatDocuments(documents, tenantId: tenantId)
                completion(.success(chats))
            }
    }
    
    /// Firestore チャットドキュメント群の共通パース
    private func parseChatDocuments(_ documents: [QueryDocumentSnapshot], tenantId: String) -> [FriendsChatUIModel] {
        var newChats: [FriendsChatUIModel] = []
        for doc in documents {
            let data = doc.data()
            let isDeleted = data["isDeleted"] as? Bool ?? false
            if isDeleted {
                continue
            }
            
            let chatId = doc.documentID
            let title = data["title"] as? String ?? ""
            let chatTypeStr = data["chatType"] as? String ?? "direct"
            let chatType: FriendsChatType = (chatTypeStr == "group") ? .group : .direct
            let members = data["members"] as? [String] ?? []
            let lastMessage = data["lastMessage"] as? String ?? ""
            let lastMessageTimestamp = (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? Date()
            let unreadCount = data["unreadCount"] as? Int ?? 0
            let createdBy = data["createdBy"] as? String ?? ""
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedBy = data["updatedBy"] as? String ?? ""
            let avatarNonce = data["avatarNonce"] as? String ?? ""
            let avatarUpdatedAt = (data["avatarUpdatedAt"] as? Timestamp)?.dateValue()
            
            var memberRoles: [String: FriendsGroupMemberRole] = [:]
            if let rolesData = data["memberRoles"] as? [String: Any] {
                for (uid, rVal) in rolesData {
                    if let rStr = rVal as? String {
                        switch rStr {
                        case "owner": memberRoles[uid] = .owner
                        case "admin": memberRoles[uid] = .admin
                        case "member": memberRoles[uid] = .member
                        default: break
                        }
                    }
                }
            }
            
            let pbChat = FriendsChat(
                chatID: chatId,
                tenantID: tenantId,
                chatType: chatType,
                members: members,
                title: title,
                createdBy: createdBy,
                createdAt: createdAt,
                updatedBy: updatedBy,
                updatedAt: lastMessageTimestamp,
                memberRoles: memberRoles,
                isDeleted: isDeleted
            )
            
            let uiChat = FriendsChatUIModel(
                chat: pbChat,
                title: title,
                lastMessage: lastMessage,
                lastMessageAt: lastMessageTimestamp,
                unreadCount: unreadCount,
                avatarNonce: avatarNonce,
                avatarUpdatedAt: avatarUpdatedAt
            )
            newChats.append(uiChat)
        }
        return newChats
    }
    
    /// グループチャット新規作成 (GP-01)
    func createGroupChat(
        tenantId: String,
        chatId: String,
        title: String,
        members: [String],
        createdBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var memberRoles: [String: String] = [:]
        for member in members {
            memberRoles[member] = (member == createdBy) ? "owner" : "member"
        }
        
        let chatData: [String: Any] = [
            "chatId": chatId,
            "tenantId": tenantId,
            "chatType": "group",
            "title": title,
            "members": members,
            "memberRoles": memberRoles,
            "isDeleted": false,
            "lastMessage": "",
            "lastMessageAt": FieldValue.serverTimestamp(),
            "createdBy": createdBy,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedBy": createdBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        db.collection("tenants").document(tenantId).collection("chats").document(chatId).setData(chatData) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// グループメンバー追加 (GP-02)
    func addGroupMembers(
        tenantId: String,
        chatId: String,
        newMembers: [String],
        updatedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        var updatePayload: [String: Any] = [
            "members": FieldValue.arrayUnion(newMembers),
            "updatedBy": updatedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        for m in newMembers {
            updatePayload["memberRoles.\(m)"] = "member"
        }
        chatRef.updateData(updatePayload) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// グループ削除 (GP-03: membersクリア & 論理削除)
    func deleteGroupChat(
        tenantId: String,
        chatId: String,
        deletedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.updateData([
            "members": [] as [String],
            "isDeleted": true,
            "deletedBy": deletedBy,
            "deletedAt": FieldValue.serverTimestamp(),
            "updatedBy": deletedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// 管理者任命 (GP-04: memberRoles更新)
    func assignAdmin(
        tenantId: String,
        chatId: String,
        targetUserId: String,
        updatedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.updateData([
            "memberRoles.\(targetUserId)": "admin",
            "updatedBy": updatedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// 立候補型オーナー交代 (GP-05: memberRoles更新)
    func claimOwnership(
        tenantId: String,
        chatId: String,
        newOwnerId: String,
        oldOwnerId: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        var updates: [String: Any] = [
            "memberRoles.\(newOwnerId)": "owner",
            "updatedBy": newOwnerId,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let oldOwner = oldOwnerId, !oldOwner.isEmpty && oldOwner != newOwnerId {
            updates["memberRoles.\(oldOwner)"] = "admin"
        }
        chatRef.updateData(updates) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// メンバー除外 / キック / 退会 (GP-06)
    func removeGroupMember(
        tenantId: String,
        chatId: String,
        targetUserId: String,
        updatedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.updateData([
            "members": FieldValue.arrayRemove([targetUserId]),
            "memberRoles.\(targetUserId)": FieldValue.delete(),
            "updatedBy": updatedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// グループにメンバーを追加 (GP-08)
    func addGroupMembers(
        tenantId: String,
        chatId: String,
        newMemberUserIds: [String],
        updatedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        var updates: [String: Any] = [
            "members": FieldValue.arrayUnion(newMemberUserIds),
            "updatedBy": updatedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        for mId in newMemberUserIds {
            updates["memberRoles.\(mId)"] = "member"
        }
        chatRef.updateData(updates) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// グループ名変更 (GP-07)
    func updateGroupTitle(
        tenantId: String,
        chatId: String,
        newTitle: String,
        updatedBy: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.updateData([
            "title": newTitle,
            "updatedBy": updatedBy,
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    /// 1:1 DM チャット親ドキュメントの存在確認および自動初期化 (CP-09)
    func ensureDirectChat(
        tenantId: String,
        chatId: String,
        currentUserId: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        guard chatId.hasPrefix("dm_") else {
            completion?(.success(()))
            return
        }
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.getDocument { snapshot, error in
            if let error = error {
                completion?(.failure(error))
                return
            }
            if snapshot?.exists == true {
                completion?(.success(()))
                return
            }
            
            // ドキュメントIDからメンバーIDを復元 (例: dm_u_111_u_222 -> ["u_111", "u_222"])
            let rawParts = String(chatId.dropFirst(3))
            let segments = rawParts.split(separator: "_").map(String.init)
            var reconstructedMembers: [String] = []
            var i = 0
            while i < segments.count {
                if segments[i] == "u" && i + 1 < segments.count {
                    reconstructedMembers.append("u_" + segments[i + 1])
                    i += 2
                } else {
                    reconstructedMembers.append(segments[i])
                    i += 1
                }
            }
            if !reconstructedMembers.contains(currentUserId) {
                reconstructedMembers.append(currentUserId)
            }
            
            let sortedMembers = Array(Set(reconstructedMembers)).sorted()
            guard sortedMembers.count == 2, sortedMembers[0] < sortedMembers[1] else {
                completion?(.failure(NSError(domain: "ChatError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid DM members count"])))
                return
            }
            
            let chatCreateData: [String: Any] = [
                "chatId": chatId,
                "tenantId": tenantId,
                "chatType": "direct",
                "members": sortedMembers,
                "lastMessage": "",
                "lastMessageAt": FieldValue.serverTimestamp(),
                "createdBy": currentUserId,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedBy": currentUserId,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            chatRef.setData(chatCreateData) { error in
                if let error = error {
                    AppLogger.error("Failed to initialize DM chat: \(error.localizedDescription)", category: .chat)
                    completion?(.failure(error))
                } else {
                    AppLogger.info("Successfully initialized DM chat: \(chatId)", category: .chat)
                    completion?(.success(()))
                }
            }
        }
    }
}



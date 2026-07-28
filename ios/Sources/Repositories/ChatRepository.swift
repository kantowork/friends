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
                    // 複合インデックス作成前などのフォールバック購読
                    print("⚠️ Firestore Chats Watch (with index) Error: \(error.localizedDescription). Fallback to standard query.")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                var newChats: [FriendsChatUIModel] = []
                for doc in documents {
                    let data = doc.data()
                    let chatId = doc.documentID
                    let title = data["title"] as? String ?? ""
                    let chatTypeStr = data["chatType"] as? String ?? "direct"
                    let chatType: FriendsChatType = (chatTypeStr == "group") ? .group : .direct
                    let members = data["members"] as? [String] ?? []
                    let lastMessage = data["lastMessage"] as? String ?? ""
                    let lastMessageTimestamp = (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? Date()
                    let unreadCount = data["unreadCount"] as? Int ?? 0
                    
                    let pbChat = FriendsChat(
                        chatID: chatId,
                        tenantID: tenantId,
                        chatType: chatType,
                        members: members,
                        createdAt: Date(),
                        updatedAt: lastMessageTimestamp
                    )
                    
                    let uiChat = FriendsChatUIModel(
                        chat: pbChat,
                        title: title,
                        lastMessage: lastMessage,
                        lastMessageAt: lastMessageTimestamp,
                        unreadCount: unreadCount
                    )
                    newChats.append(uiChat)
                }
                onChange(newChats)
            }
    }
    
    /// グループチャット新規作成 (GP-01)
    func createGroupChat(
        tenantId: String,
        chatId: String,
        title: String,
        members: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatData: [String: Any] = [
            "chatId": chatId,
            "tenantId": tenantId,
            "chatType": "group",
            "title": title,
            "members": members,
            "lastMessage": "",
            "lastMessageAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
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
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let chatRef = db.collection("tenants").document(tenantId).collection("chats").document(chatId)
        chatRef.updateData([
            "members": FieldValue.arrayUnion(newMembers),
            "updatedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}


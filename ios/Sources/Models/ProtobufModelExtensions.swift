import Foundation
import SwiftProtobuf
import Base58Swift

// MARK: - Protobuf Model Extensions (一元化モデル拡張)
// shared/model/*.proto から自動生成された Apple swift-protobuf 構造体に
// Identifiable, 便利プロパティ・イニシャライザ・ローカル拡張機能を直接付与します。

// MARK: - User ID Generator (Base58 UUID: u_<最大22文字>)

public enum UserIDHelper {
    /// UUID (16 bytes) を Base58 エンコードし、`u_` プレフィックスを付与したユーザー識別子（最大22文字）を生成
    public static func generateUserId() -> String {
        let uuid = UUID()
        let uuidBytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        let base58String = Base58.base58Encode(uuidBytes)
        return "u_\(base58String)"
    }
}

// MARK: - FriendsTenant Extensions

extension FriendsTenant: Identifiable {
    var id: String { tenantID }
    
    var createdDate: Date {
        hasCreatedAt ? createdAt.date : Date()
    }
    
    init(
        tenantID: String,
        tenantCode: String? = nil,
        tenantName: String = "",
        isDefaultTenant: Bool = false,
        tenantMasterKey: String = "",
        encryptedTenantName: String = "",
        tenantNameNonce: String = "",
        createdAt: Date = Date()
    ) {
        self.init()
        self.tenantID = tenantID
        self.tenantCode = tenantCode ?? tenantID.replacingOccurrences(of: "t_", with: "")
        self.tenantName = tenantName
        self.isDefaultTenant = isDefaultTenant
        self.tenantMasterKey = tenantMasterKey
        self.encryptedTenantName = encryptedTenantName
        self.tenantNameNonce = tenantNameNonce
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
    }
}

// MARK: - FriendsPublicUserProfile Extensions

extension FriendsPublicUserProfile: Identifiable {
    var id: String { userID }
    
    var avatarUpdatedDate: Date? {
        hasAvatarUpdatedAt ? avatarUpdatedAt.date : nil
    }
    
    /// ユーザー識別用表示名（@username）。未設定の場合は userID の先頭10文字をフォールバック
    var effectiveUsername: String {
        username.isEmpty ? String(userID.prefix(10)) : username
    }
    
    init(
        userID: String,
        uid: String,
        tenantID: String,
        displayName: String,
        publicKey: String,
        role: FriendsUserRole = .member,
        accountType: FriendsAccountType = .anonymous,
        encryptedDisplayName: String = "",
        displayNameNonce: String = "",
        avatarNonce: String = "",
        avatarUpdatedAt: Date? = nil,
        username: String? = nil,
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date()
    ) {
        self.init()
        self.userID = userID
        self.uid = uid
        self.tenantID = tenantID
        self.displayName = displayName
        self.publicKey = publicKey
        self.role = role
        self.accountType = accountType
        self.encryptedDisplayName = encryptedDisplayName
        self.displayNameNonce = displayNameNonce
        self.avatarNonce = avatarNonce
        if let avatarUpdatedAt = avatarUpdatedAt {
            self.avatarUpdatedAt = Google_Protobuf_Timestamp(date: avatarUpdatedAt)
        }
        self.username = username ?? String(userID.prefix(10))
        self.createdBy = createdBy.isEmpty ? userID : createdBy
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        self.updatedBy = updatedBy.isEmpty ? userID : updatedBy
        self.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
    }
}

// MARK: - FriendsChat Extensions

extension FriendsChat: Identifiable {
    var id: String { chatID }
    
    var createdDate: Date {
        hasCreatedAt ? createdAt.date : Date()
    }
    
    var updatedDate: Date {
        hasUpdatedAt ? updatedAt.date : Date()
    }
    
    init(
        chatID: String,
        tenantID: String,
        chatType: FriendsChatType = .direct,
        members: [String] = [],
        title: String = "",
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date()
    ) {
        self.init()
        self.chatID = chatID
        self.tenantID = tenantID
        self.chatType = chatType
        self.members = members
        self.title = title
        self.createdBy = createdBy
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        self.updatedBy = updatedBy.isEmpty ? createdBy : updatedBy
        self.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
    }
}

// MARK: - FriendsChatDisplayWrapper (UI表示用チャットモデル)

struct FriendsChatUIModel: Identifiable, Equatable, Hashable {
    let chat: FriendsChat
    let title: String
    let lastMessage: String
    let lastMessageAt: Date
    let unreadCount: Int
    
    var id: String { chat.chatID }
    var chatID: String { chat.chatID }
    var tenantID: String { chat.tenantID }
    var chatType: FriendsChatType { chat.chatType }
    
    var displayTitle: String {
        if !title.isEmpty { return title }
        return chatType == .group ? "グループトーク" : "1:1トーク"
    }
    
    var lastMessageDate: Date { lastMessageAt }
    
    init(
        chat: FriendsChat,
        title: String = "",
        lastMessage: String = "",
        lastMessageAt: Date = Date(),
        unreadCount: Int = 0
    ) {
        self.chat = chat
        self.title = title
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
    }
}

// MARK: - FriendsMessage Extensions

extension FriendsMessage: Identifiable {
    var id: String { messageID }
    
    var createdDate: Date {
        hasCreatedAt ? createdAt.date : Date()
    }
    
    init(
        messageID: String,
        tenantID: String,
        chatID: String,
        senderID: String,
        keyVersion: String = "v_1",
        ciphertext: String,
        nonce: String,
        messageType: FriendsMessageType = .text,
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date(),
        reactionCounts: [String: Int32] = [:]
    ) {
        self.init()
        self.messageID = messageID
        self.tenantID = tenantID
        self.chatID = chatID
        self.senderID = senderID
        self.keyVersion = keyVersion
        
        var payload = FriendsEncryptedPayload()
        payload.ciphertext = ciphertext
        payload.nonce = nonce
        self.encryptedPayload = payload
        
        self.messageType = messageType
        self.createdBy = createdBy.isEmpty ? senderID : createdBy
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        self.updatedBy = updatedBy.isEmpty ? senderID : updatedBy
        self.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
        self.reactionCounts = reactionCounts
    }
}

// MARK: - FriendsReactionType Extensions

extension FriendsReactionType: Identifiable {
    public var id: Int { rawValue }
    
    public var emoji: String {
        switch self {
        case .thumbsUp: return "👍"
        case .heart: return "❤️"
        case .ok: return "🆗"
        case .smile: return "😊"
        case .surprised: return "😲"
        case .sad: return "😢"
        case .thinking: return "🤔"
        default: return "❓"
        }
    }
    
    public var key: String {
        switch self {
        case .thumbsUp: return "thumbs_up"
        case .heart: return "heart"
        case .ok: return "ok"
        case .smile: return "smile"
        case .surprised: return "surprised"
        case .sad: return "sad"
        case .thinking: return "thinking"
        default: return "unspecified"
        }
    }
    
    public var title: String {
        switch self {
        case .thumbsUp: return L10n.Reaction.thumbsUp
        case .heart: return L10n.Reaction.heart
        case .ok: return L10n.Reaction.ok
        case .smile: return L10n.Reaction.smile
        case .surprised: return L10n.Reaction.surprised
        case .sad: return L10n.Reaction.sad
        case .thinking: return L10n.Reaction.thinking
        default: return ""
        }
    }
    
    public static func fromKey(_ key: String) -> FriendsReactionType {
        switch key {
        case "thumbs_up": return .thumbsUp
        case "heart": return .heart
        case "ok": return .ok
        case "smile": return .smile
        case "surprised": return .surprised
        case "sad": return .sad
        case "thinking": return .thinking
        default: return .unspecified
        }
    }
    
    public static var allActiveTypes: [FriendsReactionType] {
        [.thumbsUp, .heart, .ok, .smile, .surprised, .sad, .thinking]
    }
}

// MARK: - FriendsMessageReaction Extensions

extension FriendsMessageReaction: Identifiable {
    public var id: String { reactionID.isEmpty ? "\(messageID)_\(userID)" : reactionID }
    
    public var createdDate: Date {
        hasCreatedAt ? createdAt.date : Date()
    }
    
    public init(
        reactionID: String,
        messageID: String,
        chatID: String,
        tenantID: String,
        userID: String,
        userName: String,
        reactionType: FriendsReactionType,
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date()
    ) {
        self.init()
        self.reactionID = reactionID
        self.messageID = messageID
        self.chatID = chatID
        self.tenantID = tenantID
        self.userID = userID
        self.userName = userName
        self.reactionType = reactionType
        self.createdBy = createdBy.isEmpty ? userID : createdBy
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        self.updatedBy = updatedBy.isEmpty ? userID : updatedBy
        self.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
    }
}

// MARK: - Local Message Decryption Wrapper

struct DecryptedMessage: Identifiable, Equatable {
    let message: FriendsMessage
    let senderName: String
    let plainText: String
    let isDecrypted: Bool
    let reactions: [FriendsMessageReaction]
    let myReaction: FriendsReactionType?
    
    var id: String { message.messageID }
    var chatID: String { message.chatID }
    var senderID: String { message.senderID }
    var createdDate: Date { message.createdDate }
    var isFromMe: Bool { false }
    var decryptedText: String { plainText }
    var reactionCounts: [String: Int32] { message.reactionCounts }
    
    init(
        message: FriendsMessage,
        senderName: String = "",
        plainText: String = "",
        decryptedText: String? = nil,
        isDecrypted: Bool = true,
        reactions: [FriendsMessageReaction] = [],
        myReaction: FriendsReactionType? = nil
    ) {
        self.message = message
        self.senderName = senderName
        self.plainText = decryptedText ?? plainText
        self.isDecrypted = isDecrypted
        self.reactions = reactions
        self.myReaction = myReaction
    }
}

// MARK: - FriendsFriendRelationship Extensions

extension FriendsFriendRelationship: Identifiable {
    var id: String { relationshipID.isEmpty ? "\(ownerUserID)_\(friendUserID)" : relationshipID }
    
    var addedDate: Date {
        hasCreatedAt ? createdAt.date : Date()
    }
    
    init(
        relationshipID: String,
        tenantID: String,
        ownerUserID: String,
        friendUserID: String,
        friendDisplayName: String,
        friendPublicKey: String = "",
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date()
    ) {
        self.init()
        self.relationshipID = relationshipID
        self.tenantID = tenantID
        self.ownerUserID = ownerUserID
        self.friendUserID = friendUserID
        self.friendDisplayName = friendDisplayName
        self.friendPublicKey = friendPublicKey
        self.createdBy = createdBy.isEmpty ? ownerUserID : createdBy
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        self.updatedBy = updatedBy.isEmpty ? ownerUserID : updatedBy
        self.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
    }
}

// MARK: - FriendsFriendInvitationPayload Extensions

extension FriendsFriendInvitationPayload {
    init(
        tenantID: String,
        userID: String,
        uid: String,
        displayName: String,
        publicKey: String,
        passcode: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970)
    ) {
        self.init()
        self.type = "friend_invite"
        self.version = 1
        self.tenantID = tenantID
        self.userID = userID
        self.uid = uid
        self.displayName = displayName
        self.publicKey = publicKey
        self.passcode = passcode
        self.timestamp = timestamp
    }
}

// MARK: - FriendsReadReceipt Extensions

extension FriendsReadReceipt: Identifiable {
    var id: String { "\(chatID)_\(userID)" }
    
    var lastReadDate: Date {
        hasLastReadAt ? lastReadAt.date : Date.distantPast
    }
    
    var updatedDate: Date {
        hasUpdatedAt ? updatedAt.date : Date()
    }
    
    init(
        userID: String,
        chatID: String,
        tenantID: String,
        lastReadMessageID: String = "",
        lastReadAt: Date = Date(),
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date()
    ) {
        self.userID = userID
        self.chatID = chatID
        self.tenantID = tenantID
        self.lastReadMessageID = lastReadMessageID
        self.lastReadAt = Google_Protobuf_Timestamp(date: lastReadAt)
        self.createdBy = createdBy.isEmpty ? userID : createdBy
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
        self.updatedBy = updatedBy.isEmpty ? userID : updatedBy
        self.updatedAt = Google_Protobuf_Timestamp(date: updatedAt)
    }
}

// MARK: - FriendsKeyBucket Extensions

extension FriendsKeyBucket: Identifiable {
    var id: String { "\(chatID)_\(keyVersion)" }
    
    var createdDate: Date {
        hasCreatedAt ? createdAt.date : Date()
    }
    
    init(
        keyVersion: String,
        chatID: String,
        tenantID: String,
        encryptedGroupKeys: [String: String] = [:],
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedBy: String = "",
        updatedAt: Date = Date()
    ) {
        self.init()
        self.keyVersion = keyVersion
        self.chatID = chatID
        self.tenantID = tenantID
        self.encryptedGroupKeys = encryptedGroupKeys
        self.createdAt = Google_Protobuf_Timestamp(date: createdAt)
    }
}


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
        updatedAt: Date = Date(),
        memberRoles: [String: FriendsGroupMemberRole] = [:],
        isDeleted: Bool = false
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
        self.memberRoles = memberRoles
        self.isDeleted = isDeleted
    }
    
    /// 特定ユーザーのロールを取得（未設定時は .member、作成者初期フォールバック付き）
    func role(for userId: String) -> FriendsGroupMemberRole {
        if let role = memberRoles[userId], role != .unspecified {
            return role
        }
        if !createdBy.isEmpty && userId == createdBy {
            return .owner
        }
        return .member
    }
    
    /// オーナーのユーザーIDを取得
    var ownerUserId: String? {
        if let pair = memberRoles.first(where: { $0.value == .owner }) {
            return pair.key
        }
        return createdBy.isEmpty ? nil : createdBy
    }
    
    /// 特定ユーザーがオーナーまたは管理者であるか判定
    func isOwnerOrAdmin(userId: String) -> Bool {
        let r = role(for: userId)
        return r == .owner || r == .admin
    }
}

// MARK: - FriendsChatDisplayWrapper (UI表示用チャットモデル)

struct FriendsChatUIModel: Identifiable, Equatable, Hashable {
    let chat: FriendsChat
    let title: String
    let lastMessage: String
    let lastMessageAt: Date
    let unreadCount: Int
    var avatarNonce: String = ""
    var avatarUpdatedAt: Date? = nil
    
    var id: String { chat.chatID }
    var chatID: String { chat.chatID }
    var tenantID: String { chat.tenantID }
    var chatType: FriendsChatType { chat.chatType }
    
    var displayTitle: String {
        if !title.isEmpty { return title }
        return chatType == .group ? "かいぎ" : "1:1トーク"
    }
    
    var lastMessageDate: Date { lastMessageAt }
    
    init(
        chat: FriendsChat,
        title: String = "",
        lastMessage: String = "",
        lastMessageAt: Date = Date(),
        unreadCount: Int = 0,
        avatarNonce: String = "",
        avatarUpdatedAt: Date? = nil
    ) {
        self.chat = chat
        self.title = title
        self.lastMessage = lastMessage
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.avatarNonce = avatarNonce
        self.avatarUpdatedAt = avatarUpdatedAt
    }
    
    func role(for userId: String) -> FriendsGroupMemberRole {
        chat.role(for: userId)
    }
    
    func isOwnerOrAdmin(userId: String) -> Bool {
        chat.isOwnerOrAdmin(userId: userId)
    }
    
    var ownerUserId: String? {
        chat.ownerUserId
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
        case .laugh: return "🤣"
        case .sad: return "😢"
        case .surprised: return "😱"
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
        case .laugh: return "laugh"
        case .sad: return "sad"
        case .surprised: return "surprised"
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
        case .laugh: return L10n.Reaction.laugh
        case .sad: return L10n.Reaction.sad
        case .surprised: return L10n.Reaction.surprised
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
        case "laugh": return .laugh
        case "sad": return .sad
        case "surprised": return .surprised
        case "thinking": return .thinking
        default: return .unspecified
        }
    }
    
    /// メッセージ長押し時に直下に表示するクイックアクションリアクション（7種）
    /// ※「…」（その他の絵文字一覧展開）は今後の実装フェーズで提供予定
    public static var quickActionTypes: [FriendsReactionType] {
        [.thumbsUp, .heart, .ok, .smile, .laugh, .sad, .surprised]
    }
    
    public static var allActiveTypes: [FriendsReactionType] {
        [.thumbsUp, .heart, .ok, .smile, .laugh, .sad, .surprised, .thinking]
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

// MARK: - Message Attachments & Content Payload

public struct MessageAttachment: Codable, Equatable, Identifiable {
    public let attachmentId: String
    public let storagePath: String
    public let fileKey: String // Base64 encoded 256-bit symmetric key
    public let nonce: String   // Base64 encoded 12-byte nonce
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let size: Int
    
    public var id: String { attachmentId }
    
    public init(
        attachmentId: String,
        storagePath: String,
        fileKey: String,
        nonce: String,
        mimeType: String = "image/jpeg",
        width: Int = 0,
        height: Int = 0,
        size: Int = 0
    ) {
        self.attachmentId = attachmentId
        self.storagePath = storagePath
        self.fileKey = fileKey
        self.nonce = nonce
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.size = size
    }
}

public struct MessageContentPayload: Codable, Equatable {
    public let text: String
    public let attachments: [MessageAttachment]
    
    public init(text: String, attachments: [MessageAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }
}

// MARK: - Local Message Decryption Wrapper

struct DecryptedMessage: Identifiable, Equatable {
    let message: FriendsMessage
    var senderName: String
    let plainText: String
    let isDecrypted: Bool
    let reactions: [FriendsMessageReaction]
    let myReaction: FriendsReactionType?
    let attachments: [MessageAttachment]
    
    var id: String { message.messageID }
    var chatID: String { message.chatID }
    var senderID: String { message.senderID }
    var createdDate: Date { message.createdDate }
    var isFromMe: Bool { false }
    var decryptedText: String { plainText }
    var reactionCounts: [String: Int32] { message.reactionCounts }
    var hasAttachments: Bool { !attachments.isEmpty }
    
    init(
        message: FriendsMessage,
        senderName: String = "",
        plainText: String = "",
        decryptedText: String? = nil,
        isDecrypted: Bool = true,
        reactions: [FriendsMessageReaction] = [],
        myReaction: FriendsReactionType? = nil,
        attachments: [MessageAttachment] = []
    ) {
        self.message = message
        self.senderName = senderName
        self.isDecrypted = isDecrypted
        self.reactions = reactions
        self.myReaction = myReaction
        
        let candidateText = decryptedText ?? plainText
        // JSON ペイロード (MessageContentPayload) のパース試行
        if let data = candidateText.data(using: .utf8),
           let payload = try? JSONDecoder().decode(MessageContentPayload.self, from: data) {
            self.plainText = payload.text
            self.attachments = !attachments.isEmpty ? attachments : payload.attachments
        } else {
            self.plainText = candidateText
            self.attachments = attachments
        }
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


import Foundation

// MARK: - InAppToast Model
// アプリ内トースト通知用のデータモデル

public struct InAppToast: Identifiable, Equatable {
    public let id: String
    public let chatId: String
    public let senderId: String
    public let senderName: String
    public let messageText: String
    public let createdAt: Date
    public let isGroup: Bool
    public let avatarNonce: String
    public let avatarUpdatedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        chatId: String,
        senderId: String,
        senderName: String,
        messageText: String,
        createdAt: Date = Date(),
        isGroup: Bool = false,
        avatarNonce: String = "",
        avatarUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.senderName = senderName
        self.messageText = messageText
        self.createdAt = createdAt
        self.isGroup = isGroup
        self.avatarNonce = avatarNonce
        self.avatarUpdatedAt = avatarUpdatedAt
    }
}

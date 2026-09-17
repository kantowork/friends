import Foundation

// MARK: - UserDevice
/// プッシュ通知用端末情報モデル
public struct UserDevice: Identifiable, Sendable, Equatable {
    public let id: String // deviceId
    public let deviceName: String
    public let fcmToken: String?
    public let apnsToken: String?
    public let platform: String
    public var enabled: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var isCurrent: Bool
    
    public init(
        id: String,
        deviceName: String,
        fcmToken: String? = nil,
        apnsToken: String? = nil,
        platform: String = "ios",
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isCurrent: Bool = false
    ) {
        self.id = id
        self.deviceName = deviceName
        self.fcmToken = fcmToken
        self.apnsToken = apnsToken
        self.platform = platform
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isCurrent = isCurrent
    }
}

import Foundation
import SwiftProtobuf

// MARK: - StoredTenant (端末ローカル永続化用テナントモデル)
// 端末内に保存する登録済みテナントのメタデータを定義します。

struct StoredTenant: Codable, Identifiable, Equatable, Sendable {
    var id: String { tenantID }
    
    let tenantID: String
    let tenantCode: String
    var tenantName: String
    let isDefaultTenant: Bool
    let joinedAt: Date
    var lastActiveAt: Date
    var workerApiUrl: String?
    
    init(
        tenantID: String,
        tenantCode: String,
        tenantName: String,
        isDefaultTenant: Bool = false,
        joinedAt: Date = Date(),
        lastActiveAt: Date = Date(),
        workerApiUrl: String? = nil
    ) {
        self.tenantID = tenantID
        self.tenantCode = tenantCode
        self.tenantName = tenantName
        self.isDefaultTenant = isDefaultTenant
        self.joinedAt = joinedAt
        self.lastActiveAt = lastActiveAt
        self.workerApiUrl = workerApiUrl
    }
    
    init(from tenant: FriendsTenant, workerApiUrl: String? = nil) {
        self.tenantID = tenant.tenantID
        self.tenantCode = tenant.tenantCode
        self.tenantName = tenant.tenantName
        self.isDefaultTenant = tenant.isDefaultTenant
        self.joinedAt = tenant.createdDate
        self.lastActiveAt = Date()
        self.workerApiUrl = workerApiUrl
    }
    
    func toFriendsTenant() -> FriendsTenant {
        FriendsTenant(
            tenantID: tenantID,
            tenantCode: tenantCode,
            tenantName: tenantName,
            isDefaultTenant: isDefaultTenant,
            createdAt: joinedAt
        )
    }
}

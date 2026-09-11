import Foundation

// MARK: - PresetTenantConfig (プリセットテナント設定ローダー)
// Bundle 内の PresetTenant.plist または preset-tenant.json からデフォルト組織情報を読み込みます。

enum PresetTenantConfig {
    private static let config: [String: Any]? = {
        guard let path = Bundle.main.path(forResource: "PresetTenant", ofType: "plist"),
              let xml = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: xml, options: .mutableContainers, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }()
    
    static var tenantId: String {
        config?["TENANT_ID"] as? String ?? "t_default"
    }
    
    static var tenantCode: String {
        config?["TENANT_CODE"] as? String ?? "kanto.work"
    }
    
    static var tenantName: String {
        config?["TENANT_NAME"] as? String ?? "デフォルト"
    }
    
    static var tenantMasterKey: String {
        config?["TENANT_MASTER_KEY"] as? String ?? ""
    }
    
    static var isDefaultTenant: Bool {
        config?["IS_DEFAULT_TENANT"] as? Bool ?? true
    }
    
    static var defaultTenant: FriendsTenant {
        FriendsTenant(
            tenantID: tenantId,
            tenantCode: tenantCode,
            tenantName: tenantName,
            isDefaultTenant: isDefaultTenant,
            tenantMasterKey: tenantMasterKey
        )
    }
}

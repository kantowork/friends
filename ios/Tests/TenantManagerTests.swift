import XCTest
@testable import Friends

@MainActor
final class TenantManagerTests: XCTestCase {
    
    var manager: TenantManager!
    
    override func setUp() async throws {
        // テスト前に UserDefaults のテナント設定をクリア
        UserDefaults.standard.removeObject(forKey: "friends_registered_tenants")
        UserDefaults.standard.removeObject(forKey: "friends_active_tenant_id")
        manager = TenantManager.shared
        manager.loadTenantsFromStorage()
    }
    
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "friends_registered_tenants")
        UserDefaults.standard.removeObject(forKey: "friends_active_tenant_id")
        manager = nil
    }
    
    func testInitialSetupContainsDefaultTenant() {
        XCTAssertFalse(manager.registeredTenants.isEmpty)
        XCTAssertEqual(manager.activeTenantId, PresetTenantConfig.tenantId)
        XCTAssertTrue(manager.registeredTenants.contains(where: { $0.tenantID == PresetTenantConfig.tenantId }))
    }
    
    func testAddAndSwitchTenant() {
        let newTenant = FriendsTenant(
            tenantID: "t_acme_corp",
            tenantCode: "acme",
            tenantName: "ACME Corporation",
            isDefaultTenant: false
        )
        
        manager.addOrUpdateTenant(tenant: newTenant, workerApiUrl: "https://acme.workers.dev")
        
        XCTAssertEqual(manager.activeTenantId, "t_acme_corp")
        XCTAssertTrue(manager.registeredTenants.contains(where: { $0.tenantID == "t_acme_corp" }))
        
        let stored = manager.registeredTenants.first(where: { $0.tenantID == "t_acme_corp" })
        XCTAssertEqual(stored?.tenantName, "ACME Corporation")
        XCTAssertEqual(stored?.workerApiUrl, "https://acme.workers.dev")
    }
    
    func testOtherTenantsUnreadExcludesActiveTenant() {
        // 3つのテナントを用意
        let defaultId = PresetTenantConfig.tenantId
        let tenantB = FriendsTenant(tenantID: "t_tenant_b", tenantCode: "b", tenantName: "Tenant B")
        let tenantC = FriendsTenant(tenantID: "t_tenant_c", tenantCode: "c", tenantName: "Tenant C")
        
        manager.addOrUpdateTenant(tenant: tenantB)
        manager.addOrUpdateTenant(tenant: tenantC)
        
        // 現在アクティブは tenantC
        XCTAssertEqual(manager.activeTenantId, "t_tenant_c")
        
        // 未読数を設定
        manager.updateUnreadCount(for: defaultId, count: 2)
        manager.updateUnreadCount(for: "t_tenant_b", count: 3)
        manager.updateUnreadCount(for: "t_tenant_c", count: 5) // 現在アクティブ
        
        // 他テナントの合計未読数 = defaultId(2) + tenantB(3) = 5 (active な tenantC の 5 は除外)
        XCTAssertEqual(manager.otherTenantsUnreadCount, 5)
        
        // アクティブを tenantB に切り替え
        manager.setActiveTenantId("t_tenant_b")
        XCTAssertEqual(manager.activeTenantId, "t_tenant_b")
        
        // 他テナントの合計未読数 = defaultId(2) + tenantC(5) = 7 (active な tenantB の 3 は除外)
        XCTAssertEqual(manager.otherTenantsUnreadCount, 7)
    }
    
    func testRemoveTenantFallback() {
        let tenantX = FriendsTenant(tenantID: "t_tenant_x", tenantCode: "x", tenantName: "Tenant X")
        manager.addOrUpdateTenant(tenant: tenantX)
        XCTAssertEqual(manager.activeTenantId, "t_tenant_x")
        
        // アクティブテナントを削除
        manager.removeTenant(tenantId: "t_tenant_x")
        
        XCTAssertFalse(manager.registeredTenants.contains(where: { $0.tenantID == "t_tenant_x" }))
        // デフォルトテナント等の残存テナントへフォールバック
        XCTAssertEqual(manager.activeTenantId, PresetTenantConfig.tenantId)
    }
    
    func testCannotRemoveDefaultTenant() {
        let defaultId = PresetTenantConfig.tenantId
        manager.removeTenant(tenantId: defaultId)
        
        // デフォルトテナントは削除されずに残る
        XCTAssertTrue(manager.registeredTenants.contains(where: { $0.tenantID == defaultId }))
    }
}

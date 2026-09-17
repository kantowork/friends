import XCTest
@testable import Friends

final class NotificationManagerTests: XCTestCase {
    
    @MainActor
    func testDeviceModelInitialization() {
        let now = Date()
        let device = UserDevice(
            id: "test-device-id",
            deviceName: "My iPhone",
            fcmToken: "fcm-token-123",
            apnsToken: "apns-token-abc",
            platform: "ios",
            enabled: true,
            createdAt: now,
            updatedAt: now,
            isCurrent: true
        )
        
        XCTAssertEqual(device.id, "test-device-id")
        XCTAssertEqual(device.deviceName, "My iPhone")
        XCTAssertEqual(device.fcmToken, "fcm-token-123")
        XCTAssertEqual(device.apnsToken, "apns-token-abc")
        XCTAssertEqual(device.platform, "ios")
        XCTAssertTrue(device.enabled)
        XCTAssertEqual(device.createdAt, now)
        XCTAssertEqual(device.updatedAt, now)
        XCTAssertTrue(device.isCurrent)
    }
    
    @MainActor
    func testNotificationManagerDeviceIdPersistence() {
        let manager = NotificationManager.shared
        let id1 = manager.deviceId
        let id2 = manager.deviceId
        
        XCTAssertFalse(id1.isEmpty)
        XCTAssertEqual(id1, id2, "Device ID should be persisted and consistent")
    }
    
    @MainActor
    func testNotificationManagerDeviceName() {
        let manager = NotificationManager.shared
        XCTAssertFalse(manager.deviceName.isEmpty)
    }
    
    @MainActor
    func testNotificationManagerToggle() {
        let manager = NotificationManager.shared
        let original = manager.isNotificationsEnabled
        
        manager.isNotificationsEnabled = false
        XCTAssertFalse(manager.isNotificationsEnabled)
        
        manager.isNotificationsEnabled = true
        XCTAssertTrue(manager.isNotificationsEnabled)
        
        manager.isNotificationsEnabled = original
    }
    
    func testNotificationLocalizationKeys() {
        XCTAssertFalse(L10n.Notification.permissionTitle.isEmpty)
        XCTAssertFalse(L10n.Notification.permissionDesc.isEmpty)
        XCTAssertFalse(L10n.Notification.enableButton.isEmpty)
        XCTAssertFalse(L10n.Notification.laterButton.isEmpty)
        
        XCTAssertFalse(L10n.Settings.sectionAppSettings.isEmpty)
        XCTAssertFalse(L10n.Settings.notificationsToggle.isEmpty)
        XCTAssertFalse(L10n.Settings.notificationsDeniedAlertTitle.isEmpty)
        XCTAssertFalse(L10n.Settings.notificationsDeniedAlertMsg.isEmpty)
        XCTAssertFalse(L10n.Settings.openSettings.isEmpty)
        XCTAssertFalse(L10n.Settings.chatFontSizeLabel.isEmpty)
    }
}

import Foundation
import UIKit
import UserNotifications
import Combine

// MARK: - NotificationManager
/// プッシュ通知の受信制御、許諾リクエスト、デバイストークン登録・アプリ設定トグルを統括するマネージャー
@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    @Published var isNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isNotificationsEnabled, forKey: notificationsEnabledKey)
        }
    }
    @Published var isNotificationAuthorized: Bool = false
    @Published var shouldShowPermissionPrompt: Bool = false
    @Published var showingDeniedSettingsAlert: Bool = false
    
    // MARK: - Private Properties
    private let deviceIdKey = "friends_device_id"
    private let notificationsEnabledKey = "friends_notifications_enabled"
    private let permissionPromptDismissedKey = "friends_notification_prompt_dismissed"
    
    private var apnsTokenHex: String?
    
    public var deviceId: String {
        if let savedId = UserDefaults.standard.string(forKey: deviceIdKey) {
            return savedId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }
    
    public var deviceName: String {
        UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name
    }
    
    private override init() {
        // デフォルトは有効 (初回起動時)
        if UserDefaults.standard.object(forKey: notificationsEnabledKey) != nil {
            self.isNotificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        } else {
            self.isNotificationsEnabled = true
        }
        
        super.init()
        
        // UNUserNotificationCenter の Delegate を設定
        UNUserNotificationCenter.current().delegate = self
        
        // 起動時に現在の通知許可状態を確認
        checkAuthorizationStatus()
    }
    
    // MARK: - Authorization
    
    /// 通知許可状態を確認
    func checkAuthorizationStatus(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = isAuthorized
                completion?(isAuthorized)
            }
        }
    }
    
    /// 通知許諾を要求し、成功時にリモート通知登録を行う
    func requestNotificationPermission(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error = error {
                AppLogger.error("Notification authorization request failed: \(error.localizedDescription)", category: .auth)
            }
            
            DispatchQueue.main.async {
                self?.isNotificationAuthorized = granted
                if granted {
                    self?.isNotificationsEnabled = true
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    self?.isNotificationsEnabled = false
                }
                self?.markPromptAsHandled()
                self?.syncCurrentDevice()
                completion?(granted)
            }
        }
    }
    
    /// 設定画面の「通知」トグル切り替え時の処理
    func handleToggleChange(enabled: Bool) {
        if enabled {
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch settings.authorizationStatus {
                    case .notDetermined:
                        self.requestNotificationPermission { granted in
                            if !granted {
                                self.isNotificationsEnabled = false
                            }
                        }
                    case .denied:
                        self.isNotificationsEnabled = false
                        self.showingDeniedSettingsAlert = true
                    case .authorized, .provisional, .ephemeral:
                        self.isNotificationsEnabled = true
                        self.syncNotificationEnabledStatus(enabled: true)
                    @unknown default:
                        self.isNotificationsEnabled = true
                        self.syncNotificationEnabledStatus(enabled: true)
                    }
                }
            }
        } else {
            self.isNotificationsEnabled = false
            syncNotificationEnabledStatus(enabled: false)
        }
    }
    
    /// 初回プロンプトの表示要否を判定
    func evaluatePermissionPromptNeed() {
        let dismissed = UserDefaults.standard.bool(forKey: permissionPromptDismissedKey)
        if dismissed {
            shouldShowPermissionPrompt = false
            return
        }
        
        checkAuthorizationStatus { [weak self] authorized in
            if !authorized {
                self?.shouldShowPermissionPrompt = true
            }
        }
    }
    
    /// プロンプトをスキップまたは完了として記録
    func markPromptAsHandled() {
        UserDefaults.standard.set(true, forKey: permissionPromptDismissedKey)
        shouldShowPermissionPrompt = false
        syncCurrentDevice()
    }
    
    // MARK: - Device Registration & Token
    
    /// APNs トークン受信時のハンドラ
    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.apnsTokenHex = tokenString
        AppLogger.info("Received APNs device token: \(tokenString.prefix(12))...", category: .auth)
        
        syncCurrentDevice()
    }
    
    /// 現在の端末情報を Firestore に同期・登録
    func syncCurrentDevice(completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard let tenant = AuthService.shared.currentTenant,
              let user = AuthService.shared.currentUser else {
            AppLogger.warning("[DEVICE] Cannot sync device: user or tenant not authenticated yet.", category: .auth)
            completion?(.failure(NSError(domain: "NotificationManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])))
            return
        }
        
        AppLogger.info("[DEVICE] Syncing device to Firestore: deviceId=\(deviceId), enabled=\(isNotificationsEnabled)", category: .auth)
        
        let device = UserDevice(
            id: deviceId,
            deviceName: deviceName,
            fcmToken: nil,
            apnsToken: apnsTokenHex,
            platform: "ios",
            enabled: isNotificationsEnabled,
            createdAt: Date(),
            updatedAt: Date(),
            isCurrent: true
        )
        
        DeviceRepository.shared.registerOrUpdateDevice(
            tenantId: tenant.tenantID,
            userId: user.userID,
            device: device
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    AppLogger.info("[DEVICE] Device successfully registered/updated in Firestore: \(device.id)", category: .auth)
                case .failure(let error):
                    AppLogger.error("[DEVICE] Failed to register/update device: \(error.localizedDescription)", category: .auth)
                }
                completion?(result)
            }
        }
    }
    
    /// Firestore 上の通知有効化フラグを更新
    private func syncNotificationEnabledStatus(enabled: Bool) {
        guard let tenant = AuthService.shared.currentTenant,
              let user = AuthService.shared.currentUser else { return }
        
        DeviceRepository.shared.updateDeviceNotificationEnabled(
            tenantId: tenant.tenantID,
            userId: user.userID,
            deviceId: deviceId,
            enabled: enabled
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate (フォアグラウンド通知抑制)
extension NotificationManager: UNUserNotificationCenterDelegate {
    
    /// アプリ起動中（フォアグラウンド）に通知を受信した時の処理
    /// ★ 要件: アプリを開いている場合は通知を受け取っても通知として取り扱わない
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        AppLogger.info("Push notification received in foreground. Suppressing system banner.", category: .auth)
        // 空のオプションを返すことで、システム通知バナー・サウンド・バッジを破棄
        completionHandler([])
    }
    
    /// バックグラウンドの通知バナーをユーザーがタップした時の処理
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        AppLogger.info("User tapped notification banner. payload: \(userInfo)", category: .auth)
        
        if let chatId = userInfo["chatId"] as? String {
            Task { @MainActor in
                ToastNotificationManager.shared.handleToastTap(
                    InAppToast(
                        chatId: chatId,
                        senderId: (userInfo["senderId"] as? String) ?? "",
                        senderName: "",
                        messageText: response.notification.request.content.body
                    )
                )
            }
        }
        
        completionHandler()
    }
}

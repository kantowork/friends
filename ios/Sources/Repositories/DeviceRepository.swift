import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DeviceRepository
/// デバイスおよびプッシュ通知トークン管理を行うデータアクセスリポジトリ
final class DeviceRepository {
    static let shared = DeviceRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// ユーザーの登録デバイス一覧を取得 (DP-01)
    func listDevices(
        tenantId: String,
        userId: String,
        currentDeviceId: String,
        completion: @escaping (Result<[UserDevice], Error>) -> Void
    ) {
        db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("devices")
            .order(by: "updatedAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    AppLogger.error("Failed to list devices: \(error.localizedDescription)", category: .auth)
                    completion(.failure(error))
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion(.success([]))
                    return
                }
                
                let devices: [UserDevice] = documents.compactMap { doc in
                    let data = doc.data()
                    let id = doc.documentID
                    let deviceName = data["deviceName"] as? String ?? "Unknown Device"
                    let fcmToken = data["fcmToken"] as? String
                    let apnsToken = data["apnsToken"] as? String
                    let platform = data["platform"] as? String ?? "ios"
                    let enabled = (data["enabled"] as? Bool) ?? true
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    return UserDevice(
                        id: id,
                        deviceName: deviceName,
                        fcmToken: fcmToken,
                        apnsToken: apnsToken,
                        platform: platform,
                        enabled: enabled,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        isCurrent: (id == currentDeviceId)
                    )
                }
                
                completion(.success(devices))
            }
    }
    
    /// デバイス登録・トークン更新 (DP-02)
    func registerOrUpdateDevice(
        tenantId: String,
        userId: String,
        device: UserDevice,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let docRef = db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("devices").document(device.id)
        
        var data: [String: Any] = [
            "deviceId": device.id,
            "deviceName": device.deviceName,
            "platform": device.platform,
            "enabled": device.enabled,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": userId
        ]
        
        if let fcm = device.fcmToken {
            data["fcmToken"] = fcm
        }
        if let apns = device.apnsToken {
            data["apnsToken"] = apns
        }
        
        let currentAuthUid = Auth.auth().currentUser?.uid ?? "nil"
        AppLogger.info("[DEVICE DEBUG] registerOrUpdateDevice: authUid=\(currentAuthUid), userId=\(userId), tenantId=\(tenantId), deviceId=\(device.id)", category: .auth)
        
        docRef.getDocument { snapshot, error in
            if let error = error {
                AppLogger.error("[DEVICE DEBUG] Failed to fetch device before registration: \(error.localizedDescription) (authUid=\(currentAuthUid), userId=\(userId))", category: .auth)
                completion?(.failure(error))
                return
            }
            
            if !(snapshot?.exists ?? false) {
                // 初回登録時のみ createdAt / createdBy を追加
                data["createdAt"] = FieldValue.serverTimestamp()
                data["createdBy"] = userId
            }
            
            docRef.setData(data, merge: true) { err in
                if let err = err {
                    AppLogger.error("Failed to save device document: \(err.localizedDescription)", category: .auth)
                    completion?(.failure(err))
                } else {
                    AppLogger.info("Device registered successfully: \(device.id)", category: .auth)
                    completion?(.success(()))
                }
            }
        }
    }
    
    /// 通知有効化フラグの更新 (DP-03)
    func updateDeviceNotificationEnabled(
        tenantId: String,
        userId: String,
        deviceId: String,
        enabled: Bool,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        let docRef = db.collection("tenants").document(tenantId)
            .collection("users").document(userId)
            .collection("devices").document(deviceId)
        
        let updates: [String: Any] = [
            "enabled": enabled,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": userId
        ]
        
        docRef.updateData(updates) { error in
            if let error = error {
                AppLogger.error("Failed to update notification enabled status: \(error.localizedDescription)", category: .auth)
                completion?(.failure(error))
            } else {
                AppLogger.info("Device notification enabled updated: \(deviceId) -> \(enabled)", category: .auth)
                completion?(.success(()))
            }
        }
    }
}

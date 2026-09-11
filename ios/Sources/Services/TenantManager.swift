import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - TenantManager (複数テナント管理・永続化および他テナント未読集計)
// 端末内に保存された複数テナントの管理、アクティブテナントの切り替え、および各テナントの未読集計を担当します。

final class TenantManager: ObservableObject {
    static let shared = TenantManager()
    
    private let userDefaultsKeyTenants = "friends_registered_tenants"
    private let userDefaultsKeyActiveTenantId = "friends_active_tenant_id"
    private let db = Firestore.firestore()
    
    /// 登録済みテナント一覧
    @Published private(set) var registeredTenants: [StoredTenant] = []
    
    /// 現在アクティブなテナントID
    @Published private(set) var activeTenantId: String = ""
    
    /// 各テナントごとの未読数 (tenantId -> count)
    @Published private(set) var tenantUnreadCounts: [String: Int] = [:]
    
    /// 他テナントの合計未読数（現在開いているアクティブテナントの未読は計上から除外）
    @Published private(set) var otherTenantsUnreadCount: Int = 0
    
    /// 現在アクティブな StoredTenant
    var activeTenant: StoredTenant? {
        registeredTenants.first(where: { $0.tenantID == activeTenantId })
    }
    
    private init() {
        loadTenantsFromStorage()
    }
    
    // MARK: - Storage Persistence
    
    /// ローカルストレージ (UserDefaults) からテナント一覧とアクティブテナントを復元
    func loadTenantsFromStorage() {
        var tenants: [StoredTenant] = []
        if let data = UserDefaults.standard.data(forKey: userDefaultsKeyTenants),
           let decoded = try? JSONDecoder().decode([StoredTenant].self, from: data),
           !decoded.isEmpty {
            tenants = decoded
        } else {
            // 初期状態: PresetTenantConfig のデフォルトテナントを登録
            let defaultStored = StoredTenant(from: PresetTenantConfig.defaultTenant)
            tenants = [defaultStored]
            if let encoded = try? JSONEncoder().encode(tenants) {
                UserDefaults.standard.set(encoded, forKey: userDefaultsKeyTenants)
            }
        }
        let savedActiveId = UserDefaults.standard.string(forKey: userDefaultsKeyActiveTenantId) ?? ""
        let resolvedActiveId: String
        if !savedActiveId.isEmpty && tenants.contains(where: { $0.tenantID == savedActiveId }) {
            resolvedActiveId = savedActiveId
        } else {
            resolvedActiveId = tenants.first?.tenantID ?? PresetTenantConfig.tenantId
            UserDefaults.standard.set(resolvedActiveId, forKey: userDefaultsKeyActiveTenantId)
        }
        
        if Thread.isMainThread {
            self.registeredTenants = tenants
            self.activeTenantId = resolvedActiveId
            self.recalculateOtherTenantsUnreadCount()
        } else {
            DispatchQueue.main.async {
                self.registeredTenants = tenants
                self.activeTenantId = resolvedActiveId
                self.recalculateOtherTenantsUnreadCount()
            }
        }
    }
    
    private func saveTenantsToStorage() {
        if let encoded = try? JSONEncoder().encode(registeredTenants) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKeyTenants)
        }
    }
    
    // MARK: - Tenant Operations
    
    /// テナントを登録一覧に追加（または既存情報を更新）し、アクティブテナントに設定
    func addOrUpdateTenant(tenant: FriendsTenant, workerApiUrl: String? = nil) {
        let block = {
            if let index = self.registeredTenants.firstIndex(where: { $0.tenantID == tenant.tenantID }) {
                var updated = self.registeredTenants[index]
                updated.tenantName = tenant.tenantName
                updated.lastActiveAt = Date()
                if let url = workerApiUrl, !url.isEmpty {
                    updated.workerApiUrl = url
                }
                self.registeredTenants[index] = updated
            } else {
                let newStored = StoredTenant(from: tenant, workerApiUrl: workerApiUrl)
                self.registeredTenants.append(newStored)
            }
            
            self.activeTenantId = tenant.tenantID
            UserDefaults.standard.set(self.activeTenantId, forKey: self.userDefaultsKeyActiveTenantId)
            self.saveTenantsToStorage()
            self.recalculateOtherTenantsUnreadCount()
        }
        
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    /// アクティブテナントを変更
    func setActiveTenantId(_ tenantId: String) {
        let block = {
            guard self.registeredTenants.contains(where: { $0.tenantID == tenantId }) else { return }
            self.activeTenantId = tenantId
            UserDefaults.standard.set(tenantId, forKey: self.userDefaultsKeyActiveTenantId)
            
            if let index = self.registeredTenants.firstIndex(where: { $0.tenantID == tenantId }) {
                self.registeredTenants[index].lastActiveAt = Date()
                self.saveTenantsToStorage()
            }
            
            self.recalculateOtherTenantsUnreadCount()
        }
        
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    /// テナントを登録一覧から削除（離脱）
    func removeTenant(tenantId: String) {
        // デフォルトテナントは削除不可
        guard tenantId != PresetTenantConfig.tenantId else { return }
        
        let block = {
            self.registeredTenants.removeAll(where: { $0.tenantID == tenantId })
            self.tenantUnreadCounts.removeValue(forKey: tenantId)
            
            // Keychain からテナントマスターキーを削除
            CryptoKeyManager.shared.deleteTenantMasterKey(tenantId: tenantId)
            
            // もし削除したテナントがアクティブだった場合は別テナントへフォールバック
            if self.activeTenantId == tenantId {
                let fallbackId = self.registeredTenants.first?.tenantID ?? PresetTenantConfig.tenantId
                self.setActiveTenantId(fallbackId)
            } else {
                self.recalculateOtherTenantsUnreadCount()
            }
            
            self.saveTenantsToStorage()
        }
        
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    // MARK: - Unread Badge Management
    
    /// 特定テナントの未読数を更新
    func updateUnreadCount(for tenantId: String, count: Int) {
        let safeCount = max(0, count)
        let block = {
            self.tenantUnreadCounts[tenantId] = safeCount
            self.recalculateOtherTenantsUnreadCount()
        }
        
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    /// 他テナントの合計未読数を再計算（現在アクティブなテナントの未読は計上から除外）
    func recalculateOtherTenantsUnreadCount() {
        var total = 0
        for (tenantId, count) in tenantUnreadCounts {
            if tenantId != activeTenantId {
                total += count
            }
        }
        self.otherTenantsUnreadCount = total
    }
    
    // MARK: - Background Unread Fetching for Inactive Tenants
    
    /// 非アクティブテナントの未読メッセージ・通知数をバックグラウンドでフェッチして更新
    func refreshUnreadCounts() {
        guard let authUid = Auth.auth().currentUser?.uid else { return }
        
        for tenant in registeredTenants {
            // アクティブテナントの未読数は MessageService が常時リアルタイム同期しているためスキップ
            if tenant.tenantID == activeTenantId {
                continue
            }
            
            fetchUnreadCountForInactiveTenant(tenantId: tenant.tenantID, authUid: authUid)
        }
    }
    
    private func fetchUnreadCountForInactiveTenant(tenantId: String, authUid: String) {
        // 1. 当該テナントのユーザープロファイル（userId）を取得
        UserRepository.shared.getUserProfileByUid(tenantId: tenantId, uid: authUid) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let userProfile):
                let userId = userProfile.userID
                // 2. 当該テナントで自分が参加しているチャットを取得
                self.db.collection("tenants")
                    .document(tenantId)
                    .collection("chats")
                    .whereField("members", arrayContains: userId)
                    .getDocuments { snapshot, error in
                        guard let documents = snapshot?.documents, error == nil else { return }
                        
                        var totalUnread = 0
                        let group = DispatchGroup()
                        
                        for doc in documents {
                            let chatId = doc.documentID
                            let data = doc.data()
                            let lastMessageAt = (data["lastMessageAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                            
                            group.enter()
                            // 各チャットの自分の既読レシートを取得
                            self.db.collection("tenants")
                                .document(tenantId)
                                .collection("chats")
                                .document(chatId)
                                .collection("receipts")
                                .document(userId)
                                .getDocument { receiptDoc, _ in
                                    defer { group.leave() }
                                    let lastReadAt = (receiptDoc?.data()?["lastReadAt"] as? Timestamp)?.dateValue() ?? Date.distantPast
                                    // 最新メッセージが最終既読時刻より新しければ未読ありとみなす
                                    if lastMessageAt > lastReadAt.addingTimeInterval(0.1) {
                                        totalUnread += 1
                                    }
                                }
                        }
                        
                        group.notify(queue: .main) {
                            self.updateUnreadCount(for: tenantId, count: totalUnread)
                        }
                    }
            case .failure:
                // 未参加テナント等の場合は 0
                self.updateUnreadCount(for: tenantId, count: 0)
            }
        }
    }
}

import Foundation
import FirebaseFirestore

final class TenantRepository {
    static let shared = TenantRepository()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// デフォルトテナントを取得 (TP-01)
    func fetchDefaultTenant(completion: @escaping (Result<FriendsTenant, Error>) -> Void) {
        // 1. PresetTenantConfig の tenantId によるピンポイント検索
        let presetId = PresetTenantConfig.tenantId
        db.collection("tenants").document(presetId).getDocument { [weak self] docSnapshot, _ in
            guard let self = self else { return }
            if let doc = docSnapshot, doc.exists {
                let tenant = self.mapTenant(doc: doc)
                completion(.success(tenant))
                return
            }
            
            // 2. isDefaultTenant == true の検索
            self.db.collection("tenants")
                .whereField("isDefaultTenant", isEqualTo: true)
                .limit(to: 1)
                .getDocuments { [weak self] snapshot, error in
                    guard let self = self else { return }
                    if let doc = snapshot?.documents.first {
                        let tenant = self.mapTenant(doc: doc)
                        completion(.success(tenant))
                    } else {
                        // 3. PresetTenantConfig のデフォルト設定を最終フォールバックとして利用
                        completion(.success(PresetTenantConfig.defaultTenant))
                    }
                }
        }
    }
    
    /// テナントIDからテナント情報を取得 (TP-02)
    func getTenantByTenantId(tenantId: String, completion: @escaping (Result<FriendsTenant, Error>) -> Void) {
        db.collection("tenants").document(tenantId).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let doc = snapshot, doc.exists else {
                let err = NSError(domain: "TenantError", code: 404, userInfo: [NSLocalizedDescriptionKey: "指定されたテナントが見つかりません。"])
                completion(.failure(err))
                return
            }
            let tenant = self.mapTenant(doc: doc)
            completion(.success(tenant))
        }
    }
    
    private func mapTenant(doc: DocumentSnapshot) -> FriendsTenant {
        let data = doc.data() ?? [:]
        let tenantCode = data["tenantCode"] as? String ?? doc.documentID.replacingOccurrences(of: "t_", with: "")
        let isDefault = data["isDefaultTenant"] as? Bool ?? false
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let encryptedTenantName = data["encryptedTenantName"] as? String ?? ""
        let tenantNameNonce = data["tenantNameNonce"] as? String ?? ""
        
        var resolvedName = data["tenantName"] as? String ?? ""
        if !encryptedTenantName.isEmpty {
            if let decrypted = try? CryptoKeyManager.shared.decryptWithTenantKey(
                encryptedData: encryptedTenantName,
                nonce: tenantNameNonce,
                tenantId: doc.documentID
            ) {
                resolvedName = decrypted
            } else if doc.documentID == PresetTenantConfig.tenantId && !PresetTenantConfig.tenantName.isEmpty {
                resolvedName = PresetTenantConfig.tenantName
            } else {
                resolvedName = !tenantCode.isEmpty ? "@\(tenantCode)" : "組織 (\(doc.documentID))"
            }
        } else if resolvedName.isEmpty {
            resolvedName = (doc.documentID == PresetTenantConfig.tenantId) ? PresetTenantConfig.tenantName : "組織"
        }
        
        return FriendsTenant(
            tenantID: doc.documentID,
            tenantCode: tenantCode,
            tenantName: resolvedName,
            isDefaultTenant: isDefault,
            encryptedTenantName: encryptedTenantName,
            tenantNameNonce: tenantNameNonce,
            createdAt: createdAt
        )
    }
}

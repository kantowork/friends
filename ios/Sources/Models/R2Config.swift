import Foundation

// MARK: - R2Config (Cloudflare R2 環境設定ローダー)
// Bundle 内の R2Config.plist から R2 の公開 URL、エンドポイント、認証情報を安全に取得します。

public enum R2Config {
    private static let keyPublicBaseURL = "friends_r2_public_base_url"
    private static let keyBucketName = "friends_r2_bucket_name"
    private static let keyEndpointURL = "friends_r2_endpoint_url"
    private static let keyAccessKeyId = "friends_r2_access_key_id"
    private static let keySecretAccessKey = "friends_r2_secret_access_key"

    private static let configFromPlist: [String: Any]? = {
        guard let path = Bundle.main.path(forResource: "R2Config", ofType: "plist"),
              let xml = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: xml, options: .mutableContainers, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }()
    
    /// ダウンロード用 CDN 公開ベース URL (例: https://bucket.friends.example.com)
    public static var publicBaseURL: String {
        if let val = configFromPlist?["R2_PUBLIC_BASE_URL"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: keyPublicBaseURL) ?? ""
    }
    
    /// R2 バケット名 (例: friends-kantowork)
    public static var bucketName: String {
        if let val = configFromPlist?["R2_BUCKET_NAME"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: keyBucketName) ?? "friends-media"
    }
    
    /// S3 互換 エンドポイント URL (例: https://<ACCOUNT_ID>.r2.cloudflarestorage.com)
    public static var endpointURL: String {
        if let val = configFromPlist?["R2_ENDPOINT_URL"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: keyEndpointURL) ?? ""
    }
    
    /// S3 互換 Access Key ID
    public static var accessKeyId: String {
        if let val = configFromPlist?["R2_ACCESS_KEY_ID"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: keyAccessKeyId) ?? ""
    }
    
    /// S3 互換 Secret Access Key
    public static var secretAccessKey: String {
        if let val = configFromPlist?["R2_SECRET_ACCESS_KEY"] as? String, !val.isEmpty {
            return val
        }
        return UserDefaults.standard.string(forKey: keySecretAccessKey) ?? ""
    }
    
    /// 設定が有効（ベースURLまたはエンドポイントが設定されているか）
    public static var isConfigured: Bool {
        return !publicBaseURL.isEmpty || !endpointURL.isEmpty
    }
    
    /// テナント QR スキャン等で取得した R2 設定を動的に保存
    public static func saveConfig(
        publicBaseURL: String?,
        bucketName: String?,
        endpointURL: String?,
        accessKeyId: String?,
        secretAccessKey: String?
    ) {
        if let pub = publicBaseURL { UserDefaults.standard.set(pub, forKey: keyPublicBaseURL) }
        if let bkt = bucketName { UserDefaults.standard.set(bkt, forKey: keyBucketName) }
        if let ep = endpointURL { UserDefaults.standard.set(ep, forKey: keyEndpointURL) }
        if let ak = accessKeyId { UserDefaults.standard.set(ak, forKey: keyAccessKeyId) }
        if let sk = secretAccessKey { UserDefaults.standard.set(sk, forKey: keySecretAccessKey) }
    }
}

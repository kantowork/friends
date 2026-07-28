import Foundation

// MARK: - R2Config (Cloudflare R2 環境設定ローダー)
// Bundle 内の R2Config.plist から R2 の公開 URL、エンドポイント、認証情報を安全に取得します。

public enum R2Config {
    private static let config: [String: Any]? = {
        guard let path = Bundle.main.path(forResource: "R2Config", ofType: "plist"),
              let xml = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: xml, options: .mutableContainers, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }()
    
    /// ダウンロード用 CDN 公開ベース URL (例: https://media.yourdomain.com)
    public static var publicBaseURL: String {
        config?["R2_PUBLIC_BASE_URL"] as? String ?? ""
    }
    
    /// R2 バケット名 (例: friends-media)
    public static var bucketName: String {
        config?["R2_BUCKET_NAME"] as? String ?? "friends-media"
    }
    
    /// S3 互換 エンドポイント URL (例: https://<ACCOUNT_ID>.r2.cloudflarestorage.com)
    public static var endpointURL: String {
        config?["R2_ENDPOINT_URL"] as? String ?? ""
    }
    
    /// S3 互換 Access Key ID
    public static var accessKeyId: String {
        config?["R2_ACCESS_KEY_ID"] as? String ?? ""
    }
    
    /// S3 互換 Secret Access Key
    public static var secretAccessKey: String {
        config?["R2_SECRET_ACCESS_KEY"] as? String ?? ""
    }
    
    /// 設定が有効（ベースURLまたはエンドポイントが設定されているか）
    public static var isConfigured: Bool {
        return !publicBaseURL.isEmpty || !endpointURL.isEmpty
    }
}

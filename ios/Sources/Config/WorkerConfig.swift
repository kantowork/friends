import Foundation

/// Cloudflare Workers バックエンド設定
/// - 注: セキュリティおよび構成管理の隔離のため、本番 URL はソースコードに一切ハードコードせず、
///        管理者が発行した「テナント 二次元コード」のスキャン時にのみ動的に注入・ローカル保存されます。
public enum RecoveryConfig {
    private static let userDefaultsKey = "friends_workers_api_url"
    
    /// Cloudflare Workers のベース URL
    /// 1. 環境変数 (CI / ローカルテスト用: FRIENDS_WORKERS_URL)
    /// 2. テナント 二次元コードスキャン時に動的保存された URL
    /// 3. 未設定の場合は nil
    public static var workersBaseURL: URL? {
        if let envUrlString = ProcessInfo.processInfo.environment["FRIENDS_WORKERS_URL"],
           let url = URL(string: envUrlString) {
            return url
        }
        if let savedString = UserDefaults.standard.string(forKey: userDefaultsKey),
           let url = URL(string: savedString) {
            return url
        }
        return nil
    }
    
    /// テナント 二次元コードスキャン等で取得した Workers URL を動的に保存
    public static func saveWorkersBaseURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else {
            return
        }
        UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
    }
    
    /// 保存された Workers URL を消去
    public static func clearWorkersBaseURL() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

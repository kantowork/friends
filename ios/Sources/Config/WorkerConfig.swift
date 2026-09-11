import Foundation

/// Cloudflare Workers バックエンド設定ローダー
/// - 注: セキュリティおよび構成管理の隔離のため、本番 URL はソースコードに一切ハードコードせず、
///        管理者が発行した「テナント 二次元コード」のスキャン時（TenantManager）または PresetTenant.plist より読み込まれます。
public enum WorkerConfig {
    /// テスト用一時オーバーライド URL
    public static var testOverrideURL: String? = nil

    /// Cloudflare Workers のベース URL
    /// 1. テスト用一時オーバーライド
    /// 2. 環境変数 (CI / ローカルテスト用: FRIENDS_WORKERS_URL)
    /// 3. 現在アクティブなテナント（またはプリセットデフォルトテナント）の workerApiUrl
    /// 4. 未設定の場合は nil
    public static var baseURL: URL? {
        if let overrideString = testOverrideURL, let url = URL(string: overrideString), url.scheme == "http" || url.scheme == "https" {
            return url
        }
        if let envUrlString = ProcessInfo.processInfo.environment["FRIENDS_WORKERS_URL"],
           let url = URL(string: envUrlString) {
            return url
        }
        let workerUrlString = TenantManager.shared.activeTenant?.workerApiUrl ?? PresetTenantConfig.workerApiUrl
        if let urlString = workerUrlString, let url = URL(string: urlString) {
            return url
        }
        return nil
    }
}

import Foundation

// MARK: - LicenseItem Model
// SPM 依存ライブラリのライセンス情報モデル (Codable / Sendable)

public struct LicenseItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let url: String
    public let license: String
    
    public init(id: String, name: String, version: String, url: String, license: String) {
        self.id = id
        self.name = name
        self.version = version
        self.url = url
        self.license = license
    }
}

// MARK: - LicenseLoader
// Bundle 内の licenses.json をロードするシングルトンヘルパー

public final class LicenseLoader: @unchecked Sendable {
    public static let shared = LicenseLoader()
    
    private var cachedLicenses: [LicenseItem]?
    private let lock = NSLock()
    
    private init() {}
    
    public func loadLicenses() -> [LicenseItem] {
        lock.lock()
        defer { lock.unlock() }
        
        if let cached = cachedLicenses {
            return cached
        }
        
        // Bundle 内から licenses.json を検索
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "json") ??
                Bundle(for: LicenseLoader.self).url(forResource: "licenses", withExtension: "json") else {
            // 見つからない場合は空配列
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let items = try decoder.decode([LicenseItem].self, from: data)
            self.cachedLicenses = items
            return items
        } catch {
            return []
        }
    }
}

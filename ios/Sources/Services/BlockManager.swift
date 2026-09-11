import Foundation
import SwiftUI

// MARK: - BlockManager
/// 迷惑ユーザーのブロック状態（テナント別）を管理し、メッセージ表示・通知・DM送受信を制御するサービス
public final class BlockManager: ObservableObject {
    public static let shared = BlockManager()

    @Published public private(set) var blockedUserIds: Set<String> = []

    private let userDefaultsKeyPrefix = "work.kanto.friends.blocked_users."
    private var currentTenantId: String?

    private init() {}

    // MARK: - Configuration

    /// テナント切り替え時にブロックリストをロードする
    public func configure(tenantId: String) {
        self.currentTenantId = tenantId
        loadBlockedUsers()
    }

    // MARK: - Block Actions

    /// 指定ユーザーがブロックされているか判定
    public func isBlocked(userId: String) -> Bool {
        return blockedUserIds.contains(userId)
    }

    /// 指定ユーザーをブロックする
    public func block(userId: String) {
        guard !userId.isEmpty else { return }
        blockedUserIds.insert(userId)
        saveBlockedUsers()
    }

    /// 指定ユーザーのブロックを解除する
    public func unblock(userId: String) {
        blockedUserIds.remove(userId)
        saveBlockedUsers()
    }

    // MARK: - Persistence

    private func storageKey() -> String {
        let tid = currentTenantId ?? "default"
        return "\(userDefaultsKeyPrefix)\(tid)"
    }

    private func loadBlockedUsers() {
        let key = storageKey()
        if let savedArray = UserDefaults.standard.stringArray(forKey: key) {
            self.blockedUserIds = Set(savedArray)
        } else {
            self.blockedUserIds = []
        }
    }

    private func saveBlockedUsers() {
        let key = storageKey()
        let array = Array(blockedUserIds)
        UserDefaults.standard.set(array, forKey: key)
    }

    /// ログアウト・アカウント削除時にローカルのブロックリストを初期化
    public func clear() {
        blockedUserIds.removeAll()
        if let tid = currentTenantId {
            UserDefaults.standard.removeObject(forKey: "\(userDefaultsKeyPrefix)\(tid)")
        }
    }
}

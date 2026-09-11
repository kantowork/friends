import Foundation

// MARK: - UserProfileResolver
/// 認証ユーザー、友達キャッシュ、グループメンバーキャッシュを横断してプロファイル（表示名・アバター）を解決するヘルパー
@MainActor
enum UserProfileResolver {
    static func resolve(userId: String) -> FriendsPublicUserProfile? {
        if let current = AuthService.shared.currentUser, current.userID == userId {
            return current
        }
        if let friend = DirectChatService.shared.friendProfile(for: userId) {
            return friend
        }
        if let member = GroupChatService.shared.memberProfile(for: userId) {
            return member
        }
        return nil
    }
}

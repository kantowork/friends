import XCTest
@testable import Friends

final class ReactionTypeTests: XCTestCase {
    
    // MARK: - Emoji & Key Mapping Tests
    
    func testReactionEmojiMapping() {
        XCTAssertEqual(FriendsReactionType.thumbsUp.emoji, "👍")
        XCTAssertEqual(FriendsReactionType.heart.emoji, "❤️")
        XCTAssertEqual(FriendsReactionType.ok.emoji, "🆗")
        XCTAssertEqual(FriendsReactionType.smile.emoji, "😊")
        XCTAssertEqual(FriendsReactionType.laugh.emoji, "🤣")
        XCTAssertEqual(FriendsReactionType.sad.emoji, "😢")
        XCTAssertEqual(FriendsReactionType.surprised.emoji, "😱")
        XCTAssertEqual(FriendsReactionType.thinking.emoji, "🤔")
        XCTAssertEqual(FriendsReactionType.unspecified.emoji, "❓")
    }
    
    func testReactionKeyMapping() {
        XCTAssertEqual(FriendsReactionType.thumbsUp.key, "thumbs_up")
        XCTAssertEqual(FriendsReactionType.heart.key, "heart")
        XCTAssertEqual(FriendsReactionType.ok.key, "ok")
        XCTAssertEqual(FriendsReactionType.smile.key, "smile")
        XCTAssertEqual(FriendsReactionType.laugh.key, "laugh")
        XCTAssertEqual(FriendsReactionType.sad.key, "sad")
        XCTAssertEqual(FriendsReactionType.surprised.key, "surprised")
        XCTAssertEqual(FriendsReactionType.thinking.key, "thinking")
        XCTAssertEqual(FriendsReactionType.unspecified.key, "unspecified")
    }
    
    func testReactionFromKey() {
        XCTAssertEqual(FriendsReactionType.fromKey("thumbs_up"), .thumbsUp)
        XCTAssertEqual(FriendsReactionType.fromKey("heart"), .heart)
        XCTAssertEqual(FriendsReactionType.fromKey("ok"), .ok)
        XCTAssertEqual(FriendsReactionType.fromKey("smile"), .smile)
        XCTAssertEqual(FriendsReactionType.fromKey("laugh"), .laugh)
        XCTAssertEqual(FriendsReactionType.fromKey("sad"), .sad)
        XCTAssertEqual(FriendsReactionType.fromKey("surprised"), .surprised)
        XCTAssertEqual(FriendsReactionType.fromKey("thinking"), .thinking)
        XCTAssertEqual(FriendsReactionType.fromKey("unknown_key"), .unspecified)
    }
    
    // MARK: - Quick Actions & All Active Types Tests
    
    func testQuickActionTypes() {
        let quickActions = FriendsReactionType.quickActionTypes
        XCTAssertEqual(quickActions.count, 7, "クイックアクションは7種類（👍, ❤️, 🆗, 😊, 🤣, 😢, 😱）である必要があります")
        
        let expected: [FriendsReactionType] = [
            .thumbsUp, .heart, .ok, .smile, .laugh, .sad, .surprised
        ]
        XCTAssertEqual(quickActions, expected)
        
        // 重複がないこと
        let uniqueCount = Set(quickActions).count
        XCTAssertEqual(uniqueCount, 7)
    }
    
    func testAllActiveTypes() {
        let allActive = FriendsReactionType.allActiveTypes
        XCTAssertEqual(allActive.count, 8, "全アクティブリアクションは8種類である必要があります")
        
        let expected: [FriendsReactionType] = [
            .thumbsUp, .heart, .ok, .smile, .laugh, .sad, .surprised, .thinking
        ]
        XCTAssertEqual(allActive, expected)
        
        // 重複がないこと
        let uniqueCount = Set(allActive).count
        XCTAssertEqual(uniqueCount, 8)
    }
    
    // MARK: - Localization Tests
    
    func testReactionTitleLocalization() {
        for type in FriendsReactionType.allActiveTypes {
            XCTAssertFalse(type.title.isEmpty, "リアクション種別 \(type.key) のタイトル文言が空であってはなりません")
        }
        XCTAssertFalse(L10n.Reaction.laugh.isEmpty)
    }
}

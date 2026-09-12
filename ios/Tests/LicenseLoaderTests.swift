import XCTest
@testable import Friends

final class LicenseLoaderTests: XCTestCase {
    
    func testLicensesMarkdownExistsAndContainsPackages() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "licenses", withExtension: "md"),
            Bundle.main.url(forResource: "licenses", withExtension: "md", subdirectory: "legal"),
            Bundle.main.url(forResource: "licenses", withExtension: "md", subdirectory: "Resources/legal")
        ]
        let url = candidates.compactMap({ $0 }).first
        XCTAssertNotNil(url, "licenses.md should exist in bundle")
        
        if let url = url, let content = try? String(contentsOf: url, encoding: .utf8) {
            XCTAssertFalse(content.isEmpty, "licenses.md should not be empty")
            let lower = content.lowercased()
            XCTAssertTrue(lower.contains("swift-protobuf") || lower.contains("swiftprotobuf"), "Should contain SwiftProtobuf")
            XCTAssertTrue(lower.contains("base58swift") || lower.contains("base58"), "Should contain Base58Swift")
            XCTAssertTrue(lower.contains("swift-crypto") || lower.contains("crypto"), "Should contain Apple Swift Crypto")
            XCTAssertTrue(lower.contains("firebase-ios-sdk") || lower.contains("firebase"), "Should contain Firebase iOS SDK")
        }
    }
    
    func testTermsOfServiceMarkdownExistsAndContainsTrademarkClauses() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "terms_of_service", withExtension: "md"),
            Bundle.main.url(forResource: "terms_of_service", withExtension: "md", subdirectory: "legal"),
            Bundle.main.url(forResource: "terms_of_service", withExtension: "md", subdirectory: "Resources/legal")
        ]
        let url = candidates.compactMap({ $0 }).first
        XCTAssertNotNil(url, "terms_of_service.md should exist in bundle")
        
        if let url = url, let content = try? String(contentsOf: url, encoding: .utf8) {
            XCTAssertFalse(content.isEmpty, "terms_of_service.md should not be empty")
            XCTAssertTrue(content.contains("商標"), "Should contain trademark clauses")
            XCTAssertTrue(content.contains("悪用") || content.contains("不正"), "Should contain prohibition against misuse")
            XCTAssertTrue(content.contains("輸出"), "Should contain export control clauses")
        }
    }
    
    func testPrivacyPolicyMarkdownExistsAndContainsRetentionClause() {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "privacy_policy", withExtension: "md"),
            Bundle.main.url(forResource: "privacy_policy", withExtension: "md", subdirectory: "legal"),
            Bundle.main.url(forResource: "privacy_policy", withExtension: "md", subdirectory: "Resources/legal")
        ]
        let url = candidates.compactMap({ $0 }).first
        XCTAssertNotNil(url, "privacy_policy.md should exist in bundle")
        
        if let url = url, let content = try? String(contentsOf: url, encoding: .utf8) {
            XCTAssertFalse(content.isEmpty, "privacy_policy.md should not be empty")
            XCTAssertTrue(content.contains("送信済みメッセージの保持") || content.contains("かいぎ"), "Should contain message retention mentions")
            XCTAssertTrue(content.contains("退会したユーザー"), "Should contain '退会したユーザー' handling")
            XCTAssertTrue(content.contains("アカウントを削除") || content.contains("アカウント削除"), "Should contain account deletion")
        }
    }
    
    func testL10nAppInfoKeys() {
        XCTAssertFalse(L10n.AppInfo.title.isEmpty)
        XCTAssertFalse(L10n.AppInfo.version.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryption.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryptionDetail1.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryptionDetail2.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryptionDesc.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenses.isEmpty)
    }
}

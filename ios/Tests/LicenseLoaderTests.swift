import XCTest
@testable import Friends

final class LicenseLoaderTests: XCTestCase {
    
    func testLicenseLoaderLoadsLicenses() {
        let licenses = LicenseLoader.shared.loadLicenses()
        XCTAssertFalse(licenses.isEmpty, "licenses.json should contain licenses")
        XCTAssertGreaterThanOrEqual(licenses.count, 15, "Should have loaded at least 15 OSS packages")
    }
    
    func testLicenseItemIntegrity() {
        let licenses = LicenseLoader.shared.loadLicenses()
        for item in licenses {
            XCTAssertFalse(item.id.isEmpty, "Item id must not be empty")
            XCTAssertFalse(item.name.isEmpty, "Item name must not be empty")
            XCTAssertFalse(item.version.isEmpty, "Item version must not be empty")
            XCTAssertFalse(item.license.isEmpty, "Item license must not be empty")
        }
        
        // Check for specific core packages
        let ids = Set(licenses.map { $0.id.lowercased() })
        XCTAssertTrue(ids.contains("swift-protobuf"), "Should contain swift-protobuf")
        XCTAssertTrue(ids.contains("base58swift"), "Should contain base58swift")
        XCTAssertTrue(ids.contains("swift-crypto"), "Should contain swift-crypto")
    }
    
    func testL10nAppInfoKeys() {
        XCTAssertFalse(L10n.AppInfo.title.isEmpty)
        XCTAssertFalse(L10n.AppInfo.version.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryption.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryptionDetail.isEmpty)
        XCTAssertFalse(L10n.AppInfo.encryptionDesc.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenses.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenseListTitle.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenseSearchPlaceholder.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenseRepository.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenseViewSource.isEmpty)
        XCTAssertFalse(L10n.AppInfo.licenseEmpty.isEmpty)
    }
}

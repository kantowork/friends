import XCTest
@testable import Friends

final class ChatFontSizeTests: XCTestCase {
    
    // MARK: - Point Size Tests
    
    func testChatFontSizePointSizes() {
        XCTAssertEqual(ChatFontSize.xs.pointSize, 14.0, "xsは14.0ptである必要があります")
        XCTAssertEqual(ChatFontSize.s.pointSize, 15.5, "sは15.5ptである必要があります")
        XCTAssertEqual(ChatFontSize.m.pointSize, 17.0, "mは標準の17.0ptである必要があります")
        XCTAssertEqual(ChatFontSize.l.pointSize, 23.0, "lは旧xlと同等の23.0ptである必要があります")
        XCTAssertEqual(ChatFontSize.xl.pointSize, 28.0, "xlは拡大された28.0pt（Title 1基準）である必要があります")
    }
    
    // MARK: - Progression & Monotonicity Tests
    
    func testChatFontSizeMonotonicProgression() {
        let cases = ChatFontSize.allCases
        XCTAssertEqual(cases.count, 5)
        
        for i in 0..<(cases.count - 1) {
            let current = cases[i].pointSize
            let next = cases[i + 1].pointSize
            XCTAssertLessThan(current, next, "\(cases[i]) (\(current)) は \(cases[i + 1]) (\(next)) より小さい必要があります")
        }
    }
    
    // MARK: - Default Configuration Tests
    
    func testChatFontSizeDefault() {
        XCTAssertEqual(ChatFontSize.default, .m)
        XCTAssertEqual(ChatFontSize.defaultKey, "chat.font_size")
    }
    
    // MARK: - Localization Label Tests
    
    func testChatFontSizeLocalizedLabels() {
        for size in ChatFontSize.allCases {
            XCTAssertFalse(size.localizedLabel.isEmpty, "\(size) のラベルがローカライズされている必要があります")
        }
    }
}

import Foundation
import os

/// アプリ全体のログレベル定義
public enum AppLogLevel: Int, Comparable, CaseIterable {
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5
    
    public static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    public var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .none: return "NONE"
        }
    }
}

/// ログの分類カテゴリ
public enum LogCategory: String, CaseIterable {
    case auth = "Auth"
    case chat = "Chat"
    case crypto = "Crypto"
    case repo = "Repository"
    case ui = "UI"
    case sync = "Sync"
    case general = "General"
    
    public var emoji: String {
        switch self {
        case .auth: return "🔐"
        case .chat: return "💬"
        case .crypto: return "🛡️"
        case .repo: return "📡"
        case .ui: return "📱"
        case .sync: return "🔄"
        case .general: return "⚙️"
        }
    }
}

/// 統一ロガーシステム
public final class AppLogger {
    public static let shared = AppLogger()
    
    /// 現在のログレベル（初期値: .debug）
    public static var currentLevel: AppLogLevel = .debug
    
    private let subsystem = Bundle.main.bundleIdentifier ?? "work.kanto.friends"
    private var osLoggers: [LogCategory: os.Logger] = [:]
    
    private init() {
        for category in LogCategory.allCases {
            osLoggers[category] = os.Logger(subsystem: subsystem, category: category.rawValue)
        }
    }
    
    /// ログレベルの動的変更
    public static func setLevel(_ level: AppLogLevel) {
        currentLevel = level
        print("🎛️ [AppLogger] Log level changed to: \(level.label)")
    }
    
    // MARK: - Logging APIs
    
    public static func debug(
        _ message: @autoclosure () -> String,
        category: LogCategory = .chat,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message(), category: category, file: file, function: function, line: line)
    }
    
    public static func info(
        _ message: @autoclosure () -> String,
        category: LogCategory = .chat,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message(), category: category, file: file, function: function, line: line)
    }
    
    public static func warning(
        _ message: @autoclosure () -> String,
        category: LogCategory = .chat,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message(), category: category, file: file, function: function, line: line)
    }
    
    public static func error(
        _ message: @autoclosure () -> String,
        category: LogCategory = .chat,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .error, message: message(), category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Internal Output
    
    private static func log(
        level: AppLogLevel,
        message: String,
        category: LogCategory,
        file: String,
        function: String,
        line: Int
    ) {
        guard level >= currentLevel, currentLevel != .none else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = "\(category.emoji) [\(level.label)][\(category.rawValue)][\(fileName):\(line)] \(message)"
        
        // 1. 標準コンソール (Xcode / print) 出力
        print(formattedMessage)
        
        // 2. Apple Unified Logging System (OSLog) 出力
        if let logger = shared.osLoggers[category] {
            switch level {
            case .debug:
                logger.debug("\(formattedMessage, privacy: .public)")
            case .info:
                logger.info("\(formattedMessage, privacy: .public)")
            case .warning:
                logger.warning("\(formattedMessage, privacy: .public)")
            case .error:
                logger.error("\(formattedMessage, privacy: .public)")
            case .none:
                break
            }
        }
    }
}

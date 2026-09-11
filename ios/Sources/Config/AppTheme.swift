import SwiftUI

// MARK: - App Theme

/// アプリ全体のデザイントークン。
/// アクセントカラーは AccentColor.colorset に定義され、
/// iOS の AccentColor 機構（戻るボタン・ツールバー等）にも自動適用される。
public enum AppTheme {
    /// アプリブランドカラー（インディゴブルー）。
    /// - Light: #4E6AF0
    /// - Dark:  #7B95FF
    public static let accent = Color("AccentColor")
}

// MARK: - Color Extension

public extension Color {
    /// アプリのブランドアクセントカラー。
    /// インタラクティブ要素・状態表示（未読バッジ、CTAボタン、選択インジケーター等）に使用する。
    /// 破壊的アクションには `.red`、警告には `.orange`、ロールバッジには `.indigo` / `.orange` を使用すること。
    static let appAccent = AppTheme.accent
}

# 10-07. ロガーシステム設計仕様書 (Logging System)

本ドキュメントは、**Friends** プロジェクトにおける iOS クライアントの統一ロガーシステム（`AppLogger`）の設計およびログレベル動的制御仕様を定めたものです。

---

## 1. 概要と設計方針

- **Apple 統一ログ基盤（OSLog）との統合**:
  - `os.Logger` を内部で利用し、Xcode コンソール、Mac のコンソールアプリ、および `simctl spawn log stream` に標準出力します。
- **動的なログレベル切り替え**:
  - 開発時・デバッグ時・本番運用時で動的にログレベル（`.debug`, `.info`, `.warning`, `.error`, `.none`）を変更可能にします。
- **カテゴリ別分類**:
  - 認証（`auth`）、チャット（`chat`）、暗号・鍵管理（`crypto`）、データアクセス（`repo`）、UI・画面（`ui`）等、機能単位でサブシステムログを分離します。

---

## 2. ログレベル定義

| レベル | 識別子 | 用途 |
|:---|:---|:---|
| **DEBUG** | `AppLogLevel.debug` (1) | 詳細な処理ステップ、復号・暗号化データ、ローカル変数トレース |
| **INFO** | `AppLogLevel.info` (2) | 画面遷移、ユーザー認証状態変化、接続確立、主要ライフサイクルイベント |
| **WARNING** | `AppLogLevel.warning` (3) | キャッシュ不一致によるフォールバック発動、再試行、非致命的エラー |
| **ERROR** | `AppLogLevel.error` (4) | API通信失敗、暗号化/復号失敗、認可エラー、致命的例外 |
| **NONE** | `AppLogLevel.none` (5) | すべてのログ出力を停止 |

---

## 3. インターフェース仕様

```swift
public final class AppLogger {
    public static let shared = AppLogger()
    
    /// 現在のログレベル (動的に変更可能)
    public var currentLevel: AppLogLevel
    
    public static func debug(_ message: @autoclosure () -> String, category: LogCategory = .chat, file: String = #file, function: String = #function, line: Int = #line)
    public static func info(_ message: @autoclosure () -> String, category: LogCategory = .chat, file: String = #file, function: String = #function, line: Int = #line)
    public static func warning(_ message: @autoclosure () -> String, category: LogCategory = .chat, file: String = #file, function: String = #function, line: Int = #line)
    public static func error(_ message: @autoclosure () -> String, category: LogCategory = .chat, file: String = #file, function: String = #function, line: Int = #line)
    
    /// ログレベルの変更
    public static func setLevel(_ level: AppLogLevel)
}
```

---

## 4. ログ出力呼び出しの運用とルール更新方針

- **現状のコードベース**:
  - 新たなログルール策定に伴い、既存のすべてのソースコードから `print(...)` および `AppLogger.*(...)` の出力呼び出し記述は完全に取り除かれています。
  - `AppLogger` クラスおよび `os.Logger` 基盤自体は機構として維持されており、新ルールの制定後に規定に基づいた安全かつ体系的なログ出力が順次追加されます。
- **今後のルール**:
  - 直接的な `print(...)` の使用は原則禁止。
  - 必要最小限の運用・監査ログのみを規定カテゴリ（`category`）とログレベル（`level`）に従って配置すること。


# 09-02: 国際化・多言語対応仕様書 (Internationalization & Localization Architecture)

本ドキュメントは、Friends プロジェクト（iOS / Web / Android）における多言語対応（i18n / l10n）の設計方針、リソース構造、キー命名規則、および実装ガイドラインを定義します。

---

## 1. 基本設計方針

1. **完全外部化 (No Hardcoded Strings)**:
   - UI 表示文字列、エラーメッセージ、プレースホルダー、アクセシビリティラベルなど、すべてのユーザー可視テキストはハードコードせず、ローカライズリソースから取得します。
2. **キー命名規則 (English Dot Notation)**:
   - ローカライズキーは日本語リテラルではなく、階層構造を表す **英語のドット記法 (`domain.category.item`)** で統一します。
3. **型安全なアクセス**:
   - 文字列キーのタイポや未定義キーによるクラッシュ・表示崩れを防ぐため、Swift / TypeScript 側で型安全なヘルパー構造 (`L10n`) を提供します。
4. **対応言語 (Phase 1)**:
   - **日本語 (ja)**: プライマリ言語 / デフォルト
   - **英語 (en)**: セカンダリ言語

---

## 2. キー命名構造

```
<ドメイン>.<機能/画面>.<要素種別/識別子>
```

### 主要ドメイン

| ドメイン | 対象領域 | 例 |
|:---|:---|:---|
| `common` | 全画面共通ボタン・汎用ラベル | `common.ok`, `common.cancel`, `common.close`, `common.copy` |
| `auth` | ログイン・認証・テナント選択 | `auth.login.title`, `auth.tenant.select_title` |
| `chat` | チャット一覧・詳細・メッセージング | `chat.list.title`, `chat.detail.send_placeholder` |
| `friend` | 友達一覧・友達追加・QR・合言葉 | `friend.list.title`, `friend.add.title`, `friend.passcode.label` |
| `group` | グループ一覧・グループ作成・管理 | `group.list.title`, `group.create.title` |
| `settings` | 設定・プロフィール・復元 | `settings.title`, `settings.profile.edit` |
| `error` | エラーメッセージ | `error.friend.invalid_format`, `error.tenant_not_found` |

---

## 3. リソースファイル構成

### iOS (SwiftUI)

- **`ios/Sources/Resources/ja.lproj/Localizable.strings`**: 日本語リソース
- **`ios/Sources/Resources/en.lproj/Localizable.strings`**: 英語リソース
- **`ios/Sources/Models/Localization/L10n.swift`**: 型安全なローカライゼーションヘルパー

```swift
// 使用例
Text(L10n.Friend.addTitle)
Text(L10n.Common.ok)
let errorMsg = L10n.Error.Friend.invalidFormat
```

---

## 4. 全画面レビュー・管理チェックリスト

- [x] **A01 スプラッシュ**: 初期化テキスト・ローディングメッセージ
- [x] **A02 ログイン / A05m メール認証**: タイトル、ログインボタン、プレースホルダー、ゲスト案内
- [x] **A03m テナント選択**: QR/URL/JSONタブ名、検証中/成功/失敗メッセージ
- [x] **A04/E04 復活の呪文**: 復元案内、単語入力、警告文
- [x] **B01/C01 チャット一覧**: タブ名、空状態メッセージ、未読バッジ
- [x] **C02 チャット詳細**: メッセージ送信欄、暗号化表示
- [x] **C03 友達追加 (QR / テキスト / 3桁合言葉)**: カメラスキャン案内、自QR案内、3桁合言葉、残り時間、テキスト連携、エラー表示
- [x] **C04/FriendList 友達一覧**: 友達追加ボタン、登録済み一覧
- [x] **E01 設定**: プロフィール、テナント情報、ログアウト

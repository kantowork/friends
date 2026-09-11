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
| `common` | 全画面共通ボタン・汎用ラベル | `common.ok`, `common.cancel`, `common.close`, `common.save`, `common.delete` |
| `auth` | ログイン・認証・テナント選択 | `auth.login.title`, `auth.recovery.restore_button` |
| `chat` | チャット一覧・詳細・メッセージング | `chat.list.title`, `chat.detail.input_placeholder` |
| `friend` | ともだち一覧・ともだち追加・2次元コード・合言葉 | `friend.list.title`, `friend.add.title`, `friend.add.passcode_title` |
| `group` | かいぎ一覧・かいぎ作成・管理 | `group.list.title`, `group.create.title` |
| `settings` | 設定・プロフィール・復元 | `settings.title`, `settings.profile.edit_title` |
| `error` | エラーメッセージ | `error.friend.invalid_format`, `error.tenant.not_found` |

---

## 3. 用語選定・表現規約 (Terminology Standard)

| 概念 | 日本語 (ja) | 英語 (en) | 備考 |
|:---|:---|:---|:---|
| **友達** | **ともだち** | **Friend(s)** | タブ、ナビゲーションバー、本文、ボタンすべて「ともだち」で統一 |
| **グループチャット** | **かいぎ** | **Group(s)** | タブ、ナビゲーションバー、本文、トーストすべて「かいぎ」で統一 |
| **マトリクス型2次元コード** | **2次元コード** | **QR code** | 日本語は半角数字「2次元コード」、英語は「QR code」で統一 |
| **一意識別名** | **ユーザー名** | **Username** | アカウント名表記を排除し「ユーザー名」に一本化 |
| **所属単位** | **テナント** | **Tenant** | 組織表記を「テナント」に統一 |
| **通常アクションボタン** | **名詞＋格助詞＋動詞連用形** | - | 例:「ともだちを追加」「かいぎを作成」 |
| **ダイアログアクション** | **名詞・体言止め** | - | iOS標準準拠:「作成」「再作成」「削除」 |
| **退出・離脱** | **退室する / 退室させる** | **Leave Group / Remove from Group** | 自分:「退室する」 / 他者:「退室させる」 |
| **完了文末** | **「！」排除** | - | 落ち着いたトーン（「〜しました」）で統一 |
| **復旧フレーズ** | **ふっかつのじゅもん** | **Recovery Phrase** | 「じゅもん」表記に統一。重複キーは `settings.recovery` に一本化 |
| **共通操作ボタン** | **共通化** | - | `common.save`, `common.close`, `common.cancel` を集約再利用 |

---

## 4. リソースファイル構成

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

## 5. 全画面レビュー・管理チェックリスト

- [x] **A01 スプラッシュ**: 初期化テキスト・ローディングメッセージ
- [x] **A02 ログイン / A05m メール認証**: タイトル、ログインボタン、プレースホルダー、ゲスト案内
- [x] **A03m テナント選択**: 2次元コード/URL/テキストタブ名、検証中/成功/失敗メッセージ
- [x] **A04/B05 ふっかつのじゅもん**: 復元案内、単語入力、警告文
- [x] **B01 ホーム**: クイックアクション「ともだちを追加」、お知らせ
- [x] **C01 ともだち一覧**: タブ名「ともだち」、空状態メッセージ、未読バッジ
- [x] **C02 チャット詳細**: メッセージ送信欄、暗号化表示
- [x] **C03 ともだち追加 (2次元コード / テキスト / 3桁合言葉)**: カメラスキャン案内、自2次元コード案内、3桁合言葉、残り時間、テキスト連携、エラー表示
- [x] **D01/D03/D04 かいぎ（グループチャット）・管理**:
  - かいぎ一覧、かいぎ作成（タイトル、ともだち選択）
  - かいぎ情報（メンバー一覧、👑 オーナーバッジ、🛡️ 管理者バッジ、かいぎ名変更）
  - ロール操作（立候補型オーナー昇格、管理者任命、退室・退室させる操作）
  - かいぎ削除の確認ダイアログ（`group.delete.confirm_*`）
- [x] **B02 設定**: プロフィール、テナント情報、ログアウト、アカウント削除

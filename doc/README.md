# ドキュメント一覧

このフォルダには、Friends プロジェクトの設計・仕様に関するドキュメントを格納します。
複数ファイルを持つ分類はディレクトリ（`XX-xxxx/`）として整理し、ファイル名にも `XX-YY-xxxx.md` の形式を採用しています。

---

## 1. 要件分析

- [`01-project-overview.md`](01-project-overview.md) - プロジェクトの目的、ターゲット、ロードマップ
- [`02-requirements-and-use-cases.md`](02-requirements-and-use-cases.md) - 機能要件とICONIXのユースケース一覧

## 2. 概念分析

- [`03-usecases.md`](03-usecases.md) - ICONIXのユースケース一覧
- [`04-domain-model.md`](04-domain-model.md) - ドメインモデルと主要エンティティ

## 3. 基本設計

- [`05-architecture-and-monorepo.md`](05-architecture-and-monorepo.md) - アーキテクチャとモノレポ構成
- [`05-robustness-analysis.md`](05-robustness-analysis.md) - ロバストネス分析
- [`06-security-and-nonfunctional-requirements.md`](06-security-and-nonfunctional-requirements.md) - 非機能要件とセキュリティ要件

## 4. 詳細ユースケース

- [`07-detailed-usecases/`](07-detailed-usecases/README.md) - 詳細ユースケース一覧＆ユースケース対応表
  - [`07-01-tenant-selection.md`](07-detailed-usecases/07-01-tenant-selection.md) - テナント選択フロー（QRコードスキャン）
  - [`07-02-user-registration-login.md`](07-detailed-usecases/07-02-user-registration-login.md) - ユーザー登録・ログイン
  - [`07-03-message-encryption.md`](07-detailed-usecases/07-03-message-encryption.md) - テキストメッセージ送信・暗号化仕様（E2EE）
  - [`07-04-device-recovery.md`](07-detailed-usecases/07-04-device-recovery.md) - 端末移行および「ふっかつのじゅもん」による復旧仕様
  - [`07-05-metadata-audit.md`](07-detailed-usecases/07-05-metadata-audit.md) - メタデータ監査（テナント管理者）
  - [`07-06-friend-addition.md`](07-detailed-usecases/07-06-friend-addition.md) - 友達追加（QRコード / テキスト / 3桁合言葉）
  - [`07-07-push-notification.md`](07-detailed-usecases/07-07-push-notification.md) - メッセージ通知仕様（アプリ内トースト & プッシュ通知）
  - [`07-08-external-group-notification.md`](07-detailed-usecases/07-08-external-group-notification.md) - 外部REST API経由のグループ通知送信
  - [`07-09-user-profile-update.md`](07-detailed-usecases/07-09-user-profile-update.md) - プロフィール表示名更新および友達間同期仕様書
  - [`07-10-read-receipt-management.md`](07-detailed-usecases/07-10-read-receipt-management.md) - メッセージ既読管理（Read Receipt Management）仕様書
  - [`07-11-message-reactions.md`](07-detailed-usecases/07-11-message-reactions.md) - メッセージリアクション（Message Reactions）仕様書

## 5. 画面設計

- [`08-screen-design.md`](08-screen-design.md) - 画面設計一覧・UIレイアウト・画面遷移図

## 6. 共通開発標準・規約

- [`09-guidelines/`](09-guidelines/README.md) - 共通開発標準・規約インデックス
  - [`09-01-id-naming-conventions.md`](09-guidelines/09-01-id-naming-conventions.md) - ID プレフィックス命名規約仕様書
  - [`09-02-internationalization.md`](09-guidelines/09-02-internationalization.md) - 国際化・多言語対応仕様書 (i18n & Localization)

## 7. 基盤詳細設計

- [`10-detailed-design/`](10-detailed-design/README.md) - 基盤詳細設計インデックス
  - [`10-01-tenant-data-encryption.md`](10-detailed-design/10-01-tenant-data-encryption.md) - テナント共通鍵（MK_T）によるテナント内データ暗号化仕様書
  - [`10-02-firestore-direct-access-rules.md`](10-detailed-design/10-02-firestore-direct-access-rules.md) - Firestore 直接格納・アクセス制御ルール
  - [`10-03-data-access-patterns.md`](10-detailed-design/10-03-data-access-patterns.md) - Firebase データアクセスパターン一元管理仕様書 (Data Access Patterns & API)
  - [`10-04-background-notification-setup.md`](10-detailed-design/10-04-background-notification-setup.md) - バックグラウンドプッシュ通知 導入準備・設計仕様書 (Background Push Notification Setup & Design)
  - [`10-05-api-strategy-analysis.md`](10-detailed-design/10-05-api-strategy-analysis.md) - API通信戦略分析（gRPC vs Connect vs REST/Firestore SDK 分析）

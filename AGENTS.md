# AGENTS.md: 開発・AI協調 実装規約 (Rules & Guidelines)

本ドキュメントは、**Friends** プロジェクトにおけるすべての AI エージェントおよび開発者が **例外なく遵守しなければならない最上位の開発ルール（絶対遵守事項）** を定めたものです。
背景仕様や個別機能の詳細設計については、[doc/ 配下の各ドキュメント](#設計ドキュメント参照インデックス-doc) を必要に応じて参照してください。

---

## 🚨 絶対遵守ルール (Must-Follow Rules)

### 1. ドキュメントファースト & 整合性維持義務 (Documentation Alignment)
- **ドキュメントファースト**: 新機能の追加、仕様変更、データモデルの拡張を行う際は、**実装前に必ず関連する設計書 (`doc/*.md`, `doc/*/*.md`) を改版・新規作成** すること。
- **完全同期の維持**: コードと設計ドキュメントの整合性を不変に維持しなければならない。実装完了時にドキュメントとの乖離があってはならない。

### 2. 型安全性 & アーキテクチャ原則 (Type Safety & Swift 6)
- **厳格な型定義**: Swift / TypeScript において `Any` や曖昧な型を避け、Protobuf モデルまたは厳格な構造体・列挙型を使用すること。
- **Swift 6 並行処理対応**: `@MainActor` 隔離やバックグラウンドタスクの境界を正しく扱い、Actor 隔離違反エラー（`Main actor-isolated property cannot be accessed...`）を発生させないこと。
- **UIとロジック・データアクセスの3層分離**:
  - **View**: UI 表示およびユーザーイベント処理に専念（`Views/`）。
  - **Service**: 画面状態（`@Published`）、E2EE暗号・復号、ビジネスロジックを集約（`Services/`）。
  - **Repository**: Firestore / Cloud Storage 等のすべてのデータアクセス（CRUD・`onSnapshot` 購読）を `Repositories/` ディレクトリ配下に集約し、Service や View から直接 Firebase SDK を呼び出さないこと。
- 詳細仕様: [doc/10-detailed-design/10-03-data-access-patterns.md](doc/10-detailed-design/10-03-data-access-patterns.md)

### 3. Protocol Buffers & コード自動生成ルール (Protobuf)
- **モデルの単一情報源**: データモデルの定義は `shared/model/*.proto` (Proto3) を真実の唯一のソース (SSOT) とする。
- **Apple 公式 SwiftProtobuf**: モデル自動生成には Apple 公式 `protoc-gen-swift` を使用する。
- **構成管理除外**: 自動生成コード（`ios/Sources/Models/Generated/*.pb.swift` 等）は `.gitignore` に指定し、Git 管理対象外とすること。

### 4. 国際化・多言語対応の徹底 (Mandatory i18n / L10n)
- **ハードコードの禁止**: UI 表示文字列、プレースホルダー、システムアラート、エラーメッセージ等に日本語リテラルを直接記述することを**固く禁止**する。
- **英語ドット記法キー**: すべての文言は `L10n` ラッパーおよび英語ドット記法キー（例: `auth.login.title`, `friend.add.title`, `error.friend.invalid_format`）で定義し、`Localizable.strings` (ja / en) に翻訳を紐付けること。
- 詳細仕様: [doc/09-guidelines/09-02-internationalization.md](doc/09-guidelines/09-02-internationalization.md)

### 5. 命名規約 & ID プレフィックス体系 (Naming Conventions)
- **英語キーの統一**: API フィールド、DB ドキュメントフィールド、JSON シードデータのキーはすべて英語（camelCase）で定義すること。
- **不変 ID プレフィックス**: エンティティ ID には規定のプレフィックスを必ず付与すること（ユーザー: `u_...`, テナント: `t_...`, メッセージ: `m_...`, 会話: `dm_...`/`gm_...`）。
- 詳細仕様: [doc/09-guidelines/09-01-id-naming-conventions.md](doc/09-guidelines/09-01-id-naming-conventions.md)

### 6. セキュリティ & 暗号鍵管理原則 (Security & Cryptography)
- **鍵生成と保管**: 初回ログイン/ユーザー作成時に Curve25519 (X25519) 鍵ペアを生成。秘密鍵 ($SK_u$) は端末の **iOS Keychain** (`kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrSynchronizable = true` による E2EE iCloud キーチェーン同期) に厳重保管し、平文で外部送信してはならない。
- **公開鍵の配置**: 公開鍵 ($PK_u$) のみ Base64 形式で Firestore (`/tenants/{tenantId}/users/{userId}` および `/users/{uid}`) に公開する。
- 詳細仕様: [doc/07-detailed-usecases/07-02-user-registration-login.md](doc/07-detailed-usecases/07-02-user-registration-login.md), [doc/07-detailed-usecases/07-03-message-encryption.md](doc/07-detailed-usecases/07-03-message-encryption.md)

### 7. 自動テスト & ビルド検証義務 (Automated Testing)
- **テストの維持と拡充**: 鍵管理、パスコード生成・検証、招待エンコード/デコード、ローカライズ等の重要ロジックに対して単体テストを実装すること。
- **検証の完了**: ファイル追加・変更時は `xcodegen generate` を経由してプロジェクトを同期し、`xcodebuild test` をパスさせること。

### 8. シミュレータービルド & 配信規約 (Simulator Deployment)
- **配信スクリプトの使用**: iOS アプリの修正・機能追加後および動作確認時は、必ずユーザーに配信をするかを確認すること。必要に応じて [`scripts/deploy_simulators.sh`](scripts/deploy_simulators.sh) を使用して、稼働中のシミュレーター（iPhone 17e / iPhone SE3 等）へのビルド・一括配信・再起動を実施すること。

### 9. 自律的自己進化 (Self-Evolution)
- 開発者からの指摘やプロジェクトの進展に応じて、本規約および設計ドキュメントを自律的に最新かつ最適に保つこと。

### 10. レガシー・deprecated・レトロフィットの完全排除原則 (No Legacy / Deprecated / Retrofitting)
- **過去設計の完全排除**: 本プロジェクトにおいては、古い設計のための `deprecated` 指定やレトロフィット実装（後方互換性維持のためのフォールバック処理、旧フィールドの残置等）は**一切不要**とする。
- **クリーンな即時刷新**: 仕様変更・設計刷新を行う際は、不要となった旧フィールド・旧ロジック・旧API・旧コメントを妥協なく完全に削除し、常に最新かつ最小限のクリーンな設計・実装を維持すること。

---

## 📚 設計ドキュメント参照インデックス (doc/)

作業内容に応じて、以下の専門ドキュメントを参照してください：

| 分類 | ドキュメント | 参照すべき作業・内容 |
|:---|:---|:---|
| **全体概要** | [doc/01-project-overview.md](./doc/01-project-overview.md) | プロジェクト目的、ロードマップ、技術スタック全景 |
| **要件定義** | [doc/02-requirements-and-use-cases.md](./doc/02-requirements-and-use-cases.md) | コア機能要件、ユースケース一覧 |
| **モデル設計** | [doc/04-domain-model.md](./doc/04-domain-model.md) | ドメインエンティティ、集約、状態定義 |
| **非機能要件** | [doc/06-security-and-nonfunctional-requirements.md](./doc/06-security-and-nonfunctional-requirements.md) | セキュリティ、可用性、性能、ログ要件 |
| **詳細ユースケース** | [doc/07-detailed-usecases/README.md](./doc/07-detailed-usecases/README.md) | 詳細ユースケース一覧・対応インデックス |
| **認証・鍵生成** | [doc/07-detailed-usecases/07-02-user-registration-login.md](./doc/07-detailed-usecases/07-02-user-registration-login.md) | ログイン/登録、Curve25519 鍵生成と Keychain/DB 格納 |
| **暗号化通信** | [doc/07-detailed-usecases/07-03-message-encryption.md](./doc/07-detailed-usecases/07-03-message-encryption.md) | E2EE メッセージ暗号化、セッション鍵導出 |
| **端末復旧** | [doc/07-detailed-usecases/07-04-device-recovery.md](./doc/07-detailed-usecases/07-04-device-recovery.md) | 復活の呪文（Mnemonic Phrase）によるアカウント・鍵復元 |
| **友達追加** | [doc/07-detailed-usecases/07-06-friend-addition.md](./doc/07-detailed-usecases/07-06-friend-addition.md) | 二次元コード/テキスト連携、30秒更新3桁合言葉 TOTP 仕様 |
| **通知・プッシュ** | [doc/07-detailed-usecases/07-07-push-notification.md](./doc/07-detailed-usecases/07-07-push-notification.md)<br>[doc/10-detailed-design/10-04-background-notification-setup.md](./doc/10-detailed-design/10-04-background-notification-setup.md) | アプリ内トースト通知、FCM/APNs バックグラウンドプッシュ通知導入準備仕様 |
| **プロフィール更新** | [doc/07-detailed-usecases/07-09-user-profile-update.md](./doc/07-detailed-usecases/07-09-user-profile-update.md) | 表示名変更の暗号化保存プロトコル・低コストハイブリッド友達同期 |
| **既読管理** | [doc/07-detailed-usecases/07-10-read-receipt-management.md](./doc/07-detailed-usecases/07-10-read-receipt-management.md) | 水位線カーソル方式によるE2EEチャット既読管理・リアルタイム同期仕様 |
| **リアクション** | [doc/07-detailed-usecases/07-11-message-reactions.md](./doc/07-detailed-usecases/07-11-message-reactions.md) | メッセージリアクション（8種、クイックアクション7種）、低通信量集計、長押し詳細表示仕様 |
| **グループチャット** | [doc/07-detailed-usecases/07-12-group-chat.md](./doc/07-detailed-usecases/07-12-group-chat.md) | グループチャット（かいぎ）一覧・作成・詳細・KeyBucket仕様 |
| **グループ管理・削除** | [doc/07-detailed-usecases/07-13-group-role-and-deletion.md](./doc/07-detailed-usecases/07-13-group-role-and-deletion.md) | メンバー属性role、立候補型オーナー昇格、退室管理、グループ削除仕様 |
| **アカウント削除・退会** | [doc/07-detailed-usecases/07-14-account-deletion.md](./doc/07-detailed-usecases/07-14-account-deletion.md) | アカウント削除・論理削除・暗号化データ消去仕様 |
| **ブロック・通報** | [doc/07-detailed-usecases/07-15-block-and-report.md](./doc/07-detailed-usecases/07-15-block-and-report.md) | ユーザーブロック・解除・通報処理仕様 |
| **写真・ファイル添付** | [doc/07-detailed-usecases/07-16-chat-file-attachment.md](./doc/07-detailed-usecases/07-16-chat-file-attachment.md) | 写真・ファイル添付（カメラ/写真選択）、E2EE封筒暗号化、Cloudflare R2連携・キャッシュ仕様 |
| **画面設計** | [doc/08-screen-design.md](./doc/08-screen-design.md) | 画面一覧、UIレイアウト、画面遷移 |
| **開発標準・規約** | [doc/09-guidelines/README.md](./doc/09-guidelines/README.md) | 命名規約・多言語化規約インデックス |
| **命名規約** | [doc/09-guidelines/09-01-id-naming-conventions.md](./doc/09-guidelines/09-01-id-naming-conventions.md) | ID プレフィックスおよびキー命名ルール |
| **多言語化** | [doc/09-guidelines/09-02-internationalization.md](./doc/09-guidelines/09-02-internationalization.md) | i18n / L10n キー設計標準、言語リソース仕様 |
| **基盤詳細設計** | [doc/10-detailed-design/README.md](./doc/10-detailed-design/README.md) | 基盤・セキュリティ・データアクセスの専門詳細設計インデックス |
| **テナント暗号** | [doc/10-detailed-design/10-01-tenant-data-encryption.md](./doc/10-detailed-design/10-01-tenant-data-encryption.md) | テナントマスターキー ($MK_T$) による組織データ暗号化方針・仕様 |
| **DBアクセス** | [doc/10-detailed-design/10-02-firestore-direct-access-rules.md](./doc/10-detailed-design/10-02-firestore-direct-access-rules.md) | Firestore パス構造、セキュリティルール |
| **アクセスパターン** | [doc/10-detailed-design/10-03-data-access-patterns.md](./doc/10-detailed-design/10-03-data-access-patterns.md) | テナント・ユーザー・友達・アバター・チャット・メッセージ等のFirebase/R2アクセスパターン一元管理仕様 |
| **API戦略** | [doc/10-detailed-design/10-05-api-strategy-analysis.md](./doc/10-detailed-design/10-05-api-strategy-analysis.md) | クライアント直接Firestore vs サーバーAPIの通信戦略分析 |
| **R2ストレージ準備** | [doc/10-detailed-design/10-06-r2-storage-setup.md](./doc/10-detailed-design/10-06-r2-storage-setup.md) | Cloudflare R2 バケット作成・カスタムドメイン・CORS・APIトークン発行・事前準備手順書 |
| **ロガー基盤** | [doc/10-detailed-design/10-07-logging-system.md](./doc/10-detailed-design/10-07-logging-system.md) | OSLog連携、動的ログレベル制御（DEBUG/INFO/WARN/ERROR）仕様 |
| **Workers基盤準備** | [doc/10-detailed-design/10-08-cloudflare-workers-setup.md](./doc/10-detailed-design/10-08-cloudflare-workers-setup.md) | Cloudflare Workers サーバー基盤・サービスアカウント・事前準備・運用手順書 |

---
*This document is optimized for AI context injection.*


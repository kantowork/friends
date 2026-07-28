# プロジェクト概要: Friends

## 1. 目的 & ビジョン

**Friends** は、強固なプライバシー保護と使いやすさを両立した次世代コミュニケーションアプリです。
E2EE（End-to-End Encryption）による秘匿リアルタイムメッセージングを中核とし、匿名ログイン（ゲスト開始）から永続化、組織（テナント）別の隔離運用、対面での安全な友達交換までを一貫してサポートします。

## 2. 展開プラットフォーム & ロードマップ

- **Phase 1 (現行)**: iOS (iPhone ネイティブ / SwiftUI + Swift 6 Ready)
- **Phase 2**: Web (クロスプラットフォーム展開・管理コンソール)
- **Phase 3**: Android

## 3. 主要ターゲット

- 高いプライバシー保護を求める個人・チーム
- 匿名アカウントと永続アカウントを柔軟に使い分ける利用者
- 組織・コミュニティごとに安全な通信基盤を必要とするテナント利用者

## 4. 技術スタック & インフラストラクチャ

- **リポジトリ構成**: モノレポ (Monorepo)
- **バックエンド / クラウド**: Google Cloud & Firebase
  - **認証 (Auth)**: Firebase Auth (匿名認証, メール/パスワード, ソーシャルログイン)
  - **データベース (Database)**: Cloud Firestore (リアルタイムリスナー & セキュリティルールによる保護)
  - **通知 (Notification)**: Firebase Cloud Messaging (FCM) / Apple Push Notification service (APNs Time-Sensitive)
  - **ストレージ (Storage)**: Cloudflare R2 / Cloud Storage
- **暗号化エンジン**: Apple CryptoKit (Curve25519 / AES-256-GCM / HKDF) + iOS Keychain
- **モデル定義**: Protocol Buffers (Proto3) + `swift-protobuf`

## 5. コーディング & 開発規約

- **コーディング規約**: インデントはスペース 2 を標準とする。
- **設定管理**: リポジトリルートに `.editorconfig` を配置し、統一されたフォーマットを維持する。

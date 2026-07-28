# アーキテクチャとモノレポ構成

## 1. ルートディレクトリ構成

- `infra/` - インフラコード
- `server/` - サーバーコード
- `shared/` - 共通コード
- `ios/` - iOS ネイティブアプリコード
- `doc/` - 設計・ドキュメント

## 2. モノレポ設計方針

- 共通ドメインを `shared/` に置き、`server/` と `ios/` で再利用
- `infra/` は Cloud Infrastructure as Code、ネットワーク・認証・監視を定義
- `server/` は最小限のサーバーAPI / Cloud Functions を実装し、主に復活の呪文検証、監査ログ集計、通知配信などの例外的なサーバー処理を担います。多くのデータフローは Firestore 直接アクセスと Security Rules で完結します。
- `ios/` は UI、ローカル暗号化、機密データの端末内保持（tenantId, session tokens, private keys, recovery phrase）、通知受信、位置情報管理、復活の呪文による端末移行を実装

## 3. 推奨レイヤー構成

### プレゼンテーション層

- iOS: View / ViewController / SwiftUI
- サーバー: 必要最小限の API 層、サーバーレス関数 / 監査処理

### アプリケーション層

- Use Case / Interactors
- ユースケース実行、トランザクション制御

### ドメイン層

- エンティティ、値オブジェクト、ドメインサービス
- 主要ビジネスルールを `shared/` で定義

### インフラ層

- 永続化、ネットワーク、通知、クラウドサービス連携
- `infra/` と `server/` の実装を分離

## 4. 技術スタック想定

- `infra/`: Terraform / Pulumi / Cloud SDK
- `server/`: Node.js / TypeScript もしくは Go、Firestore、gRPC/WebSocket
- `shared/`: TypeScript または Swift for shared domain definitions
- `ios/`: Swift、SwiftUI、Firebase SDK

## 5. iOS 初期重点

- テナント利用前の設定フロー
- ログイン / 認証画面
- 端末移行用の復活の呪文生成・復元
- チャット UI
- QR コードスキャンによる友達追加
- プッシュ通知受信
- 位置共有 UI

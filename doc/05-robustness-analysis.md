# ロバストネス分析

ユースケースごとにロバストネス分析を行い、シーケンスの振る舞いを検証します。

## 1. テナント設定・構成

- Actor: サービス管理者, テナント管理者
- Boundary: Tenant Setup Console, Tenant Config API
- Entity: Tenant
- Control: TenantController

### 主なシナリオ

1. テナントを事前に登録・構成する
2. テナントマスターキーを発行・管理する
3. テナントマスターキーのローテーションポリシーを設定する
4. テナント作成後にテナント情報を含む QR コードを生成・出力する（管理者がダウンロード／配布可能）
5. テナント設定をユーザー利用前に確定する
6. テナント管理者のアクセス権限を設定する

### 例外パス

- テナント設定不備
- キー管理の不一致
- 設定権限不足

## 2. テナント選択

- Actor: User
- Boundary: Tenant Selection Screen, QR Scanner, Firestore
- Entity: Tenant
- Control: TenantSelectionController
- Note: Tenant Selection UI also supports manual JSON input as an alternative to QR scanning. テナント検証は可能な限り Firestore 直接読み取りで完結し、専用サーバー機能は必要最小限にとどめます。

### 主なシナリオ

1. アプリ起動時、デフォルトテナント確認
2. デフォルトテナント指定がない場合、テナント選択画面を表示
3. ユーザーがテナント用 QR コードをスキャン、または手動でテナント設定(JSON)を入力
4. スキャン結果または JSON から `tenantId` を解決
5. アプリが Firestore `/tenants/{tenantId}` を直接読み取り、テナント有効性を確認
6. テナント情報をアプリに保存して次ステップへ

### 例外パス

- QR コード無効
- テナント不存在
- ネットワークエラー
- デフォルトテナント指定時は選択画面をスキップ

## 3. ユーザー登録・ログイン

- Actor: User
- Boundary: Login Screen, Firebase Auth SDK
- Entity: User, Session
- Control: AuthController

### 主なシナリオ

1. ユーザーが認証方法を選択
2. 認証情報を入力して送信
3. クライアントが Firebase Auth SDK で認証を実行
4. Firebase Auth がトークンを返却
5. アプリがセッションを開始
6. 必要なユーザーデータは Firestore 直接書き込みで保存

### 例外パス

- ネットワークエラー
- 認証失敗
- Firebase サービスの障害

## 4. テナント管理者のメタデータ監査

- Actor: テナント管理者
- Boundary: Audit Console, Audit API
- Entity: Message, Conversation, Tenant
- Control: AuditController

### 主なシナリオ

1. テナント管理者が監査期間を指定する
2. サーバーは通信メタデータ（送信者、受信者、日時）を収集して返す
3. テナント管理者は本文なしでやりとりの履歴を確認する

### 例外パス

- 監査権限不足
- メタデータ収集エラー
- 監査範囲超過

## 5. 端末移行 / 復活の呪文

- Actor: User
- Boundary: Recovery UI, Recovery API
- Entity: User, RecoveryPhrase
- Control: RecoveryController

### 主なシナリオ

1. ユーザーが復活の呪文を生成・保存する
2. 端末を移行した際、新しいデバイスで同じ復活の呪文を入力する
3. システムは同じユーザーIDとして認証・復元し、復旧可能なローカル鍵を再生成してテナント／アカウント情報を再構成する

### 例外パス

- 復活の呪文無効
- 復旧データ損失
- 旧端末の鍵が利用不可

## 6. テキストメッセージ送信

- Actor: User
- Boundary: Chat Screen, Firestore
- Entity: Message, Conversation
- Control: MessageController

### 主なシナリオ

1. ユーザーがメッセージを入力
2. アプリがメッセージを E2EE に暗号化
3. アプリが暗号化済みメッセージを Firestore に直接書き込み
4. Firestore の更新通知 / FCM で受信側に配信トリガー
5. 受信側で復号して表示

### 例外パス

- 送信先不在
- 暗号化鍵不整合
- 配信遅延

## 7. 友達追加（QR コード）

- Actor: User
- Boundary: QR Scanner, Firestore
- Entity: Friend, User
- Control: FriendController

### 主なシナリオ

1. QR コードをスキャン
2. アプリが Firestore へ直接友達リクエストを書き込み
3. 承認時は Firestore トランザクションで友達関係を登録
4. 友達リストを更新

### 例外パス

- QR コード無効
- 相手が既に友達
- ネットワーク障害

## 8. 通知受信

- Actor: User
- Boundary: Push Notification Service
- Entity: Notification
- Control: NotificationManager

### 主なシナリオ

1. Firestore の更新をトリガーとしてサーバー / Cloud Function が FCM へ通知送信
2. 端末が通知を受信
3. アプリが表示・処理

### 例外パス

- 通知配信失敗
- 端末トークン無効

## 9. 位置共有

- Actor: User
- Boundary: Location Service, Location API
- Entity: LocationShare
- Control: LocationController

### 主なシナリオ

1. 位置情報共有を開始
2. 位置を暗号化して送信
3. 受信側に通知
4. 共有場所を表示

### 例外パス

- 位置情報権限拒否
- 位置取得失敗
- 共有先未設定

---

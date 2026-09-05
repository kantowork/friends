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

## 4. 端末移行 / 復活の呪文

- Actor: User
- Boundary: Recovery UI, Firestore (`/users/{uid}/private/data`)
- Entity: User, UserPrivateData
- Control: RecoveryController

### 主なシナリオ

1. ユーザーが復活の呪文を生成・安全に保管する
2. 端末移行時、新しいデバイスで同じ復活の呪文を入力する
3. クライアントがローカルで `recoveryHash` と `K_priv_enc` を導出し、Firestore から暗号化された秘密鍵を取得して復号
4. 復元された鍵ペアとセッション情報を Keychain に格納し、ログイン完了

### 例外パス

- 復活の呪文無効（ハッシュ不一致）
- 復旧データ損失
- ネットワーク障害

## 5. テキストメッセージ暗号化送受信

- Actor: User
- Boundary: Chat Screen, Firestore (`/tenants/{tenantId}/chats/{chatId}/messages`)
- Entity: Message, Chat, KeyBucket
- Control: MessageController, CryptoEngine

### 主なシナリオ

1. ユーザーがメッセージを入力
2. アプリが E2EE 暗号化（1:1 は $SK_{direct}$、かいぎは $SK_{group}$）を実行
3. 暗号化済みペイロードと監査メタデータを Firestore に直接書き込み
4. 受信側が Firestore リアルタイムリスナーで検知し、対応鍵で復号して表示

### 例外パス

- 送信先不在
- 暗号化鍵（KeyBucket）不整合・未取得
- ネットワーク障害

## 6. かいぎ（グループチャット）管理 & 共有鍵ローテーション

- Actor: User (Owner / Admin / Member)
- Boundary: Group Chat View, Firestore (`/tenants/{tenantId}/chats/{chatId}`)
- Entity: Chat, KeyBucket
- Control: GroupChatController

### 主なシナリオ

1. ユーザーが友達を選択してかいぎを新規作成（初期作成者が `owner`、他メンバーは `member`）
2. 作成者端末が新規 $SK_{group, v_1}$ を生成し、参加メンバー全員の公開鍵で個別暗号化して `KeyBucket`（$v_1$）を作成
3. メンバー追加時：招待者端末が新規鍵 $SK_{group, v_2}$ を生成し、追加後メンバー全員の公開鍵で暗号化した `KeyBucket`（$v_2$）を書き込み（後方秘匿性確保）
4. メンバー除外時：管理者端末が対象メンバーを `members` から除外し、残存メンバー向けに新規 `KeyBucket` を発行（前方秘匿性確保）
5. かいぎ削除時：オーナーまたは管理者が確認ダイアログを経て `members: []`, `isDeleted: true` に更新

### 例外パス

- 権限不足（一般メンバーによる他者除外や削除試行）
- 削除確認キャンセル
- 鍵バケット書き込み競合

## 7. メッセージ既読 & リアクション

- Actor: User
- Boundary: Chat View, Firestore (`/reactions`, `/receipts`)
- Entity: MessageReaction, ReadReceipt, Message
- Control: ReactionController, ReceiptController

### 主なシナリオ

1. ユーザーがメッセージ一覧を閲覧：最新閲覧メッセージIDで水位線カーソル（`ReadReceipt`）を更新
2. ユーザーが絵文字リアクションをタップ：リアクションサブコレクション登録と親メッセージの集計カウント更新をアトミック実行
3. 長押しによりリアクション詳細シートを表示：該当リアクションの送信者一覧を表示

### 例外パス

- 同一絵文字の再タップ（リアクション解除・デクリメント）
- ネットワーク遅延

## 8. 友達追加（QR コード & 30秒更新3桁合言葉 TOTP）

- Actor: User
- Boundary: Friend Add Screen, Camera/QR Scanner, Firestore
- Entity: Friend, FriendInvitation, User
- Control: FriendController

### 主なシナリオ

1. 提示側が QR コード（または 30 秒更新の 3 桁合言葉）を表示
2. 読取側が QR コードをスキャン（または合言葉を入力照合）
3. 相手の `userId`・公開鍵・暗号化表示名を取得
4. Firestore 上で相互の `/friends` サブコレクションおよび DM 用チャットドキュメントをアトミックに初期化・登録

### 例外パス

- QR コード無効・期限切れ
- 3桁合言葉の不一致または有効期限（30秒）超過
- 相手が既に友達

## 9. 通知受信

- Actor: User
- Boundary: App / OS Notification Center, FCM / APNs
- Entity: Message, Device
- Control: NotificationManager

### 主なシナリオ

1. メッセージ着信時、フォアグラウンド起動中であればアプリ内トースト通知を表示
2. バックグラウンド時は APNs / FCM 経由でプッシュ通知を受信（Time-Sensitive 対応）

---

## 10. 将来構想シナリオ (Phase 2 以降)

### テナント管理者のメタデータ監査
- Actor: テナント管理者
- Boundary: Audit Console, 専用サーバー API（※現行 Phase 1 では未実装）
- メタデータ集計・閲覧

### 音声・ビデオ通話
- WebRTC シグナリングおよびセッション確立

### 位置情報共有
- 暗号化位置座標のリアルタイム共有


---

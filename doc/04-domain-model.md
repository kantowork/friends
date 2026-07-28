# ドメインモデル（改訂版）

この文書は Friends プロジェクトの主要ドメインエンティティ、関係、および暗号鍵ライフサイクルの位置付けを定義します。

## 1. 主要エンティティ

### Tenant

- `tenantId`: テナント不変一意識別子 (`t_` プレフィックス、システム内部・Firestoreドキュメントキー、変更不可)
- `tenantCode`: テナント表示用・変更可能コード (例: `kantowork`、ユーザー向け表示)
- `tenantName`: アプリ内復号済みテナント表示名 (例: `カントーワーク`)
- `encryptedTenantName`: MK_T で AES-256-GCM 暗号化したテナント表示名 (Base64)
- `tenantNameNonce`: 暗号化 Nonce (Base64)
- `isDefaultTenant`: デフォルトテナントフラグ
- `configuration`: テナント固有設定
- `createdAt`, `createdBy`, `updatedAt`, `updatedBy`

### User

- `userId`: ユーザー識別子 (`u_` + Base58(UUID) 最大22文字、システム不変キー、変更不可)
- `uid`: Firebase Auth 認証で取得する全域一意の認証ID (Auth UID, 非公開)
- `username`: ユーザー名 (初期値: `userId` と同値、小文字テナント内一意、ユーザー向け表示・変更可能)
- `tenantId`: 所属テナントID (`t_...`)
- `displayName`: アプリ内復号済み表示名 (暗号化保存)
- `groupIds`: 配列 — 所属するグループIDリスト
- `accountType`: `anonymous` | `persistent`
- `publicKey` / `keyPair`（クライアント側に主に保管）
- `localKeyMetadata`: キー識別子・ストレージ場所など
- `recoveryPhrase`: 復活の呪文（安全な管理を前提）
- `profileInfo`, `deviceInfo`

### Device

- `deviceId`: 端末デバイスID (`d_...`)
- `deviceType`: ディスプレイ種別（`ios` | `android` | `web`）
- `deviceToken`: プッシュ通知用トークン（FCM/APNs）
- `publicKey`: デバイス固有の公開鍵
- `registeredAt`, `lastSeenAt`

### Message

- `messageId`: メッセージ一意識別子 (`m_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `chatId`: トークID (`dm_...` / `gm_...`)
- `senderId`: 送信者 `userId`
- `keyVersion`: 使用鍵バージョン（例: `v_1`, `v_2`）
- `encryptedPayload`: Map (`ciphertext`, `nonce`)
- `createdAt`
- `messageType`: `text` | `image` | `system`

### Chat (会話/グループ)

- `chatId`: 会話一意識別子 (`dm_...` | `gm_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `members`: 配列 (参加者の `uid` リスト)
- `chatType`: `direct` | `group`
- `createdAt`, `updatedAt`

### Group

- `groupId`: グループ一意識別子
- `tenantId`: 所属テナントID
- `groupName`: グループ名
- `description`: グループの概要・説明
- `isDefaultGroup`: boolean — デフォルトグループフラグ（テナント参加時に新ユーザーが自動アサイン）
- `memberUserIds`: 配列 — グループに所属するユーザーIDリスト
- `createdAt`, `createdBy`, `updatedAt`, `updatedBy`

### Friend

- `relationshipId`: 関係一意識別子
- `tenantId`: 所属テナントID (`t_...`)
- `ownerUserId`: ユーザーID (`u_...`)
- `friendUserId`: 相手のユーザーID (`u_...`)
- `connectionStatus`: `active` | `blocked`
- `addedAt`: 作成日時
- `verifiedVia`: `qr_scan` | `text_passcode`

### FriendInvitation (招待データ・一時ペイロード)

- `version`: ペイロードバージョン (1)
- `tenantId`: 所属テナントID (`t_...`)
- `userId`: 送信者公開ID (`u_...`)
- `uid`: Firebase Auth 全域UID
- `displayName`: 表示名
- `publicKey`: 送信者の端末公開鍵
- `passcode`: 30秒更新の3桁合言葉 (`000`〜`999`)
- `timestamp`: 生成時刻 (エポック秒)
- `encodedFormat`: `FRIENDS_USER:<base64>`

### CallSession

- `callId`, `participants`, `callType`（audio/video）
- `startTime`, `endTime`, `status`

### Post

- `postId`, `authorId`, `content`, `tags`, `createdAt`, `reactions`

### LocationShare

- `shareId`, `ownerId`, `targetId`, `location`, `timestamp`

### AuditLog

- `auditId`, `tenantId`, `actorId`, `action`, `targetId`, `timestamp`, `details`（本文は含めない）

### TenantConfig (補助エンティティ)

- テナントのポリシー、QR 表示データ、監査設定など
  - note: QR コードはテナント作成後に生成され、管理者が配布する想定（`qrCodeData` を保存・参照）

## 2. 関係および Cloud Firestore 階層構造

各テナントに紐づくデータリソースは、データ分離および Security Rules 適用のため、Cloud Firestore 上で `/tenants/{tenantId}` のサブコレクション構造として厳格に管理されます：

- `/tenants/{tenantId}` (テナント設定・マスターキーメタデータ)
  - `/tenants/{tenantId}/chats/{chatId}` (グループ・DM共通のチャットコレクション)
    - `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}` (暗号化メッセージ)
  - `/tenants/{tenantId}/users/{userId}` (テナント所属ユーザープロファイル・公開鍵)
- `/users/{uid}` (匿名ユーザ・永続ユーザ共通の公開プロフィール)
  - `/users/{uid}/private/data` (永続ユーザ用の復元データ等)

- Tenant 1:N User
- Tenant 1:N Group
- Tenant 1:N Conversation
- Tenant 1:N Message
- Group N:M User
- User 1:N Device
- User 1:N Friend
- Conversation 1:N Message
- User 1:N Post
- User 1:N CallSession

## 3. 鍵管理と E2EE の位置付け

- テナントは暗号化通信のためのマスターキー（`MK_T`）を保持・管理し、サーバー単体では本文の復号が出来ない設計を維持する。
- メッセージ暗号化には、1:1 チャットでは `SK_direct`（共有セッションキー）、グループでは `SK_group`（グループ共有セッションキー）を使用し、`keyVersion` と `encryptedPayload` (`ciphertext`, `nonce`) でパケットを構成する。
- 端末移行・アカウント復旧時は、「ふっかつのじゅもん（Mnemonic Phrase）」からクライアントローカルで `recoveryHash` と秘密鍵復号キー（`K_priv_enc`）を確定導出する。
- サーバーには `recoveryHash` と暗号化された秘密鍵（`encryptedPrivateKey`）のみが保存され、プレーンテキストのフレーズや秘密鍵は一切保存されない。

## 4. 運用上の設計注記

- 鍵素材は KMS（Cloud KMS / HSM）に保存し、`keyMaterialRef` で参照する。アプリ側は秘密鍵を Keychain / Secure Enclave 等で保護する。
- 鍵ローテーションは `rotationPolicy.rotationMethod` が `automatic` の場合は自動化し、必ずインベントリと監査ログを残す。
- 監査（`AuditLog`）はメタデータ中心とし、コンテンツ本文のアクセスは限定的にする。

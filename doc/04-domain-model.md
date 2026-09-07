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
- `encryptedDisplayName`: $MK_T$ で AES-256-GCM 暗号化した表示名 (Base64)
- `displayNameNonce`: 表示名暗号化 Nonce (Base64)
- `avatarNonce`: $MK_T$ で暗号化した Cloudflare R2 アバター画像の Nonce (Base64)
- `avatarUpdatedAt`: アバター最終更新日時
- `accountType`: `anonymous` | `persistent`
- `role`: `USER_ROLE_MEMBER` | `USER_ROLE_ADMIN`
- `publicKey` / `keyPair`: クライアント Keychain に秘密鍵 $SK_u$ 保管、公開鍵 $PK_u$ (Base64) のみ公開
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

### Device

- `deviceId`: 端末デバイスID (`d_...`)
- `deviceType`: ディスプレイ種別（`ios` | `android` | `web`）
- `deviceToken`: プッシュ通知用トークン（FCM/APNs）
- `registeredAt`: 登録日時

### Chat (会話/かいぎ)
※ 本アプリではグループチャットを「かいぎ」と呼びます（英語表記は `group chat`、ID体系: `gm_...`）。1:1 チャットはダイレクトメッセージ（ID体系: `dm_...`）です。

- `chatId`: 会話一意識別子 (`dm_...` | `gm_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `members`: 配列 (参加者の `userId` リスト - クエリ用)
- `chatType`: `direct` | `group`
- `title`: かいぎのタイトル（グループチャットのみ）
- `memberRoles`: マップ (`userId -> GroupMemberRole`) — 各メンバーの属性（ロール）
  - `owner` (`GROUP_MEMBER_ROLE_OWNER`): グループオーナー（初期作成者。1名。退出不可。かいぎ削除権限・管理者任命権限・他メンバー退出権限・かいぎ名変更権限）
  - `admin` (`GROUP_MEMBER_ROLE_ADMIN`): グループ管理者（複数可。立候補型オーナー昇格権限。かいぎ削除権限・管理者任命権限・他メンバー退出権限・かいぎ名変更権限）
  - `member` (`GROUP_MEMBER_ROLE_MEMBER`): 一般メンバー（送受信、招待、自らかいぎを退出する権限）
- `latestKeyVersion`: 最新鍵バージョン（例: `v_1`, `v_2`）
- `lastMessage`: 最後に送信されたメッセージのプレビュー
- `lastMessageAt`: 最終メッセージ日時
- `isDeleted`: boolean — 削除フラグ（削除時は `members: []` にクリアして非表示化）
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

### KeyBucket (会話共有鍵バケット)

- `keyVersion`: バージョン識別子 (`v_1`, `v_2` ...)
- `chatId`: チャットID (`gm_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `encryptedGroupKeys`: マップ (`userId -> Base64(Encrypt(PK_u, SK_group))`) — 各自の公開鍵で暗号化されたグループ会話鍵
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

### Message

- `messageId`: メッセージ一意識別子 (`m_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `chatId`: トークID (`dm_...` / `gm_...`)
- `senderId`: 送信者 `userId` (`u_...`)
- `keyVersion`: 使用鍵バージョン（例: `v_1`, `v_2`）
- `encryptedPayload`: Map (`ciphertext`, `nonce`)
- `messageType`: `text` | `image` | `system`
- `reactionCounts`: マップ (`emoji -> count`) — リアクション集計
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

### MessageReaction (メッセージリアクション)

- `userId`: リアクション操作者 `userId` (`u_...`)
- `chatId`: トークID (`dm_...` / `gm_...`)
- `messageId`: 対象メッセージID (`m_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `emoji`: リアクション絵文字種別（8種、クイックアクション7種）
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

### ReadReceipt (既読水位線カーソル)

- `userId`: 閲覧者 `userId` (`u_...`)
- `chatId`: トークID (`dm_...` / `gm_...`)
- `tenantId`: 所属テナントID (`t_...`)
- `lastReadMessageId`: 最後に閲覧したメッセージID (`m_...`)
- `lastReadAt`: 閲覧メッセージの作成日時タイムスタンプ
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

### Friend

- `relationshipId`: 関係一意識別子
- `tenantId`: 所属テナントID (`t_...`)
- `ownerUserId`: ユーザーID (`u_...`)
- `friendUserId`: 相手のユーザーID (`u_...`)
- `encryptedFriendDisplayName`: 相手の表示名 (テナントマスターキー $MK_T$ による AES-256-GCM 暗号化)
- `friendDisplayNameNonce`: 暗号化 Nonce (Base64)
- `friendUsername`: 相手のユーザー名
- `friendPublicKey`: 相手の公開鍵 (Base64)
- `createdBy`, `createdAt`, `updatedBy`, `updatedAt`

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

### UserPrivateData (ユーザー非公開・復元用データ)

- `uid`: Firebase Auth 全域 UID
- `recoveryHash`: `SHA256(K_recovery_id)`
- `encryptedPrivateKey`: $K_{priv\_enc}$ で暗号化した秘密鍵 $SK_u$ (Base64)
- `nonce`: 暗号化 Nonce / IV (Base64)
- `updatedAt`: 更新日時

### AuditLog

- `auditId`: 監査ログ一意識別子
- `tenantId`: 所属テナントID
- `actorId`: 操作者ID
- `action`: 操作種別
- `targetId`: 操作対象ID
- `timestamp`: 操作日時
- `details`: 操作メタデータ詳細（本文は一切含めない）

---

## 2. 関係および Cloud Firestore 階層構造

各テナントに紐づくデータリソースは、データ分離および Security Rules 適用のため、Cloud Firestore 上で `/tenants/{tenantId}` のサブコレクション構造として厳格に管理されます：

```text
/tenants/{tenantId}                                    : テナント情報・設定
       /users/{userId}                                 : テナント所属ユーザー公開プロファイル (u_)
              /friends/{friendUserId}                  : 友達サブコレクション
       /usernames/{username}                           : ユーザー名一意性排他インデックス
       /chats/{chatId}                                 : 会話ドキュメント (DM: dm_, かいぎ: gm_)
              /messages/{messageId}                    : E2EE暗号化メッセージ (m_)
                        /reactions/{reactionUserId}    : メッセージリアクション
              /receipts/{receiptUserId}                : 既読水位線カーソル
              /keys/{keyVersion}                       : かいぎ会話共有鍵バケット (v_)
/users/{uid}                                           : 認証ユーザー公開情報
       /private/data                                   : アカウント復元用・暗号化秘密鍵
```

### エンティティ関係性
- Tenant 1:N User
- Tenant 1:N Chat
- User N:M Chat (via `Chat.members`)
- Chat 1:N Message
- Chat 1:N KeyBucket
- Chat 1:N ReadReceipt
- Message 1:N MessageReaction
- User 1:N Friend
- User 1:1 UserPrivateData

---

## 3. 鍵管理と E2EE の位置付け

- テナントは暗号化通信のためのマスターキー（`MK_T`）を保持・管理し、サーバー単体では本文の復号が出来ない設計を維持する。
- メッセージ暗号化には、1:1 チャットでは `SK_direct`（共有セッションキー）、かいぎ（グループ）では `SK_group`（グループ共有セッションキー）を使用し、`keyVersion` と `encryptedPayload` (`ciphertext`, `nonce`) でパケットを構成する。
- 端末移行・アカウント復旧時は、「ふっかつのじゅもん（Mnemonic Phrase）」からクライアントローカルで `recoveryHash` と秘密鍵復号キー（`K_priv_enc`）を確定導出する。
- サーバーには `recoveryHash` と暗号化された秘密鍵（`encryptedPrivateKey`）のみが保存され、プレーンテキストのフレーズや秘密鍵は一切保存されない。

---

## 4. 運用上の設計注記

- 鍵素材は KMS（Cloud KMS / HSM）に保存し、`keyMaterialRef` で参照する。アプリ側は秘密鍵を Keychain / Secure Enclave 等で保護する。
- メタデータ監査はクライアント直接 Firestore アクセスのルールに基づき、コンテンツ本文のアクセスは限定的（不可）にする。

---

## 5. 将来構想ドメインモデル (Phase 2 以降)

以下のエンティティは、Phase 2 以降の機能拡張時に設計を具体化する構想モデルです：

### CallSession (通話セッション)
- `callId`: 通話一意識別子
- `chatId`: 紐づくかいぎ/DM ID
- `callType`: `audio` | `video`
- `participants`: 参加者リスト
- `status`: `initiating` | `active` | `ended`
- `startedAt`, `endedAt`

### Post (投稿・タグ)
- `postId`, `authorId`, `content`, `tags`, `reactions`, `createdAt`

### LocationShare (位置共有)
- `shareId`, `ownerId`, `targetId`, `encryptedLocation`, `expiresAt`, `createdAt`


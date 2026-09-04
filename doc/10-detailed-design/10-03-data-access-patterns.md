# 10-03: Firebase / Cloudflare R2 データアクセスパターン一元管理仕様書 (Data Access Patterns & API Specification)

本ドキュメントは、**Friends** におけるすべてのバックエンドリソース（Cloud Firestore / Cloudflare R2 / Cloud Storage）に対するデータアクセスパターン、CRUD/クエリ関数一覧、引数・戻り値の型シグネチャ、およびリアルタイム同期（`onSnapshot`）仕様を一元的に集約・定義する包括的な詳細設計書です。

---

## 1. 全体アーキテクチャとアクセス方針

### 1.1 基本原則
- **3層アーキテクチャと Repository ディレクトリ分離**:
  - すべてのデータベース・ファイルストレージ（Cloud Firestore / Cloudflare R2 / Cloud Storage）データアクセス処理（CRUD・リアルタイム `onSnapshot` 購読）は、クライアントアプリケーションの `Repositories/` ディレクトリ（例: `ios/Sources/Repositories/`）に集約・実装します。
  - Service 層や View 層から直接 SDK / HTTP クライアントを呼び出すことを禁止し、Repository 経由で呼び出す構成とします。
- **直接アクセス & 高速 CDN 配信 (Direct Access & Global CDN)**:
  - データベースは Firestore SDK 経由で直接 CRUD / リアルタイム購読を実行。
  - 暗号化メディアバイナリ（アバター、画像、添付ファイル）は、高速・帯域幅（Egress）課金ゼロの **Cloudflare R2（S3互換 + Cloudflare CDN）** を標準ストレージとして直接アップロード/ダウンロードします。
- **ゼロ知識暗号化 (Zero-Knowledge / E2EE)**:
  - テナント機密データ（表示名、アバター、グループ名等）はテナントマスターキー（$MK_T$）で暗号化。
  - 1:1 / グループメッセージはセッションキー（$SK_{direct}$ / $SK_{group}$）で E2EE 暗号化。
- **関数命名規約**:
  - `get[Resource]By[Key]` : 単一ドキュメント/データの取得
  - `list[Resource]By[Key]` : コレクション/クエリによる複数件取得
  - `watch[Resource]By[Key]` : `onSnapshot` によるリアルタイム購読
  - `create[Resource]` / `set[Resource]` : 新規作成・初期登録
  - `update[Resource]By[Key]` : 特定フィールドの更新 (全体)
  - `patch[Resource]By[Key]`  : 特定フィールドの更新 (部分)
  - `delete[Resource]By[Key]` : 削除
  - `upload[Resource]By[Key]` : Storage / R2 バイナリの暗号化アップロード


---

## 2. Firebase パス・リソース一覧マップ

### 2.1 Cloud Firestore パス階層

```text
/tenants/{}                                   : テナント基本情報
           /users/{}                          : ユーザープロファイル
                    /friends/{}               : 私の友達一覧
           /chats/{}                          : チャット（DM / かいぎ）
                    /messages/{}              : E2EE暗号化メッセージ
                                /reactions/{} : メッセージリアクション
                    /receipts/{}              : 既読位置・タイムスタンプ
                    /keys/{}                  : 共通鍵バケット
/users/{}                                     : 認証ユーザー情報
         /private/data                        : アカウント復元用・暗号化秘密鍵
```

### 2.2 Cloud Storage パス階層

```text
/tenants/{}
           /users/{}/avatar.enc  : 暗号化ユーザーアバターバイナリ
           /groups/{}/avatar.enc : 暗号化グループアイコンバイナリ
```

---

## 3. アクセスパターン一覧

### 3.1 テナント (Tenant) アクセスパターン

#### TP-01: デフォルトテナント取得
- **操作種別** : Read (Query)
- **対象パス** : `/tenants` (where `isDefaultTenant == true`, `limit(1)`)
- **関数名**   : `fetchDefaultTenant(completion:)`
- **概要**     : 初回起動時や未参加時の組織取得。

#### TP-02: テナント情報取得
- **操作種別**: Read
- **対象パス**: `/tenants/{tenantId}`
- **関数名**: `getTenantByTenantId(tenantId:completion:)`
- **概要**: テナント表示名の復号とメタデータ取得。

---

### 3.2 ユーザー・プロファイル (User & Profile) アクセスパターン

#### UP-01: 全域公開鍵取得
- **操作種別** : Read
- **対象パス** : `/users/{uid}`
- **関数名**   : `getUserByUid(uid:completion:)`
- **概要**     : ユーザー全域の公開鍵を取得。

#### UP-02: ユーザー非公開復元データ登録
- **操作種別** : Write (Create/Set)
- **対象パス** : `/users/{uid}/private/data`
- **関数名**   : `setUserPrivateDataByUid(uid:data:completion:)`
- **概要**.    : 復活の呪文で暗号化した秘密鍵バックアップを保存。

#### UP-03: ユーザー非公開復元データ取得
- **操作種別** : Read
- **対象パス** : `/users/{uid}/private/data`
- **関数名**   : `getUserPrivateDataByUid(uid:completion:)`
- **概要**     : アカウント復元時の暗号化秘密鍵取得。

#### UP-04: テナント内プロファイル取得
- **操作種別**: Read
- **対象パス**: `/tenants/{tenantId}/users/{userId}`
- **関数名**: `getUserProfileByUserId(tenantId:userId:completion:)`
- **概要**: テナント内のユーザープロファイル・公開鍵・アバターメタデータを取得。

#### UP-05: テナント内プロファイル作成/更新
- **操作種別**: Write (Set/Merge)
- **対象パス**: `/tenants/{tenantId}/users/{userId}`
- **関数名**: `createOrUpdateUserProfile(tenantId:user:completion:)`
- **監査要件**:
  - 作成時: `createdBy: userId`, `createdAt: serverTimestamp()`, `updatedBy: userId`, `updatedAt: serverTimestamp()`
  - 更新時: `createdBy`, `createdAt` は変更不可。`updatedBy: userId`, `updatedAt: serverTimestamp()`

#### UP-06: 表示名更新
- **操作種別**: Update
- **対象パス**: `/tenants/{tenantId}/users/{userId}`
- **関数名**: `updateDisplayNameByUserId(tenantId:userId:name:completion:)`
- **監査要件**: `updatedBy: userId`, `updatedAt: serverTimestamp()`
- **概要**: 表示名を $MK_T$ で暗号化して更新。

---

### 3.3 友達 (Friends) アクセスパターン

#### FP-01: 友達一覧リアルタイム購読
- **操作種別**: Listen (`onSnapshot`)
- **対象パス**: `/tenants/{tenantId}/users/{userId}/friends`
- **関数名**: `watchFriendsByUserId(tenantId:userId:onChange:)`
- **概要**: 友達の追加・削除をリアルタイム検知。

#### FP-02: 友達関係の双方向追加
- **操作種別**: Batch Write
- **対象パス**:
  - `/tenants/{tenantId}/users/{myUserId}/friends/{friendUserId}`
  - `/tenants/{tenantId}/users/{friendUserId}/friends/{myUserId}`
- **関数名**: `createFriendBidirectional(tenantId:myUser:friendUser:completion:)`
- **監査要件**:
  - 作成時: `createdBy: myUserId`, `createdAt: serverTimestamp()`, `updatedBy: myUserId`, `updatedAt: serverTimestamp()`
- **概要**: 相互のサブコレクションにアトミック同時書き込み（Auth UID は使用せず `userId` で相互認可）。

#### FP-03: 友達削除
- **操作種別**: Delete
- **対象パス**: `/tenants/{tenantId}/users/{userId}/friends/{friendUserId}`
- **関数名**: `deleteFriendByUserId(tenantId:userId:friendUserId:completion:)`
- **概要**: 特定の友達関係を解除・削除。

#### FP-04: 友達プロファイル一括最新化
- **操作種別**: Batch Read
- **対象パス**: `/tenants/{tenantId}/users/{friendUserId}`
- **関数名**: `listFriendsProfilesByUserIds(tenantId:friendUserIds:completion:)`
- **概要**: Pull-to-Refresh 時のプロファイル差分取得。

---

### 3.4 アバター (Avatar) アクセスパターン (Cloudflare R2 連携)

#### AP-01: アバター画像暗号化アップロード
- **操作種別**: Write (Cloudflare R2 + Firestore)
- **対象パス**:
  - R2 Storage: `https://<R2_CUSTOM_DOMAIN>/tenants/{tenantId}/users/{userId}/avatar.enc`
  - Firestore: `/tenants/{tenantId}/users/{userId}`
- **関数名**: `uploadAvatarByUserId(image:tenantId:userId:completion:)`
- **監査要件**: `updatedBy: userId`, `updatedAt: serverTimestamp()`
- **概要**: 画像を 256x256 圧縮・$MK_T$ 暗号化して R2 バケットに S3 互換 PUT / 署名付き URL アップロード後、Firestore の `encryptedAvatar`（または R2 パス）, `avatarNonce`, `avatarUpdatedAt` を更新。

#### AP-02: アバター画像ダウンロード・復号
- **操作種別**: Read (2層キャッシュ優先 + R2 CDN HTTP GET)
- **対象パス**: R2 Storage: `https://<R2_CUSTOM_DOMAIN>/tenants/{tenantId}/users/{userId}/avatar.enc`
- **関数名**: `getAvatarByUserId(tenantId:userId:avatarNonce:updatedAt:completion:)`
- **概要**: メモリキャッシュ（`NSCache`）確認後、未キャッシュ時のみ Cloudflare CDN 経由で暗号化バイナリを高速 GET 取得し、$MK_T$ で復号。

#### AP-03: アバター削除
- **操作種別**: Delete (Cloudflare R2 + Firestore)
- **対象パス**:
  - R2 Storage: `https://<R2_CUSTOM_DOMAIN>/tenants/{tenantId}/users/{userId}/avatar.enc`
  - Firestore: `/tenants/{tenantId}/users/{userId}`
- **関数名**: `deleteAvatarByUserId(tenantId:userId:completion:)`
- **監査要件**: `updatedBy: userId`, `updatedAt: serverTimestamp()`
- **概要**: R2 上の暗号化バイナリ削除および Firestore メタデータ（`avatarNonce`, `avatarUpdatedAt`）消去。


---

### 3.5 チャット & メッセージ (Chat & Messages) アクセスパターン

#### CP-01: 参加チャット一覧購読 (複合インデックス最適化)
- **操作種別**: Listen (`onSnapshot`)
- **対象パス**: `/tenants/{tenantId}/chats`
- **クエリ条件**: `whereField("members", arrayContains: userId).order(by: "updatedAt", descending: true).limit(to: 50)`
- **関数名**: `watchChatsByUserId(tenantId:userId:limit:onChange:)`
- **負荷低減設計**:
  - 複合インデックス（`members: array-contains` + `updatedAt: DESC`）を活用し、不要な全ドキュメントスキャンを排除。
  - `limit(to: 50)` を適用し、通信量および初期レンダリング負荷を最小化。

#### CP-02: チャットメタデータ作成・更新
- **操作種別**: Write / Update (Set with merge)
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}`
- **関数名**: `MessageRepository.createMessage` 内部での自動初期化/更新（旧 `createDirectChatIfNotExists` はデッドコードとして廃止）
- **監査要件**:
  - 作成時: `createdBy: myUserId`, `createdAt: serverTimestamp()`, `updatedBy: myUserId`, `updatedAt: serverTimestamp()`
  - 更新時: `createdBy`, `createdAt` は不変。`updatedBy: myUserId`, `updatedAt: serverTimestamp()`
- **概要**: チャットルームの初期作成または最終メッセージメタデータ更新。DM の場合は `members: [min(uA, uB), max(uA, uB)]` で初期化。

#### MP-01: 新着メッセージ購読 & 過去メッセージの動的オンデマンド取得 (Dynamic Pagination)
- **操作種別**: Listen (`onSnapshot`) + Dynamic Limit Expansion
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}/messages` (order `createdAt asc`, `limitToLast(limit)`)
- **関数名**: `watchMessagesByChatId(tenantId:chatId:limit:onChange:)` / `loadMoreMessages(chatId:pageSize:)`
- **動的ページネーション仕様**:
  - **初期表示**: 最新の 30 件（`initialLimit: 30`）をリアルタイム購読し、初期通信量・メモリ使用量を最小化。
  - **上スクロール時の遡りロード**: ユーザーが上方向にスクロールして最上部付近に到達した際、`limit` を +30 件ずつ動的に拡張してリスナーを再設定（または追加過去データを取得）。
  - **リアルタイム整合性**: リアルタイムリスナーのウィンドウを拡張する方式により、過去メッセージへのリアクション変更や新着メッセージの受信・既読管理を同一ストリームで一貫して保証。
  - **全件到達判定**: 取得件数が要求 `limit` 未満となった場合、`hasMoreMessages = false` として不要なバックエンドクエリを停止。

#### MP-02: 暗号化メッセージ送信
- **操作種別**: Create (Append)
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}`
- **関数名**: `createMessage(tenantId:chatId:message:members:completion:)`
- **監査要件**:
  - 作成時: `createdBy: senderId`, `createdAt: serverTimestamp()`, `updatedBy: senderId`, `updatedAt: serverTimestamp()`
- **概要**: E2EE 暗号化本文と監査用メタデータを Firestore に追記。親チャット未作成時は親ドキュメントを `members` とともにアトミックに初期化・更新。

---

### 3.5.1 グループチャット (Group Chat) アクセスパターン

#### GP-01: グループチャット作成
- **操作種別**: Write (Create/Set)
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}`
- **関数名**: `createGroupChat(tenantId:chatId:title:members:createdBy:completion:)`
- **監査要件**: `createdBy: myUserId`, `createdAt: serverTimestamp()`, `updatedBy: myUserId`, `updatedAt: serverTimestamp()`
- **概要**: グループチャットドキュメント（`chatType: "group"`, `title`, `members`, `createdBy`）を作成。

#### GP-02: グループメンバー追加
- **操作種別**: Update (ArrayUnion)
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}`
- **関数名**: `addGroupMembers(tenantId:chatId:newMembers:updatedBy:completion:)`
- **監査要件**: `updatedBy: myUserId`, `updatedAt: serverTimestamp()`
- **概要**: 既存グループチャットの `members` フィールドに新規 UID を追加。

---

### 3.6 リアクション & 既読管理 (Reactions & Read Receipts) アクセスパターン

#### RP-01: メッセージリアクション購読
- **操作種別**: Listen (`onSnapshot`)
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}/reactions`
- **関数名**: `watchReactionsByMessageId(tenantId:chatId:messageId:onChange:)`
- **概要**: メッセージ個別のリアクション内訳をリアルタイム購読。

#### RP-02: リアクション追加・更新
- **操作種別**: Batch Write
- **対象パス**:
  - `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}/reactions/{userId}`
  - `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}` (`reactionCounts` カウント加算)
- **関数名**: `setReactionByUserId(tenantId:chatId:messageId:userId:emoji:completion:)`
- **監査要件**:
  - リアクションサブコレクション: `createdBy: userId`, `createdAt: serverTimestamp()`, `updatedBy: userId`, `updatedAt: serverTimestamp()`
  - 親メッセージ: `updatedBy: userId`, `updatedAt: serverTimestamp()`
- **概要**: リアクションサブコレクション追加と集計カウントのインクリメント。

#### RP-03: リアクション解除
- **操作種別**: Batch Write
- **対象パス**:
  - `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}/reactions/{userId}` (Delete)
  - `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}` (`reactionCounts` カウント減算)
- **関数名**: `deleteReactionByUserId(tenantId:chatId:messageId:userId:completion:)`
- **監査要件**: 親メッセージ: `updatedBy: userId`, `updatedAt: serverTimestamp()`
- **概要**: リアクションの取り消しと集計カウントのデクリメント。

#### RR-01: 既読状態購読
- **操作種別**: Listen (`onSnapshot`)
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}/receipts`
- **関数名**: `watchReadReceiptsByChatId(tenantId:chatId:onChange:)`
- **概要**: チャット内メンバーの既読位置（水位線カーソル）を購読。

#### RR-02: 既読カーソル更新
- **操作種別**: Set/Merge
- **対象パス**: `/tenants/{tenantId}/chats/{chatId}/receipts/{userId}`
- **関数名**: `updateReadReceiptByUserId(tenantId:chatId:userId:lastReadMessageId:lastReadAt:completion:)`
- **監査要件**: `createdBy: userId`, `createdAt: serverTimestamp()`, `updatedBy: userId`, `updatedAt: serverTimestamp()`
- **概要**: 自身が最新メッセージを閲覧した際の水位線カーソル更新。

---

## 4. Firestore 複合インデックス定義 (Composite Indexes)

高頻度アクセスおよびリアルタイムリスナーの負荷を最小化するため、以下の複合インデックスを Firestore に設定します。

### 4.1 インデックス設定 (`infra/firestore.indexes.json`)

```json
{
  "indexes": [
    {
      "collectionGroup": "chats",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "members", "arrayConfig": "CONTAINS" },
        { "fieldPath": "updatedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "messages",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "createdAt", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "friends",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "addedAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

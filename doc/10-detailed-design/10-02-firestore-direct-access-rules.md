# 10-02: Firestore 直接格納・アクセス制御ルール仕様書

本ドキュメントでは、クライアント（iOS/Web/Android）がサーバー API を経由せず、直接 Cloud Firestore にデータを格納・取得する際の設計ルール、セキュリティルール（Security Rules）方針、およびデータの不変性制御仕様を定義します。

---

## 1. 直接アクセスの基本方針

本システムでは、低レイテンシ通信、リアルタイムリスナーの活用、およびオフラインファースト設計を実現するため、メッセージ送受信やユーザー情報の同期において**クライアントからの Firestore 直接アクセス**を原則とします。

サーバーを経由しないことによる改ざんや不正アクセスを防ぐため、以下の 3 層の防衛ラインを構築します。

1. **Firestore Security Rules による宣言的認可**
2. **E2EE（暗号化データ）と平文（監査メタデータ）の厳格な分離**
3. **クライアント SDK における型定義とサーバータイムスタンプの強制**

---

## 2. E2EEデータと平文メタデータの格納境界ルール

Firestore に保存されるすべてのフィールドは、セキュリティおよびテナント管理者による監査可能性（メタデータ監査要件）の観点から明確に分離されます。

### 2.1 平文格納が禁止されるデータ (E2EEデータ)
- メッセージ本文（テキスト）、添付ファイルデータ
- ユーザーの非公開属性（秘密鍵、復旧用キーワード等）
- 位置共有機能における生座標データ

### 2.2 平文格納が必須・許可されるデータ (監査用メタデータ)
- メッセージ ID、テナント ID、チャット ID (`chatId`)
- 送信者 UID (`senderId`)
- タイムスタンプ (`createdAt` - サーバー時刻)
- 鍵バージョン情報 (`keyVersion`)

> **注意**: テナント管理者はメタデータ（「誰が・いつ・どのチャットで送信したか」）の取得権限を持ちますが、暗号化ペイロード (`ciphertext`) を復号するためのセッションキーを持たないため、本文閲覧は不可能です。

### 2.3 秘密鍵バックアップ・復元データ領域 (/users/{uid}/private/data)
- **読み取り認可**: 本人（`request.auth.uid == uid`）のみ許可。第三者・未認証の直接読み取りは完全禁止。
- **書き込み認可**: 本人のみ許可。作成・更新時は以下のスキーマ・サイズをセキュリティルールで強制：
  - `uid == request.auth.uid`
  - `recoveryHash` は 64 文字の Hex 文字列（SHA-256）
  - `encryptedPrivateKey` は 2048 文字未満の Base64 文字列
  - `nonce` は 128 文字未満の Base64 文字列
- **削除認可**: 完全禁止（`allow delete: if false;`）。誤操作や不正リクエストによる秘密鍵バックアップの消失を防止。

---

## 3. クライアント直接格納における運用ルール

1. **直書き込み時の型安全性の担保**:
   - TypeScript / Swift で定義された Domain Model をエンコードして Firestore に書き込みます。定義外フィールド混入防止のため `hasOnly()` で厳格に制限します。
2. **1:1 ダイレクトメッセージ (DM) のメンバー規約**:
   - DM チャット（`dm_...`）の `members` 配列は **厳密に2要素**（自分と相手の公開 `userId`）で構成されます。
   - 配列の 0 番目には **辞書順（文字列昇順）で若い方の `userId`**、1 番目には大きい方の `userId` を格納します（`members[0] < members[1]`）。
   - チャット ID も `dm_${members[0]}_${members[1]}` の形式に従います。
   - セキュリティルールにおいて `members.size() == 2` かつ `members[0] < members[1]` かつ `chatId == 'dm_' + members[0] + '_' + members[1]` を強制します。
   - **親ドキュメント先行購読・未作成耐性**: クライアントが友達一覧から DM 画面を開いた際、親チャットドキュメント作成完了前にメッセージリスナーが初期化されるレースコンディションを防ぐため、セキュリティルール `isChatMember` は `chatId.matches('^dm_u_[a-zA-Z0-9]+_u_[a-zA-Z0-9]+$')` による未作成時読み取りを許容します。
   - **クエリ一覧と単一取得の認可分離**: `tenants/{tenantId}/chats` コレクションに対する `whereField("members", arrayContains: userId)` クエリ（CP-01）を確実に動作させるため、親チャットの読み取りルールは `allow get`（ドキュメント単一取得・メンバー判定）と `allow list`（認証済みクエリ）に分離・定義します。
3. **オフライン同期と競合管理**:
   - Firestore SDK のローカルキャッシュ機能（Local Cache）を活用し、オフライン時のメッセージ送信はローカルキューに保持されます。
4. **ユーザー識別子 (`username`) の一意性インデックスと一覧取得禁止**:
   - `/tenants/{tenantId}/usernames/{username}` コレクションを設け、ドキュメントIDとして小文字化された `username` を配置します。
   - セキュリティルールにおいて、**新規作成のみを許可 (`allow create`)** し、作成時に `request.resource.data.uid == request.auth.uid` を検証して本人の UID を挿入・固定します。
   - **既存ドキュメントの更新は完全禁止 (`allow update: if false;`)** とし、ユーザー名の後勝ち上書きや改ざんを物理的に阻止します。
   - ユーザー名変更時は「新ユーザー名のドキュメント作成（`create`）＋ 旧ユーザー名のドキュメント削除（`delete`）」の排他処理とし、削除時は `resource.data.uid == request.auth.uid` により所有者本人のみ許可します。
   - **名簿スキャン防止**: `allow list: if false;` を強制し、指定ユーザーネームの存在確認および単一取得（`allow get: if isAuthenticated();`）のみを許可します。
5. **ユーザープロファイルの一覧取得制限（自身検索のみ許可）と表示名公開撤廃**:
   - `/tenants/{tenantId}/users/{userId}` に対する一覧取得は `allow list: if isAuthenticated() && resource.data.uid == request.auth.uid;` とし、自身以外の全件スキャンやスクレイピングを物理的に遮断しつつ、ログイン時や復元時の自身のプロファイル検索（`whereField("uid", isEqualTo: uid)`）を正当に許可します。
   - テナントマスターキー（$MK_T$）による `encryptedDisplayName` の公開プロファイル格納を完全撤廃し、対面（二次元コード直接）または30秒合言葉（TOTP）から導出した鍵（$K_{pass}$）で保護された一時データのみを許容します。
6. **インデックスの最適化**:
   - メッセージ取得クエリおよび `members` 配列を含むチャット一覧取得クエリ（`CP-01`）に必要な複合インデックス (Composite Indexes) を事前作成します。

---

## 4. 監査メタデータ規約と不変性制御 (Audit Metadata & Immutability)

セキュリティ、トレーサビリティ、およびなりすまし防止のため、Firestore に保存される全主要エンティティに対して統一された監査メタデータ規約を適用します。

### 4.1 監査フィールド定義
| フィールド名 | 型 | 説明 | 作成時規約 | 更新時規約 |
|:---|:---|:---|:---|:---|
| `createdBy` | `string` | 作成者のテナント内公開ID (`u_...`) | **必須**。現在の Auth UID に紐づく本人IDであることを検証。 | **完全不変（変更不可）** |
| `createdAt` | `timestamp` | ドキュメント初期作成日時 | **必須**。サーバー現在時刻 (`FieldValue.serverTimestamp()` == `request.time`) | **完全不変（変更不可）** |
| `updatedBy` | `string` | 最終更新者のテナント内公開ID (`u_...`) | **必須**。作成時は `createdBy == updatedBy` | **必須**。更新操作者本人の ID であることを検証 |
| `updatedAt` | `timestamp` | ドキュメント最終更新日時 | **必須**。サーバー現在時刻 (`FieldValue.serverTimestamp()` == `request.time`) | **必須**。サーバー現在時刻 (`request.time`) で更新 |

### 4.2 セキュリティルールによる強制仕様
- **新規作成 (`allow create`)**:
  ```javascript
  request.resource.data.keys().hasAll(['createdBy', 'createdAt', 'updatedBy', 'updatedAt'])
    && isTenantUser(tenantId, request.resource.data.createdBy)
    && request.resource.data.createdBy == request.resource.data.updatedBy
    && request.resource.data.createdAt == request.time
    && request.resource.data.updatedAt == request.time;
  ```
- **更新 (`allow update`)**:
  ```javascript
  !request.resource.data.diff(resource.data).affectedKeys().hasAny(['createdBy', 'createdAt'])
    && request.resource.data.keys().hasAll(['updatedBy', 'updatedAt'])
    && isTenantUser(tenantId, request.resource.data.updatedBy)
    && request.resource.data.updatedAt == request.time;
  ```

---

## 5. グループチャットのアクセス制御・ロール・削除ルール

### 5.1 メンバー属性とロール制御
- グループチャットドキュメント（`/tenants/{tenantId}/chats/{chatId}`）において、`chatType == "group"` の場合は各メンバーの属性として `memberRoles` マップ（`userId -> role`）を保持します。
- **ロール種別**:
  - `owner`: オーナー（1名のみ。脱退不可）
  - `admin`: 管理者（複数可。立候補型オーナー昇格権限）
  - `member`: 一般メンバー
- **オーナー・管理者による削除ルール**:
  - グループ削除は物理削除（`delete`）ではなく、`members: []`（空配列）への更新および `isDeleted: true` の付与による論理削除として実行します。
  - `members` を空に更新できる操作者は、変更前の `resource.data.memberRoles[request.auth.uid]` が `owner` または `admin` である場合に限定されます。
  - ルール検証ロジック例:
    ```javascript
    function isGroupOwnerOrAdmin(chatData) {
      let role = chatData.memberRoles[request.auth.uid];
      return role == 'owner' || role == 'admin';
    }

// 削除（membersクリア）更新の検証
    allow update: if isTenantUser(tenantId, request.resource.data.updatedBy)
      && (
        // 通常のメンバー・メッセージ更新
        (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['isDeleted', 'title']))
        ||
        // グループ名変更 (title更新: オーナーまたは管理者のみ)
        (isGroupOwnerOrAdmin(resource.data) && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['title', 'updatedBy', 'updatedAt']))
        ||
        // グループ削除（オーナーまたは管理者のみ）
        (isGroupOwnerOrAdmin(resource.data) && request.resource.data.members.size() == 0 && request.resource.data.isDeleted == true)
      );
    ```

### 5.2 グループ名の変更権限 (Group Title Update)
- グループチャットのタイトル（`title`）変更は、グループの改ざん・スパム防止のため**グループオーナー (`owner`) または グループ管理者 (`admin`)** に限定されます。
- セキュリティルール上、`title` が変更対象キーに含まれる場合は `isGroupOwnerOrAdmin` が真であることを必須とします。

---

## 6. アカウント削除ルール仕様 (Apple Guideline 5.1.1(v) 適合)

Apple 審査ガイドラインに基づき、利用者が自発的にアカウント消去を要求した場合、クライアント SDK から関連ドキュメントの物理削除を許可します。

### 6.1 各コレクションの削除認可
1. **全域ユーザー情報 (`/users/{uid}`)**:
   - `allow delete: if isUser(uid);`
   - 本人の認証トークン（Auth UID）と一致する場合のみ物理削除を許可。
2. **秘密鍵バックアップ領域 (`/users/{uid}/private/data`)**:
   - `allow delete: if isUser(uid);`
   - 本人のみバックアップデータの物理消去を許可。
3. **テナント内ユーザープロファイル (`/tenants/{tenantId}/users/{userId}`)**:
   - `allow delete: if isTenantUser(tenantId, userId);`
   - 当該テナントの所有者本人のみ物理削除を許可。
4. **ユーザーネーム予約インデックス (`/tenants/{tenantId}/usernames/{username}`)**:
   - `allow get: if isAuthenticated();` （単一検索・重複確認のみ許可）
   - `allow list: if false;` （名簿スキャン防止）
   - `allow create: if isAuthenticated() && request.resource.data.uid == request.auth.uid ...;` （新規作成のみ許可。本人の UID を必須挿入）
   - `allow update: if false;` （既存ドキュメントの上書き・更新は完全禁止）
   - `allow delete: if isAuthenticated() && resource.data.uid == request.auth.uid;` （所有者本人のみ削除・解放を許可）
5. **復旧ボルト (`/recovery_vault/{recoveryHash}`)**:
   - `allow read: if recoveryHash.size() == 64;`
   - 未ログイン端末から Cloudflare Workers REST API を経由した復元用レコード取得を許可（推測不可能な 64文字 SHA-256 ハッシュを暗号鍵として検証）。
   - `allow create, update: if isAuthenticated() && request.resource.data.uid == request.auth.uid ...;`
   - `allow delete: if isAuthenticated() && resource.data.uid == request.auth.uid;`
   - 復元用レコードの完全削除。






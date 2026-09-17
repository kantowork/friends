# 10-05: API 戦略分析：クライアント直接Firestore書き込み vs サーバーAPI

## 概要
クライアント側から Firestore への直接書き込みを検討する場合、各操作について以下の観点で分類します。

- **直接Firestore書き込み可能** (Client SDK + Security Rules で保護)
- **サーバーAPI必須** (認可判定・秘密鍵処理・リカバリ認証・複雑集計ロジック)

### 共通インタフェースの管理原則 (SSoT)
サーバーとクライアント間で共通となる REST API インタフェース定義は、TypeScript + Zod を真実の唯一のソース (SSoT) として **`shared/schema/*.ts`** にて一元管理します。
- **Zod スキーマ (SSoT)**: `shared/schema/`（`auth.ts`, `messages.ts`, `common.ts` 等）にてリクエスト/レスポンス構造、フィールド型、バリデーションルール、エラー構造を厳密に定義。
- **TypeScript (サーバー側)**: `shared/schema` から直接 `z.infer` による型注釈および `safeParse` によるランタイムバリデーションに利用。中間ディレクトリ（`shared/api/*`）等の二重生成は一切行わず完全排除。
- **Swift (クライアント側)**: `scripts/generate_api.mjs` により Zod スキーマと完全一致する型安全な Swift Codable モデル（`ios/Sources/Models/Generated/APISchemas.generated.swift`）を直接自動生成し、通信モデルの完全な型整合性を担保。
- **構成管理方針**: 中間ファイルとしての OpenAPI YAML や中間型定義はリポジトリ保持せず、`shared/schema/` から直接 Swift コードを生成（`npm run generate:models`）。自動生成コードはすべて `.gitignore` 対象とし、手動二重管理を完全に排除。

---

## API別分析

### 1. 認証関連

#### `POST /api/v1/auth/login` / `POST /api/v1/auth/login-anonymous`
- **判定**: **❌ 不要（Firebase Auth SDKを直接使用）**
- **理由**: Firebase Auth SDK がクライアント側で認証を完結させます。
- **操作**:
  - `signInWithEmailAndPassword()` または `signInAnonymously()` をクライアント側で実行

---

### 2. テナント情報取得

#### `GET /api/v1/tenants/:tenantId`
- **判定**: **✅ クライアント直接読み取り（Firestore Security Rules で保護）**
- **理由**: 公開情報（テナント ID、名前等）でテナント構成を確認するのみ。
- **Firestore パス**: `/tenants/{tenantId}`
- **実装**: Firestore SDK `doc(tenantId).get()`

---

### 3. メッセージ & 公開鍵関連

#### `GET /api/v1/users/:publicUserId/public-key`
- **判定**: **✅ クライアント直接読み取り（Security Rules で保護）**
- **理由**: テナント所属ユーザーの公開鍵は公開情報。
- **Firestore パス**: `/tenants/{tenantId}/users/{publicUserId}`
- **実装**: Firestore SDK `getDoc()`

#### `POST /api/v1/tenants/:tenantId/chats/:chatId/messages` (メッセージ送信)
- **判定**: **❌ サーバーAPI 必須 (Cloudflare Workers)**
- **理由**: 将来の FCM / APNs Push 通知連携の契機とするため、および送信時の検証・監査の一元化。暗号化はクライアント側で完結したまま、サーバーが Firestore への保存と通知ディスパッチを統制。
- **Firestore パス**: `/tenants/{tenantId}/chats/{chatId}/messages`
- **操作**:
  - クライアント側で共有セッションキー（`SK_direct` または `SK_group`）で暗号化
  - Firebase ID Token（`Authorization: Bearer`）と共に `POST /api/v1/tenants/:tenantId/chats/:chatId/messages` へ送信
  - サーバー（Workers）が ID Token を検証し、Firestore REST API で親チャットの更新・メッセージ作成を実行
- **リクエスト**:
  ```json
  {
    "message": {
      "messageId": "m_...",
      "tenantId": "t_...",
      "chatId": "dm_...",
      "senderId": "u_...",
      "keyVersion": "v_1",
      "encryptedPayload": { "ciphertext": "...", "nonce": "..." },
      "messageType": "text",
      "createdAt": 1726000000000
    },
    "members": ["u_...", "u_..."]
  }
  ```
- **Authorizer（認証・送信者評価）**:
  1. `Authorization: Bearer <ID_TOKEN>` の必須化。
  2. Google Identity Toolkit REST API (`accounts:lookup`) による Firebase ID Token の署名・有効期限・失効検証。無効時は `401 Unauthorized` を返却。
  3. 送信者評価: トークンから得られた認証済み `uid` と、メッセージの送信者 `senderId`（`/tenants/{tenantId}/users/{senderId}` の `uid` フィールド）の一致性を厳格に評価。不一致やなりすまし時は `403 Forbidden` を返却。
- **レスポンス**: `{ "success": true, "messageId": "m_...", "chatId": "...", "tenantId": "..." }`

#### `GET /api/v1/messages/:messageId`
- **判定**: **✅ クライアント直接読み取り（Security Rules で保護）**
- **理由**: 暗号化メッセージ。サーバーは復号不可。クライアント側で復号。
- **Firestore パス**: `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}`

---

### 4. 復旧関連 (ふっかつのじゅもん)

#### `POST /api/v1/auth/recover-anonymous` (匿名アカウント復旧)
- **判定**: **❌ サーバーAPI 必須 (Cloudflare Workers)**
- **理由**:
  1. クライアントローカルでふっかつのじゅもん（Mnemonic Phrase）から `recoveryHash = SHA256(K_recovery_id)` を導出
  2. Cloudflare Workers に `recoveryHash` を送信し、`/recovery_vault/{recoveryHash}` から一致するドキュメントを検索
  3. サーバーは平文フレーズや秘密鍵を一切受け取らず、ハッシュ検証のみ実行
  4. 一致した場合、Google サービスアカウントと Web Crypto API (RS256) により Firebase Custom Token を発行して返却
- **リクエスト**: `{ recoveryHash: "string" }`
- **レスポンス**: `{ uid: "string", customToken: "string", encryptedPrivateKey: "string", nonce: "string" }`

#### `POST /api/v1/devices/register` (新規デバイス登録)
- **判定**: **⚠️ ハイブリッド（Firestore 直接書き込み ＋ Security Rules）**
- **Firestore パス**: `/users/{uid}/devices/{deviceId}`

---

### 5. 監査関連

#### `GET /api/v1/audit/metadata` (テナント管理者向け監査ログ)
- **判定**: **❌ サーバーAPI 必須 (Cloudflare Workers)**
- **理由**:
  1. テナント管理者権限の厳格チェック
  2. メタデータの集計・フィルタリング・ページネーション
- **実装**: 専用 Cloudflare Workers エンドポイント

---

### 6. 友達管理関連

#### `POST /api/v1/friends/add` (友達追加リクエスト)
- **判定**: **✅ クライアント直接書き込み（Security Rules で保護）**
- **Firestore パス**: `/tenants/{tenantId}/friendRequests`

#### `POST /api/v1/friends/confirm` (友達追加確認)
- **判定**: **⚠️ トランザクション処理（Firestore Transactions で実現）**
- **実装**: クライアント側で `runTransaction()` を呼び出し、リクエスト削除と友達情報作成を原子的に実行

---

### 7. 外部通知連携

#### `POST /api/v1/external/notifications/send` (外部システムからのグループ宛通知)

- **判定**: **❌ サーバーAPI 必須 (Cloudflare Workers)**
- **理由**: 外部 API Key 認証、複数グループメンバーの抽出、FCM マルチキャスト送信。

---

## 結論：サーバー API が必須な操作一覧 (Cloudflare Workers 基盤)

| 操作 API | プラットフォーム | 理由 |
| :--- | :--- | :--- |
| `POST /api/v1/tenants/:tenantId/chats/:chatId/messages` | Cloudflare Workers | E2EE暗号化メッセージの保存・将来のPush通知（FCM/APNs）ディスパッチ |
| `POST /api/v1/auth/recover-anonymous` | Cloudflare Workers | 匿名アカウントの復旧ハッシュ検証・Firebase Custom Token 発行 |
| `GET /api/v1/tenants/:tenantId/audit/metadata` | Cloudflare Workers | テナント管理者認可・監査ログ集計 |
| `POST /api/v1/tenants/:tenantId/external/notifications/send` | Cloudflare Workers | 外部 API Key 認証・FCM 送信制御 |

---

## サーバー API インタフェース定義方針 (SSoT)

- **真実の唯一のソース (SSoT)**: `shared/schema/*.ts` (TypeScript + Zod)
- **利用および自動生成対象**:
  - **サーバー (TypeScript)**: `shared/schema` から直接 `z.infer` 型とスキーマをインポート（中間ディレクトリ `shared/api/*` は完全排除）
  - **クライアント (Swift)**: `scripts/generate_api.mjs` で `ios/Sources/Models/Generated/APISchemas.generated.swift` を直接自動生成
- **構成管理方針**:
  - 中間生成物となる OpenAPI YAML や中間型ファイルはリポジトリ保持せず、`shared/schema/` から直接 Swift コードを自動生成（`npm run generate:models`）。
  - 自動生成コードはすべて `.gitignore` 対象とし、手動編集を禁止。

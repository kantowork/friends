# 10-05: API 戦略分析：クライアント直接Firestore書き込み vs サーバーAPI

## 概要
クライアント側から Firestore への直接書き込みを検討する場合、各操作について以下の観点で分類します。

- **直接Firestore書き込み可能** (Client SDK + Security Rules で保護)
- **サーバーAPI必須** (認可判定・秘密鍵処理・リカバリ認証・複雑集計ロジック)

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

#### `POST /api/v1/messages` (メッセージ送信)
- **判定**: **✅ クライアント直接書き込み（Security Rules で保護）**
- **理由**: 暗号化はクライアント側で完結。サーバーはメッセージ内容を復号不可。
- **Firestore パス**: `/tenants/{tenantId}/chats/{chatId}/messages`
- **操作**: 
  - クライアント側で共有セッションキー（`SK_direct` または `SK_group`）で暗号化
  - `keyVersion` と `encryptedPayload` (`ciphertext`, `nonce`) を作成して書き込み
- **Security Rules**:
  ```javascript
  match /tenants/{tenantId}/chats/{chatId}/messages/{messageId} {
    allow create: if request.auth.uid == request.resource.data.senderId 
                  && isTenantMember(tenantId);
  }
  ```

#### `GET /api/v1/messages/:messageId`
- **判定**: **✅ クライアント直接読み取り（Security Rules で保護）**
- **理由**: 暗号化メッセージ。サーバーは復号不可。クライアント側で復号。
- **Firestore パス**: `/tenants/{tenantId}/chats/{chatId}/messages/{messageId}`

---

### 4. 復旧関連 (ふっかつのじゅもん)

#### `POST /api/v1/auth/recover-anonymous` (匿名アカウント復旧)
- **判定**: **❌ サーバーAPI 必須 (Cloud Function)**
- **理由**:
  1. クライアントローカルでふっかつのじゅもん（Mnemonic Phrase）から `recoveryHash = SHA256(K_recovery_id)` を導出
  2. サーバーに `recoveryHash` を送信し、`/users/{uid}/private/data` から一致するドキュメントを検索
  3. サーバーは平文フレーズや秘密鍵を一切受け取らず、ハッシュ検証のみ実行
  4. 一致した場合、Firebase Admin SDK により Custom Token を発行して返却
- **リクエスト**: `{ recoveryHash: "string" }`
- **レスポンス**: `{ uid: "string", customToken: "string", encryptedPrivateKey: "string", nonce: "string" }`

#### `POST /api/v1/devices/register` (新規デバイス登録)
- **判定**: **⚠️ ハイブリッド（Firestore 直接書き込み ＋ Security Rules）**
- **Firestore パス**: `/users/{uid}/devices/{deviceId}`

---

### 5. 監査関連

#### `GET /api/v1/audit/metadata` (テナント管理者向け監査ログ)
- **判定**: **❌ サーバーAPI 必須**
- **理由**:
  1. テナント管理者権限の厳格チェック
  2. メタデータの集計・フィルタリング・ページネーション
- **実装**: 専用 Cloud Function / サーバー API エンドポイント

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
- **判定**: **❌ サーバーAPI 必須**
- **理由**: 外部 API Key 認証、複数グループメンバーの抽出、FCM マルチキャスト送信。

---

## 結論：サーバー API が必須な操作一覧

| 操作 API | 理由 |
| :--- | :--- |
| `POST /api/v1/auth/recover-anonymous` | 匿名アカウントの復旧ハッシュ検証・Custom Token 発行 |
| `GET /api/v1/audit/metadata` | テナント管理者認可・監査ログ集計 |
| `POST /api/v1/external/notifications/send` | 外部 API Key 認証・FCM 送信制御 |

---

## Security Rules 設計例

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    
    function isAuthenticated() {
      return request.auth != null;
    }

    function isTenantMember(tenantId) {
      return isAuthenticated() && 
        exists(/databases/$(database)/documents/tenants/$(tenantId)/users/$(request.auth.uid));
    }

    // 1. 全域ユーザー情報
    match /users/{uid} {
      allow read: if isAuthenticated();
      allow create, update: if request.auth.uid == uid;

      // 復元データ（本人しかアクセス不可）
      match /private/data {
        allow read, write: if request.auth.uid == uid;
      }
    }
    
    // 2. テナント情報
    match /tenants/{tenantId} {
      allow read: if isAuthenticated();
      
      // テナント所属ユーザー情報
      match /users/{publicUserId} {
        allow read: if isTenantMember(tenantId);
        allow create, update: if isAuthenticated() && request.resource.data.uid == request.auth.uid;
      }
      
      // チャット（1:1 DM & グループ）
      match /chats/{chatId} {
        allow read: if isTenantMember(tenantId) && (
          request.auth.uid in resource.data.members || request.auth.token.role == 'tenant_admin'
        );

        match /messages/{messageId} {
          allow read: if isTenantMember(tenantId) && (
            resource.data.senderId == request.auth.uid ||
            request.auth.uid in get(/databases/$(database)/documents/tenants/$(tenantId)/chats/$(chatId)).data.members ||
            request.auth.token.role == 'tenant_admin'
          );
          
          allow create: if isTenantMember(tenantId) 
                         && request.resource.data.senderId == request.auth.uid
                         && request.resource.data.createdAt == request.time
                         && request.resource.data.keys().hasAll(['encryptedPayload', 'keyVersion']);
        }

        match /keys/{keyVersion} {
          allow read, create: if isTenantMember(tenantId) && request.auth.uid in get(/databases/$(database)/documents/tenants/$(tenantId)/chats/$(chatId)).data.members;
        }
      }
    }
  }
}
```

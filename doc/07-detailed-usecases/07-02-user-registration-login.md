# 07-02: ユーザー登録・初回ログインと暗号鍵生成仕様

ロバストネス分析 #3 およびコア機能要件（E2EEおよびアカウント体系）に対応する詳細設計書です。
初回ログイン時（ユーザー作成時）における暗号鍵ペア（Curve25519）の自動生成、端末内 Keychain への秘密鍵安全保持、ならびに Cloud Firestore への公開鍵配置プロトコルを定義します。

---

## 1. 初回ログイン・ユーザー作成シーケンス

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant UI as "UI Layer (LoginView / SplashView)"
    participant AuthController as "Auth / ChatService"
    participant CryptoService as "CryptoService (CryptoKit)"
    participant Keychain as "Secure Storage (Keychain)"
    participant FirebaseAuth as "Firebase Auth"
    participant Firestore as "Cloud Firestore"

    User->>UI: 認証方法選択（匿名開始 / メールログイン / 登録）
    UI->>AuthController: authenticate(credentials, tenantId, displayName)
    AuthController->>FirebaseAuth: ログイン / サインアップ実行

    alt 認証成功
        FirebaseAuth-->>AuthController: Auth UID (uid), idToken
        
        Note over AuthController,Keychain: 🔐 1. ユーザー暗号鍵ペア (Curve25519) 初期化
        AuthController->>Keychain: getExistingKeypair(uid)
        
        alt Keychain に秘密鍵が存在しない場合 (初回登録時)
            AuthController->>CryptoService: generateCurve25519Keypair()
            CryptoService-->>AuthController: PrivateKey (SK_u), PublicKey (PK_u)
            AuthController->>Keychain: savePrivateKey(uid, SK_u), savePublicKey(uid, PK_u)
        else 既存鍵が存在する場合
            Keychain-->>AuthController: SK_u, PK_u
        end

        Note over AuthController,Keychain: 🔐 2. テナントマスターキー (MK_T) で表示名を暗号化
        AuthController->>Keychain: getTenantMasterKey(tenantId)
        Keychain-->>AuthController: SymmetricKey (MK_T)
        AuthController->>CryptoService: encryptWithTenantKey(displayName, tenantId)
        CryptoService-->>AuthController: encryptedDisplayName, displayNameNonce

        Note over AuthController,Firestore: 🌐 3. Firestore へ公開鍵と暗号化プロファイル配置 (平文非保持)
        AuthController->>Firestore: /tenants/{tenantId}/users/{userId} に encryptedDisplayName, Nonce, PK_u を保存
        AuthController->>Firestore: /users/{uid} に PK_u, defaultTenantId を保存 (平文 displayName は保存しない)
        Firestore-->>AuthController: Write Success

        AuthController->>UI: ログイン完了 & メイン画面遷移
    else 認証失敗
        FirebaseAuth-->>AuthController: 認証エラー
        AuthController->>UI: エラーダイアログ表示
    end
```

---

## 2. 鍵生成・保管仕様

### 2.1 アルゴリズム
- **端末鍵ペア**: Curve25519 (X25519) 非対称鍵ペア
- **生成ライブラリ**: Apple `CryptoKit` (`Curve25519.KeyAgreement.PrivateKey()`)
- **データ表現**: 32 バイト生データ (Raw Representation) を Base64 エンコードした文字列
- **表示名暗号化**: テナントマスターキー ($MK_T$) による **AES-256-GCM 暗号化** (12 バイト Nonce + 16 バイト認証タグ)

### 2.2 ローカル保持 (iOS Keychain)
秘密鍵およびテナントマスターキーは端末のセキュアストレージ（iOS Keychain）に厳密に保管し、クラウドやサーバーへ平文で送信することは固く禁止します。

| キー名 | 格納先 | アクセシビリティ属性 | 説明 |
|:---|:---|:---|:---|
| `friends_priv_key_{uid}` | iOS Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ユーザー端末秘密鍵 ($SK_u$) |
| `friends_pub_key_{uid}` | iOS Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | ユーザー端末公開鍵 ($PK_u$) |
| `friends_tenant_key_{tenantId}` | iOS Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | テナントマスターキー ($MK_T$) |

### 2.3 データベース配置 (Cloud Firestore)
公開鍵 ($PK_u$) および暗号化されたプロファイルのみを Firestore 上に配置します。**平文の `displayName` は DB 上に保存されません。**

1. **テナント所属ユーザー情報**: `/tenants/{tenantId}/users/{userId}`
   ```json
   {
     "userId": "u_12345678",
     "uid": "firebase_auth_uid_abc",
     "tenantId": "t_kanto_corp",
     "encryptedDisplayName": "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA...",
     "displayNameNonce": "MDEyMzQ1Njc4OWFi",
     "publicKey": "X25519_Base64Encoded_PublicKey_32bytes==",
     "role": 1,
     "accountType": 1,
     "updatedAt": "2026-08-27T00:00:00Z"
   }
   ```
2. **全域ユーザー情報**: `/users/{uid}`
   ```json
   {
     "uid": "firebase_auth_uid_abc",
     "publicKey": "X25519_Base64Encoded_PublicKey_32bytes==",
     "defaultTenantId": "t_kanto_corp",
     "updatedAt": "2026-08-27T00:00:00Z"
   }
   ```

---

## 3. ローカル管理と Firestore 管理の区分

- **ローカル管理 (Secure Storage / Keychain)**:
  - 秘密鍵 ($SK_u$)
  - テナントマスターキー ($MK_T$)
  - 復活の呪文、復旧用派生キー ($K_{priv\_enc}$)
  - DM・グループセッションキー ($SK_{direct}$, $SK_{group}$)
- **Firestore 管理**:
  - 公開鍵 ($PK_u$)
  - 暗号化プロファイル (`encryptedDisplayName`, `displayNameNonce`)
  - 認可・ルーティング用平文メタデータ (`role`, `accountType`, `tenantId`, `userId`, `uid`, `updatedAt`)
  - 友達リスト、会話メタデータ、暗号化メッセージ本文 (`encryptedPayload`)

> ユーザー個人の秘密鍵、テナントマスターキー、平文の氏名・表示名はサーバー・DB 上に一切保存されず、暗号化データと公開鍵・認可メタデータのみが保持されます。

---

## 4. 端末データ・Keychain 完全消去仕様 (Device Reset & Sign Out)

シミュレーター環境や端末引き継ぎ時、またはログアウト時において、Keychain に残留した古い秘密鍵 ($SK_u$) やテナントマスターキー ($MK_T$) による誤復号・不整合を完全に防止するため、以下の消去プロトコルを提供します：

1. **消去対象**:
   - `work.kanto.friends.keys` サービス名で Keychain に登録されたすべての項目 (`kSecClassGenericPassword`, `kSecClassKey` 等)
   - メモリ上のセッションキャッシュ (`directSessionKeys`, `messages`, `friends`, `chats`, `currentUser`)
   - Firebase Auth セッション (`Auth.auth().signOut()`)
2. **実行トリガー**:
   - **設定画面 (E01)**: 「ログアウト」実行時（ユーザー確認アラートを経て自動実行）
   - **ログイン画面 (A02)**: 「端末データ・鍵の完全リセット」ボタン押下時（未ログイン状態からでもクリーンリセット可能）

---

## 5. エラーハンドリング

| エラー | 原因 | 対応方針 |
|:---|:---|:---|
| `KEY_GENERATION_FAILED` | CryptoKit による鍵生成例外 | リトライおよびユーザーへ再試行通知 |
| `KEYCHAIN_STORE_FAILED` | Keychain 書き込み権限または容量エラー | エラーコードを記録しリカバリ |
| `FIRESTORE_WRITE_FAILED` | ネットワーク接続不良またはパーミッション | リトライキューへ投入し再接続時に同期 |

---

## 5. 多言語対応 (i18n)

- 認証フローおよび鍵初期化に関わるすべての文言・エラーメッセージは `L10n` を通じて `auth.*` / `error.auth.*` のドット記法キーで管理します。

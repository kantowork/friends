# 10-01: テナント共通鍵（$MK_T$）によるテナント内データ暗号化仕様書

本ドキュメントは、**Friends** におけるテナント（組織）共通鍵（テナントマスターキー: $MK_T$）を用いた、`/tenants/{tenantId}` 配下データの暗号化方針および暗号化・復号プロトコルを定義する詳細設計書です。

---

## 1. 暗号化すべきデータの方針 (Data Encryption Policy)

### 1.1 背景と目的
Cloud Firestore 上に保存されるデータのうち、テナント組織内のプライバシー（氏名、グループ名等）に関わる機密情報は、**データベース管理者や外部攻撃者に対しても平文を秘匿**しなければなりません。
正当な手段（テナント参加QRコードや招待JSON）でテナントに参加し、テナントマスターキー（$MK_T$）を取得した端末のみが内容を復号・閲覧できるように設計します。

### 1.2 フィールド別 暗号化 / 平文保持 区分基準

| カテゴリ | フィールド名 | 保管形式 | 理由 / 役割 |
|:---|:---|:---|:---|
| **暗号化対象** ($MK_T$) | `tenantName` (テナント表示名) | **AES-256-GCM 暗号化** (`encryptedTenantName`, `nonce`) | 組織・企業名をクラウド上で秘匿 |
| **暗号化対象** ($MK_T$) | `displayName` (表示名) | **AES-256-GCM 暗号化** (`encryptedDisplayName`, `nonce`) | ユーザー個人の氏名・ニックネームをクラウド上で秘匿 |
| **暗号化対象** ($MK_T$) | `groupName` (グループ名) | **AES-256-GCM 暗号化** (`encryptedGroupName`, `nonce`) | 組織内の機密プロジェクト名・部署名を秘匿 |
| **暗号化対象** ($MK_T$) | `description` (グループ説明) | **AES-256-GCM 暗号化** (`encryptedDescription`, `nonce`) | 組織内の業務詳細・説明を秘匿 |
| **暗号化対象** ($MK_T$) | カスタムステータス・アバターURL | **AES-256-GCM 暗号化** | プライベートなプロファイルメタデータを秘匿 |
| **平文保持** | `tenantId`, `tenantCode` | **平文** | ルーティング、ドキュメントパス、Firestore クエリに必須 |
| **平文保持** | `userId`, `uid`, `groupId`, `chatId` | **平文** | ルーティング、ドキュメントパス、Firestore クエリに必須 |
| **平文保持** | `publicKey` (X25519 Base64) | **平文** | ユーザー公開鍵（$PK_u$）。E2EE メッセージ通信および友達追加時の ECDH 鍵導出に必須（※テナント鍵は保持しない） |
| **平文保持** | `role`, `accountType`, `isDefaultTenant` | **平文** | Firestore セキュリティルール（認可・アクセス制御）での判定に必須 |
| **平文保持** | `createdAt`, `updatedAt` | **平文** | Firestore 上でのタイムスタンプソートおよび同期クエリに必須 |

---

## 2. テナントマスターキー ($MK_T$) 仕様 & 配布・保管

### 2.1 鍵仕様
- **暗号アルゴリズム**: AES-256-GCM (対称鍵 256-bit / 32バイト)
- **Nonce (IV)**: 暗号化ごとに暗号学的に安全な乱数で生成される 12 バイト (`AES.GCM.Nonce`)
- **暗号化出力**: 暗号文 + 16 バイト認証タグ (Combined Data) の Base64 文字列

### 2.2 配布プロトコル (テナント参加)
- テナント管理者が発行する **参加用 QR コード** または **招待 JSON** に $MK_T$ (Base64) を含めて利用者に配布します。
- QR コードペイロード例:
  ```json
  FRIENDS_TENANT:{
    "type": "tenant_invite",
    "version": 1,
    "tenantId": "t_kanto_corp",
    "tenantCode": "kanto-tech",
    "tenantName": "関東テクノロジー",
    "tenantMasterKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    "isDefaultTenant": true
  }
  ```

### 2.3 端末内保管 (iOS Keychain)
$MK_T$ は端末のセキュア領域（iOS Keychain）に保管され、サーバー上に平文で保存されることはありません。

| キー名 | 格納先 | アクセシビリティ属性 |
|:---|:---|:---|
| `friends_tenant_key_{tenantId}` | iOS Keychain | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |

---

## 3. Firestore 格納スキーマ
 
### 3.0 テナント情報 (`/tenants/{tenantId}`)

```json
{
  "tenantId": "t_kanto_corp",
  "tenantCode": "kanto-tech",
  "encryptedTenantName": "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA...",
  "tenantNameNonce": "MDEyMzQ1Njc4OWFi",
  "isDefaultTenant": true,
  "createdAt": "2026-08-27T00:00:00Z"
}
```

### 3.1 ユーザープロファイル (`/tenants/{tenantId}/users/{userId}`)

```json
{
  "userId": "u_12345678",
  "uid": "firebase_auth_uid_abc",
  "tenantId": "t_kanto_corp",
  "encryptedDisplayName": "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA...",
  "displayNameNonce": "MDEyMzQ1Njc4OWFi",
  "publicKey": "dGVzdFB1YmxpY0tleU1vY2szMmJ5dGVzQmFzZTY0PT0=",
  "role": 1,
  "accountType": 1,
  "updatedAt": "2026-08-27T00:00:00Z"
}
```

### 3.2 チャット/グループ情報 (`/tenants/{tenantId}/chats/{chatId}`)

```json
{
  "chatId": "gm_sales_dept",
  "tenantId": "t_kanto_corp",
  "chatType": "group",
  "encryptedTitle": "base64EncodedTitle...",
  "titleNonce": "base64EncodedNonce...",
  "members": ["u_alice", "u_bob"],
  "createdAt": "2026-08-27T00:00:00Z",
  "updatedAt": "2026-08-27T00:00:00Z"
}
```

---

## 4. 暗号化・復号シーケンス図

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as "iOS App (ChatService)"
    participant CryptoKeyManager as "CryptoKeyManager (CryptoKit)"
    participant Keychain as "iOS Keychain"
    participant Firestore as "Cloud Firestore"

    Note over User,Firestore: 📝 1. ユーザープロファイル保存 (暗号化)
    App->>Keychain: getTenantMasterKey(tenantId)
    Keychain-->>App: SymmetricKey (MK_T)
    App->>CryptoKeyManager: encryptWithTenantKey("アリス", tenantId)
    CryptoKeyManager->>CryptoKeyManager: AES.GCM.seal("アリス", using: MK_T)
    CryptoKeyManager-->>App: encryptedDisplayName, displayNameNonce
    App->>Firestore: /tenants/{tenantId}/users/{userId} に保存 (暗号文 + Nonce)

    Note over User,Firestore: 📖 2. ユーザー一覧・プロファイル取得 (復号)
    Firestore-->>App: Snapshot (encryptedDisplayName, displayNameNonce)
    App->>CryptoKeyManager: decryptWithTenantKey(encryptedDisplayName, nonce, tenantId)
    CryptoKeyManager->>CryptoKeyManager: AES.GCM.open(sealedBox, using: MK_T)
    CryptoKeyManager-->>App: PlainText "アリス"
    App->>User: UI 上に "アリス" を表示
```

---

## 5. 平文非保持原則と鍵未所持時の挙動

1. **平文非保持の徹底（Clean Start 原則）**:
   - 既存データの移行期間や旧形式との混在は行わず、すべての機密フィールド（`tenantName`, `displayName`, `groupName`, `description`）は初回保存時から $MK_T$ による AES-256-GCM 暗号文および Nonce のみとして Firestore に格納します。平文カラムは DB 上に保持されません。
2. **$MK_T$ 未所持・未認証時の挙動**:
   - テナントキーが未取り込みの端末では復号に失敗するため、表示名にはフォールバック表記（テナント: `@tenantCode`、ユーザー: `[未復号ユーザー]`）を表示し、安全性を担保します。

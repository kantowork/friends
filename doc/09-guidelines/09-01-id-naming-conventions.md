# 09-01: ID プレフィックス命名規約仕様書 (ID Naming Conventions)

本ドキュメントは、**Friends** アプリにおける各種エンティティ ID（一意識別子）のプレフィックス命名規約を定義します。システム内のデータ種別を型安全かつ直感的に識別可能にし、データベースログや通信パケット解析時の誤認を防止することを目的とします。

---

## 1. プレフィックス一覧および命名ルール

すべてのプライマリキーおよび識別子は、原則として以下のプレフィックス規約を適用した英数字文字列として生成・管理します。

| ドメイン領域 | エンティティ名 | プレフィックス / 形式 | ID 例 | 適用場所 | 変更可否 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ユーザー・アカウント** | 全域ユーザー UID (認証ID) | *(なし)* | `abc123xyz` | Firebase Auth 標準 UID / `/users/{uid}` | 不可 (非公開) |
| | ユーザー識別子 (公開不変ID) | `u_` + Base58(UUID) (最大22文字) | `u_2tJqQ6rVw8zY1...` | `/tenants/{tenantId}/users/{userId}` | 不可 (システム不変キー) |
| | ユーザー名 (username) | `^[a-zA-Z0-9_]{3,20}$` | `alice_dev` | `/tenants/{tenantId}/usernames/{username}` | **変更可能 (ユーザー表示用)** |
| **チャット・会話** | ダイレクトメッセージ (1:1 DM) | `dm_` | `dm_u_alice_u_bob` | `/tenants/{tenantId}/chats/{chatId}` (`chatType: "direct"`) | 不可 |
| | グループチャット | `gm_` | `gm_sales_team` | `/tenants/{tenantId}/chats/{chatId}` (`chatType: "group"`) | 不可 |
| | 暗号化メッセージ | `m_` | `m_01J6G7R8N9Y96S8W3A1V2B4C5D` | `/chats/{chatId}/messages/{messageId}` | 不可 |
| | 鍵バージョン | `v_` | `v_1`, `v_2` | `/chats/{chatId}/keys/{keyVersion}` | 不可 |
| **テナント・組織** | テナント (組織) | `t_` | `t_kanto_corp` | `/tenants/{tenantId}` | 不可 |
| | 組織グループ | `g_` | `g_dev_dept` | テナント内の所属グループ ID | 不可 |
| **デバイス・インフラ** | デバイス | `d_` | `d_ios_iphone15` | `/users/{uid}/devices/{deviceId}` | 不可 |
| **友達・招待ペイロード** | 友達追加QR/文字列ペイロード | `FRIENDS_USER:` | `FRIENDS_USER:eyJ0eX...` | QRコード / クリップボード共有 | - |
| | テナント招待QRペイロード | `FRIENDS_TENANT:` | `FRIENDS_TENANT:eyJ0...` | テナントQRコード | - |

---

## 2. 実装ガイドライン

1. **生成ルール**:
   - クライアントおよびサーバー側で ID を生成・指定する際、対応するプレフィックスを必ず付与します。
   - **ユーザー識別子 (`u_`) の Base58(UUID) 採用仕様**:
     - ユーザー識別子には UUID (16バイト) を Base58 エンコードした文字列（最大 22 文字）を採用し、`u_<Base58>` とします。
     - **メリット**:
       1. Base64 のような `+`, `/`, `=` などの URL / QRコード / DB で特殊扱いされる記号を含まず、英数字のみで安全に表現。
       2. UUID の 128bit の一意性を保ちながら、16進数表記 (36文字) より短い最大22文字に圧縮。
     - **依存ライブラリ**:
       - Swift: `https://github.com/keefertaylor/Base58Swift.git` (`import Base58Swift`)

   - **暗号化メッセージ ID (`m_`) の ULID 採用仕様**:
     - メッセージ ID には時系列ソート可能な **ULID (Universally Unique Lexicographically Sortable Identifier)** を採用し、`m_<ULID>` (例: `m_01J6G7R8N9Y96S8W3A1V2B4C5D`) とします。
     - **メリット**:
       1. Firestore ドキュメント ID 順（`FieldPath.documentID()`）で自然に時系列ソートが可能となり、`createdAt` への複合インデックスコストを削減。
       2. 高速かつ曖昧さのないカーソルベースページネーション（`startAfter(doc.documentID)`）を実現。
       3. Swift / クライアント端末側のローカル配列や SQLite でも辞書順（文字列比較）で低コストに時系列ソート・マージが可能。
     - **依存ライブラリ**:
       - Swift: `https://github.com/yaslab/ULID.swift.git` (`import ULID`)
       - Node.js / TypeScript: `ulid` パッケージ (`import { ulid } from 'ulid'`)

   - 例 (Swift / TypeScript):
     ```swift
     // Swift:
     import ULID
     import Base58Swift

     public func generateUserId() -> String {
         let uuid = UUID()
         let uuidBytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
         return "u_\(Base58.base58Encode(uuidBytes))"
     }

     public func generateMessageId() -> String {
         return "m_\(ULID().ulidString)"
     }
     ```
     ```typescript
     // TypeScript:
     import { ulid } from 'ulid';
     import bs58 from 'bs58';
     import { v4 as uuidv4, parse as parseUuid } from 'uuid';

     // ユーザー識別子 (Base58 UUID)
     export const generateUserId = () => `u_${bs58.encode(parseUuid(uuidv4()))}`;

     // 暗号化メッセージ ID (ULID)
     export const generateMessageId = () => `m_${ulid()}`;

     // テナント内公開ユーザー ID
     export const generatePublicUserId = () => `u_${nanoid(16)}`;

     // 1:1 DM チャット ID
     export const generateDirectChatId = (uidA: string, uidB: string) => {
       const sorted = [uidA, uidB].sort();
       return `dm_${sorted[0]}_${sorted[1]}`;
     };

     // グループチャット ID
     export const generateGroupChatId = () => `gm_${nanoid(16)}`;

     // 鍵バージョン ID
     export const generateKeyVersionId = (ver: number) => `v_${ver}`;

     // テナント ID
     export const generateTenantId = () => `t_${nanoid(12)}`;

     // 組織グループ ID
     export const generateGroupId = () => `g_${nanoid(12)}`;

     // デバイス ID
     export const generateDeviceId = () => `d_${nanoid(16)}`;
     ```

2. **Firestore Security Rules でのフォーマット検証**:
   - セキュリティルールにおいて、`chatId` や `messageId` のプレフィックスチェックを行うことができます。
     ```javascript
     function isDirectChat(chatId) {
       return chatId.matches('^dm_.*');
     }
     function isGroupChat(chatId) {
       return chatId.matches('^gm_.*');
     }
     function isValidMessageId(messageId) {
       return messageId.matches('^m_.*');
     }
     ```

# 07-12: グループチャット詳細設計書（かいぎ）

本ドキュメントは、**Friends** アプリケーションにおけるグループチャット（タブ名：「かいぎ」 / Groups）の機能要件、画面遷移、E2EE 暗号化通信プロトコル、およびデータ構造を定義した詳細設計書です。

---

## 1. 概要 & 目的

グループチャット（「かいぎ」）機能は、同一組織（テナント）内の複数ユーザーがリアルタイムにメッセージ、リアクション、既読確認をセキュアに行うためのコラボレーション基盤です。

### 主要機能
1. **グループチャット一覧（D01 / タブ名: 「かいぎ」）**: 参加しているグループチャットの一覧表示、最新メッセージ・更新日時のプレビュー、未読バッジ表示。
2. **新規グループ作成（D03）**: グループ名の入力、友達一覧からの複数メンバー選択によるグループの新規開設。
3. **グループチャット詳細（D02 / 既存 C02 拡張）**: 複数人での E2EE 暗号化メッセージ送受信、送信者アイコン・名前表示、リアクション、既読カウント。
4. **グループ詳細 & メンバー管理（D04, D05m）**: グループ名・参加メンバー一覧の確認および追加メンバーの招待。

---

## 2. 鍵体系 & E2EE 暗号化プロトコル (前方秘匿性 / Forward Secrecy 対応)

グループチャットにおける E2EE 通信は、[07-03: テキストメッセージ送信・暗号化詳細設計書](07-03-message-encryption.md) および [10-01: テナント暗号設計](10-detailed-design/10-01-tenant-data-encryption.md) に規定された **グループ会話共有鍵バケット (`KeyBucket` / $SK_{group, v}$) 方式** に準拠します。

### 2.1 共有鍵バージョニング & 配布プロトコル
1. **鍵生成 & 配布 (`KeyBucket` / `v_1`, `v_2`, ...)**:
   - グループ作成時またはメンバー増減（追加・除外）時に、暗号論的擬似乱数により 256-bit のグループ会話鍵 $SK_{group, v}$ を生成。
   - 作成者は各メンバーの公開鍵 $PK_{u}$ を用いて $SK_{group, v}$ を個別暗号化し、`/tenants/{tenantId}/chats/{chatId}/keys/{keyVersion}` の `encryptedGroupKeys` マップに格納：
     $$\text{encryptedGroupKeys}[u_i] = \text{Encrypt}(PK_{u_i}, SK_{group, v})$$
   - メンバー除外時は新規バージョン $v_{k+1}$ を発行することで、除外されたユーザーが以降のメッセージを復号できない **前方秘匿性 (Forward Secrecy)** を担保します。
   - 過去バージョンの `KeyBucket`（$v_1, \dots, v_k$）も Firestore に保持されるため、過去のメッセージもメッセージの `keyVersion` に応じた鍵で過去ログ復号可能です。

2. **暗号化送信**:
   - 送信端末は最新バージョンのグループ会話鍵 $SK_{group, v}$（またはフォールバックとして $MK_T$）を用いてメッセージ本文を AES-256-GCM 暗号化。
     $$\text{CiphertextPayload} = \text{AES-256-GCM-Encrypt}(SK_{group, v}, \text{Plaintext}, \text{Nonce})$$
   - メッセージには `keyVersion: "v_1"` 等のバージョン情報を付与して Firestore に保存。

3. **受信・復号**:
   - 受信端末はメッセージの `keyVersion` に応じた $SK_{group, v}$ をローカルキャッシュまたは `KeyBucket` から復号して取得し、メッセージを平文へ復号。

---

## 3. データ構造 (Firestore)

### 3.1 チャットドキュメント (`/tenants/{tenantId}/chats/{chatId}`)
```json
{
  "chatId": "gm_01J6XYZ1234567890ABCDEF",
  "tenantId": "t_corp_abc",
  "chatType": "group",
  "title": "プロジェクト推進会",
  "members": [
    "u_01J6XYZ_ALICE",
    "u_01J6XYZ_BOB",
    "u_01J6XYZ_CHARLIE"
  ],
  "latestKeyVersion": "v_1",
  "lastMessage": "次回の会議は明日10時からです",
  "lastMessageAt": "2026-08-30T22:50:00Z",
  "createdAt": "2026-08-30T20:00:00Z",
  "updatedAt": "2026-08-30T22:50:00Z"
}
```

### 3.2 グループ鍵バケット (`/tenants/{tenantId}/chats/{chatId}/keys/{keyVersion}`)
```json
{
  "keyVersion": "v_1",
  "chatId": "gm_01J6XYZ1234567890ABCDEF",
  "tenantId": "t_corp_abc",
  "encryptedGroupKeys": {
    "u_01J6XYZ_ALICE": "base64EncodedEncryptedSKGroupForAlice...",
    "u_01J6XYZ_BOB": "base64EncodedEncryptedSKGroupForBob...",
    "u_01J6XYZ_CHARLIE": "base64EncodedEncryptedSKGroupForCharlie..."
  },
  "createdAt": "2026-08-30T20:00:00Z"
}
```

### 3.3 メッセージドキュメント (`/tenants/{tenantId}/chats/{chatId}/messages/{messageId}`)
```json
{
  "messageId": "m_01J6XYZ9876543210FEDCBA",
  "tenantId": "t_corp_abc",
  "chatId": "gm_01J6XYZ1234567890ABCDEF",
  "senderId": "u_01J6XYZ_ALICE",
  "keyVersion": "v_1",
  "encryptedPayload": {
    "ciphertext": "base64EncodedGroupCiphertext...",
    "nonce": "base64EncodedNonce..."
  },
  "messageType": "text",
  "createdAt": "2026-08-30T22:50:00Z",
  "reactionCounts": {
    "thumbs_up": 2,
    "ok": 1
  }
}
```

---

## 4. シーケンス図

### 4.1 新規グループチャット作成 & KeyBucket 初期化 (D03)

```mermaid
sequenceDiagram
    actor Creator as "作成者 (Alice: u_alice)"
    participant View as "CreateGroupView"
    participant Service as "ChatService"
    participant Crypto as "CryptoKeyManager"
    participant Repo as "ChatRepository / KeyBucketRepository"
    participant Firestore as "Cloud Firestore"

    Creator->>View: グループ名入力 & 友達メンバー選択 (u_bob, u_charlie)
    Creator->>View: 「作成」ボタンタップ
    View->>Service: createGroup(title, memberUserIds)
    Service->>Crypto: generateGroupKey(chatId, version: "v_1")
    Service->>Crypto: encryptGroupKeyForMembers(SK_group, memberPublicKeys)
    Service->>Repo: createGroupChatWithKeyBucket(tenantId, chatId, title, members, keyBucket)
    Repo->>Firestore: 1) /tenants/{tenantId}/chats/{chatId} を作成 (members: [u_alice, u_bob, ...])
    Repo->>Firestore: 2) /tenants/{tenantId}/chats/{chatId}/keys/v_1 を保存
    Firestore-->>Repo: 完了通知
    Repo-->>Service: Success
    Service->>Service: 参加グループ一覧を即時更新
    Service-->>View: 完了
    View-->>Creator: 画面を閉じて作成したグループチャットへ遷移
```

---

## 5. UI/UX 仕様

1. **タブナビゲーション**:
   - タブアイコン: `person.3.fill` / タブ名: 「かいぎ」
   - グループチャット内の未読合計件数をバッジとして表示。
2. **グループ一覧（D01）**:
   - グループアイコン（グラデーション背景＋頭文字または複数人アバター）
   - グループ名、最新メッセージ本文（復号済み）、最新受信時刻
   - 未読件数バッジ（青丸に白文字）
   - ナビゲーションバー右上に新規作成ボタン（`+` アイコン）
3. **新規グループ作成（D03）**:
   - モーダル/シート表示
   - グループ名入力フィールド（クリアボタン付き）
   - メンバー選択（登録済み友達一覧の複数チェックボックス、`userId: u_...` 基準）
   - ナビゲーションバー右上に「作成」ボタン（グループ名未入力時は非活性）
4. **グループ詳細 & メンバー管理（D04）**:
   - チャット詳細のナビゲーションバー右上にあるインフォボタン（`info.circle`）から遷移
   - グループ名、作成日、参加メンバー一覧（表示名、アバター、自分バッジ）の表示

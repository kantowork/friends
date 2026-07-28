# 07-11: メッセージリアクション（Message Reactions）仕様書

本ドキュメントは、**Friends** におけるメッセージリアクション機能のアーキテクチャ、Firestore パス構造、データモデル、セキュリティルール、通信量低減集計仕様および UI 表示設計を定義する詳細設計書です。

---

## 1. リアクション機能の基本方針

### 1.1 提供リアクション種別（7種類）
ユーザーが直感的に感情・意思を表明できるよう、以下の 7 種類のリアクションを提供します。

| 識別子 (enum / key) | 絵文字 | 日本語名 | 英語名 | 用途・ニュアンス |
|:---|:---|:---|:---|:---|
| `thumbs_up` | 👍 | サムズアップ | Thumbs Up | 了解、賛成、いいね |
| `heart` | ❤️ | ハート | Heart | 感謝、共感、愛着 |
| `ok` | 🆗 | OK | OK | 承知、OK |
| `smile` | 😊 | スマイル | Smile | 笑顔、嬉しい、親しみ |
| `surprised` | 😲 | びっくり | Surprised | 驚き、意外 |
| `sad` | 😢 | かなしい | Sad | 悲しい、残念 |
| `thinking` | 🤔 | 考え中 | Thinking | 検討中、疑問、熟考 |

### 1.2 リアクション付与・更新ルール
- **1ユーザー1リアクション**: 1つのメッセージに対して各ユーザーは最大1つのリアクションを保持できます。
- **トグル・切り替え動作**:
  - 同じリアクションを再度タップ: リアクションを**解除（削除）**
  - 別のリアクションをタップ: 新しいリアクションに**切り替え（上書き）**

### 1.3 通信量低減（Traffic Optimization）方針
大規模なグループチャットにおいて、各リアクションの全ユーザー情報を常時リッスンするとクライアントの通信量および Firestore 読み取りコストが増大します。そのため以下のハイブリッド方式を採用します：
1. **チャット詳細画面（常時同期）**:
   - メッセージドキュメント (`messages/{messageId}`) に `reactionCounts: map<string, int32>` を保持。
   - クライアントは集計件数（例: 👍 5, ❤️ 2）のみを表示し、不要なサブコレクション購読を行わない。
2. **リアクション詳細画面（オンデマンド取得）**:
   - ユーザーがメッセージを長押し、またはリアクションバッジをタップした際にのみ、該当メッセージの `/reactions` サブコレクションを取得して「誰がどのリアクションをしたか」を表示。

---

## 2. データ構造・スキーマ設計 (Protobuf & Firestore)

### 2.1 Firestore パス構造

```text
/tenants/{tenantId}/chats/{chatId}/messages/{messageId}
  ├── (Field) reactionCounts: { "thumbs_up": 2, "heart": 1, ... }
  └── reactions/{userId}  (サブコレクション: 詳細管理)
        ├── userId: "u_xxx"
        ├── userName: "表示名"
        ├── reactionType: "thumbs_up"
        ├── createdAt: Timestamp
        └── updatedAt: Timestamp
```

### 2.2 Proto3 定義 (`shared/model/message.proto`)

```protobuf
// リアクション種別
enum ReactionType {
  REACTION_TYPE_UNSPECIFIED = 0;
  REACTION_TYPE_THUMBS_UP = 1;   // 👍
  REACTION_TYPE_HEART = 2;       // ❤️
  REACTION_TYPE_OK = 3;          // 🆗
  REACTION_TYPE_SMILE = 4;       // 😊
  REACTION_TYPE_SURPRISED = 5;   // 😲
  REACTION_TYPE_SAD = 6;         // 😢
  REACTION_TYPE_THINKING = 7;    // 🤔
}

// リアクション詳細エンティティ (/tenants/{tenantId}/chats/{chatId}/messages/{messageId}/reactions/{userId})
message MessageReaction {
  string reaction_id = 1;  // ID 命名規約: r_xxx
  string message_id = 2;   // ID 命名規約: m_xxx
  string chat_id = 3;      // ID 命名規約: dm_xxx または gm_xxx
  string tenant_id = 4;    // ID 命名規約: t_xxx
  string user_id = 5;      // ユーザーID (u_xxx)
  string user_name = 6;    // ユーザー表示名
  ReactionType reaction_type = 7;
  google.protobuf.Timestamp created_at = 8;
  google.protobuf.Timestamp updated_at = 9;
}
```

---

## 3. Firestore セキュリティルール

```javascript
// ---------------------------------------------------------------------
// メッセージリアクション (/tenants/{tenantId}/chats/{chatId}/messages/{messageId}/reactions/{reactionUserId})
// ---------------------------------------------------------------------
match /reactions/{reactionUserId} {
  // チャット参加者のみ読み取り可能 (詳細表示用)
  allow read: if isChatMember(tenantId, chatId);

  // 自分のリアクションのみ作成・更新可能
  allow create, update: if isAuthenticated()
    && isChatMember(tenantId, chatId)
    && (reactionUserId == request.auth.uid || isTenantUser(tenantId, reactionUserId))
    && (request.resource.data.userId == request.auth.uid || isTenantUser(tenantId, request.resource.data.userId))
    && request.resource.data.chatId == chatId
    && request.resource.data.tenantId == tenantId;

  // 自分のリアクションのみ削除可能
  allow delete: if isAuthenticated()
    && isChatMember(tenantId, chatId)
    && (reactionUserId == request.auth.uid || isTenantUser(tenantId, reactionUserId));
}
```

---

## 4. UI / UX 表示仕様 (ChatDetailView)

1. **相手アイコン＆クリーンな吹き出しデザイン**:
   - 相手（自分以外）のメッセージは左側に丸型アバターアイコンを表示。
   - 吹き出し上部のユーザー名テキストは**常時非表示**（クリーンなUI表示）。
   - 背景はシステムセカンダリカラーの角丸吹き出し。
2. **全体左→右スワイプによる詳細・ユーザー名の一括表示**:
   - 画面全体を左から右へスワイプ（または右へドラッグ）すると、左側に配置されている全メッセージ（相手メッセージ）の送信者名・送信時刻・鍵バージョンメタデータが一括でスライドイン表示。
   - スワイプを解除すると自動で元の位置にアニメーション復帰。
3. **リアクションピッカー**:
   - メッセージを長押しすると、バブル上部に 7 種類の絵文字（👍, ❤️, 🆗, 😊, 😲, 😢, 🤔）が水平に並ぶクイックリアクションバーがポップアップ表示。
4. **リアクションバッジ**:
   - リアクションが付与されたメッセージの吹き出し下部に、付与されているリアクション絵文字と数量（例: `👍 2` `❤️ 1`）をカプセル型バッジで一覧表示。
   - 自分がリアクションしているものはハイライト表示（青枠/青背景）。
5. **リアクション詳細モーダル (Sheet)**:
   - メッセージのリアクションバッジタップ、または長押しメニューの「リアクション一覧」からシートを表示。
   - 「すべて」およびリアクション別のタブで「誰がいつリアクションしたか」を一覧表示。

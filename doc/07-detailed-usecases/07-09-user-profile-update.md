# 07-09: プロフィール編集（表示名・ユーザー識別子 username・アバター変更）と低コスト友達同期仕様書

本ドキュメントは、**Friends** におけるユーザーの表示名（`displayName`）、ユーザー識別子（`username`）およびアバター画像（`avatar`）変更のプロトコル、一意性制約管理、ローカルキャッシュ設計、および Firestore Read コストを最小化する**ハイブリッド同期方式（TTLキャッシュ + メッセージ受信時更新 + Pull-to-Refresh）**の設計仕様を定めたものです。

---

## 1. 背景と課題

1. **暗号化保存と公開識別子の分離**:
   - 表示名（`displayName`）は重要な個人特定情報（PII）であるため、同一テナント内であっても無差別に閲覧可能な公開プロファイルへの暗号化・平文保存は行いません。
   - 本人の表示名は自身の端末 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`）に安全に保管され、友達成立後は各自の個人秘密鍵（$MK_u$）で暗号化して `friends` サブコレクションに保管されます。最新の表示名変更は E2EE チャットメッセージ経由（送信者メタデータ）でセッション鍵暗号化されて友達にのみ伝播します。
   - ユーザー識別子（`username`）は検索・メンション用の公開ハンドル名（英数字・アンダースコア）とし、`/tenants/{tenantId}/usernames/{username}` に一意制約インデックスを配置して重複を防止します（初期値は `userId` と同一）。
   - システム内部の参照キーはすべて不変の `userId` (`u_xxx`) を使用し、`username` 変更時にも過去メッセージ・暗号鍵・DMチャット参照が壊れないようにします。
   - **ユーザー名変更時の確認・警告ダイアログ**: ユーザー名を変更すると他者が自身を検索・友達追加する際の識別子が変更されるため、保存実行時に明示的な警告・確認アラートを表示し、合意を得てから更新トランザクションを実行します。
2. **画像最適化 & メモリ保護 & R2 高速配信**:
   - アバター画像は 256x256 に圧縮（JPEG quality: 0.75）し、$MK_T$ で AES-GCM 暗号化したバイナリを **Cloudflare R2（CDN キャッシュ + Egress 転送量ゼロ）** へ保存。
   - クライアント側では `NSCache` による 2 層キャッシュで不要なダウンロードおよび復号処理を最小化します。

3. **リアルタイム伝播のコスト課題**:
   - 友達全員（数十〜数百人）のプロファイルドキュメントに対してリアルタイムリスナー（`onSnapshot`）を常時張ると、Read 課金および端末通信負荷が膨大になります。
   - そのため、**「On-Demand TTL キャッシュ」** と **「会話時のイベント駆動更新」** を組み合わせた**ハイブリッド同期**を採用し、不要な通信を 90% 以上削減します。

---

## 2. ハイブリッド同期アーキテクチャ

### 2.1 3 層の同期メカニズム

```text
┌───────────────────────────────────────────────────────────────────────────┐
│                      表示名変更ハイブリッド同期モデル                     │
├───────────────────────────────────────────────────────────────────────────┤
│ 1. [ローカル TTL キャッシュ (24h)]                                        │
│    - 友達一覧表示時はローカルキャッシュから即時描画（通信 0 回 / 爆速）   │
│    - 個人秘密鍵 (MK_u) で暗号化されたローカル友達データを復号表示         │
├───────────────────────────────────────────────────────────────────────────┤
│ 2. [会話時（メッセージ受信時）の同期]                                    │
│    - メッセージ送信時に送信者の最新表示名を E2EE 暗号化ペイロードから抽出し、│
│      受信側のローカル友達キャッシュを即時更新                             │
├───────────────────────────────────────────────────────────────────────────┤
│ 3. [手動 Pull-to-Refresh / 二次元コード再スキャン]                        │
│    - 友達一覧の再取得や対面での二次元コード再スキャンによる最新化         │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 3. シーケンス図

### 3.1 表示名変更シーケンス (本人)

```mermaid
sequenceDiagram
    autonumber
    actor User as "ユーザー (アリス)"
    participant View as "EditProfileView (E02)"
    participant ChatService as "ChatService"
    participant CryptoKeyManager as "CryptoKeyManager"

    User->>View: 新しい表示名「アリス改」を入力 & 「保存」タップ
    View->>ChatService: updateDisplayName(newName: "アリス改")
    ChatService->>CryptoKeyManager: saveMyDisplayName(name: "アリス改") (iOS Keychain保管)
    CryptoKeyManager-->>ChatService: 保存完了
    ChatService->>ChatService: currentUser.displayName = "アリス改"
    ChatService-->>View: 完了
    View-->>User: 画面を閉じて更新完了表示
    Note over ChatService: 今後のE2EEメッセージ送信時に最新の表示名が友達へ安全に伝播
```

### 3.2 友達への伝播シーケンス (ハイブリッド方式)

```mermaid
sequenceDiagram
    autonumber
    actor Alice as "アリス (名前変更済)"
    actor Bob as "友達ボブ"
    participant BobApp as "ボブのアプリ"
    participant Firestore as "Cloud Firestore"

    alt パターン 1: メッセージ受信時 (即時反映・追加Readゼロ)
        Alice->>Firestore: sendMessage(chatId, text: "こんにちは")
        Firestore-->>BobApp: 新着メッセージ通知 (senderName: "アリス改")
        BobApp->>BobApp: 友達キャッシュ内のアリスの名前を "アリス改" に更新
        BobApp->>Bob: トーク画面・友達一覧に「アリス改」と表示
    else パターン 2: 友達一覧 Pull-to-Refresh または TTL 期限切れ
        Bob->>BobApp: 友達一覧を下に引っ張って更新 (Pull to Refresh)
        BobApp->>Firestore: getDocs(/tenants/{t}/users/{aliceId})
        Firestore-->>BobApp: encryptedDisplayName, displayNameNonce
        BobApp->>BobApp: MK_T で復号 -> "アリス改"
        BobApp->>BobApp: キャッシュ更新 (TTLリセット)
        BobApp->>Bob: 友達一覧の表示名が更新
    end
```

### 3.3 友達のカスタム表示名変更シーケンス (秘密鍵 $MK_u$ 暗号化)

利用者が友達一覧やチャット画面で相手の呼び名（カスタム表示名）を変更する際、**自分自身の端末秘密鍵（$SK_u$）から導出される個人専用対称鍵（$MK_u$）** を用いて AES-256-GCM 暗号化を行い、自分側の友達サブコレクションにのみ保存します。

```mermaid
sequenceDiagram
    autonumber
    actor Alice as "ユーザー (アリス)"
    participant View as "FriendListView / ChatDetailView"
    participant ChatService as "ChatService"
    participant CryptoKeyManager as "CryptoKeyManager"
    participant Keychain as "iOS Keychain (SK_u)"
    participant Firestore as "Cloud Firestore"

    Alice->>View: 友達ボブの「表示名を変更」選択 & 「ボブちゃん」と入力
    View->>ChatService: updateFriendDisplayName(friendUserId: bobId, newDisplayName: "ボブちゃん")
    ChatService->>CryptoKeyManager: encryptWithPersonalKey("ボブちゃん", uid: aliceUid)
    CryptoKeyManager->>Keychain: getPrivateKey(aliceUid) (Curve25519 SK_u)
    Keychain-->>CryptoKeyManager: SK_u raw 32 bytes
    CryptoKeyManager->>CryptoKeyManager: HKDF-SHA256(SK_u, salt: "friends_personal_encryption_key_v1") -> MK_u
    CryptoKeyManager->>CryptoKeyManager: AES.GCM.seal("ボブちゃん", using: MK_u, nonce)
    CryptoKeyManager-->>ChatService: encryptedFriendDisplayName, friendDisplayNameNonce
    ChatService->>Firestore: updateDoc(/tenants/{t}/users/{aliceId}/friends/{bobId}, {encryptedFriendDisplayName, friendDisplayNameNonce, updatedBy, updatedAt})
    Firestore-->>ChatService: 成功応答
    ChatService->>ChatService: friends キャッシュのボブの表示名を "ボブちゃん" に即時反映
    ChatService-->>View: 完了
    View-->>Alice: 友達一覧およびチャット画面で「ボブちゃん」と即時表示
```

> [!IMPORTANT]
> - 友達のカスタム表示名は **本人しかアクセスできない自分側のサブコレクション** にのみ保存されます。
> - 暗号化鍵はテナント鍵（$MK_T$）ではなく本人の秘密鍵から導出される $MK_u$ を使用するため、テナント管理者や相手ボブ本人に対しても、アリスが設定したカスタムニックネームは一切漏洩しません（Zero-Knowledge）。

---

## 4. データ構造とキャッシュ設計

### 4.1 ローカル友達・プロファイルキャッシュ構造 (`FriendCacheEntry`)
```swift
struct FriendCacheEntry: Codable {
    let userId: String
    let displayName: String
    let publicKey: String
    let avatarNonce: String
    let avatarUpdatedAt: Date?
    let lastFetchedAt: Date

    var isExpired: Bool {
        // 24 時間で TTL 期限切れ
        Date().timeIntervalSince(lastFetchedAt) > 86400
    }
}
```

---

## 5. 画面設計・UI

プロフィール編集画面 (`E02`) の詳細なレイアウト・左右配置・ラベル体系・画面遷移については、[doc/08-screen-design.md (E02 プロフィール編集画面)](../08-screen-design.md#e02-プロフィール編集画面-editprofileview) を参照してください。

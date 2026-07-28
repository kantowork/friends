# 07-08: 外部REST API経由のグループ通知送信

外部システムからの REST API コールにより、指定された1つのテナントおよび複数のグループに所属するユーザー端末群へ通知を一括送信する機能の詳細設計です。

## 概要

基幹システムや外部の監視・連絡サービスから、特定のテナントに属する単数または複数のグループの所属メンバーに対してリアルタイムでプッシュ通知を配信します。
iOSデバイスに対しては、緊急性の高いメッセージ配信をサポートするため **Time Sensitive Notifications（即時通知）** に対応します。

---

## 外部 REST API 仕様

### エンドポイント

`POST /api/v1/external/notifications/send`

### 認証方式

`Authorization: Bearer <EXTERNAL_API_KEY>`
- 外部サービスごとに発行される API キー（またはサービスアカウント JWT）による認証を実施。
- サーバー側で API キーの有効性および送信対象テナントに対するアクセス権限を検証。

### リクエストヘッダー

```http
Content-Type: application/json
Authorization: Bearer sec_ext_api_key_xxxxxxxx
```

### リクエストボディ (`JSON`)

```json
{
  "tenantId": "t_corp_001",
  "targetGroupIds": [
    "g_sales_dept",
    "g_support_team"
  ],
  "notification": {
    "title": "【重要】緊急システムメンテナンスのお知らせ",
    "body": "本日15:00より緊急メンテナンスを実施いたします。",
    "urgency": "time-sensitive",
    "sound": "default"
  },
  "data": {
    "notificationId": "m_20260728_001",
    "actionUrl": "https://example.com/notice/123"
  }
}
```

#### パラメータ定義

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `tenantId` | String | ○ | 対象のテナント一意識別子（1つ指定） |
| `targetGroupIds` | Array[String] | - | 対象のグループ識別子リスト（複数指定可）。未指定または空配列の場合は、該当テナントの「デフォルトグループ」が自動適用されます。 |
| `notification.title` | String | ○ | 通知タイトル |
| `notification.body` | String | ○ | 通知本文 |
| `notification.urgency` | String | - | 通知の割り込み優先度 (`normal` \| `time-sensitive`)。デフォルト: `normal` |
| `notification.sound` | String | - | 通知音 (`default` またはアプリ組み込み音声ファイル名) |
| `data` | Map | - | アプリ側に渡すカスタム拡張メタデータ |

### レスポンス

#### 成功時 (`200 OK`)

```json
{
  "success": true,
  "notificationId": "m_20260728_001",
  "targetUserCount": 42,
  "sentDeviceCount": 58,
  "failedDeviceCount": 0,
  "timestamp": "2026-07-28T06:20:00Z"
}
```

#### エラー時 (`400` / `401` / `403` / `404`)

```json
{
  "success": false,
  "error": {
    "code": "INVALID_TENANT_OR_GROUP",
    "message": "Specified tenantId or groupIds do not exist or access denied."
  }
}
```

---

## シーケンス図

```mermaid
sequenceDiagram
    participant ExtService@{ "type": "boundary" } as "外部サービス"
    participant APIServer@{ "type": "control" } as "API サーバー / Cloud Function"
    participant DB@{ "type": "database" } as "Firestore DB"
    participant FCM@{ "type": "boundary" } as "Firebase Cloud Messaging"
    participant iOSDevice@{ "type": "boundary" } as "iOS デバイス"
    participant App@{ "type": "boundary" } as "iOS アプリ"

    ExtService->>APIServer: POST /api/v1/external/notifications/send (API Key, tenantId, targetGroupIds, notification)
    APIServer->>APIServer: API Key 認証 & テナント権限検証
    
    alt 認証失敗 / 権限なし
        APIServer-->>ExtService: 401 Unauthorized / 403 Forbidden
    end

    APIServer->>DB: 指定テナント内の指定グループメンバー抽出 (memberUserIds)
    DB-->>APIServer: ユーザーIDリスト (重複排除)
    
    APIServer->>DB: ユーザーの有効な FCM デバイストークン取得 (/devices)
    DB-->>APIServer: deviceToken リスト

    APIServer->>FCM: sendMulticast(FCM Tokens, Payload [APNs interruption-level])
    FCM-->>APIServer: 配信結果 (Success / Failure count)
    
    APIServer->>DB: AuditLog 書き込み (外部通知送信レコード)
    APIServer-->>ExtService: 200 OK (sentDeviceCount, targetUserCount)

    FCM->>iOSDevice: APNs プッシュ通知配信
    
    alt iOS ロック画面 / 集中モード中 (Time Sensitive)
        iOSDevice->>iOSDevice: 集中モードをバイパスして通知バナー表示 & 通知音再生
        opt AirPods 等装着時
            iOSDevice->>iOSDevice: Siri による通知自動読み上げ (Announce Notifications)
        end
    else フォアグラウンド起動中
        iOSDevice->>App: Notification received
        App->>App: AVSpeechSynthesizer によるアプリ内音声読み上げ (設定ON時)
    end
```

---

## FCM / APNs 通知ペイロード構造

FCM を介して APNs へ配信される際の通知ペイロード構造です。`urgency: "time-sensitive"` 指定時は `interruption-level: "time-sensitive"` を APNs ヘッダー/ペイロードへ埋め込みます。

```json
{
  "message": {
    "apns": {
      "headers": {
        "apns-priority": "10",
        "apns-push-type": "alert"
      },
      "payload": {
        "aps": {
          "alert": {
            "title": "【重要】緊急システムメンテナンスのお知らせ",
            "body": "本日15:00より緊急メンテナンスを実施いたします。"
          },
          "sound": "default",
          "interruption-level": "time-sensitive",
          "relevance-score": 1.0
        },
        "tenantId": "t_corp_001",
        "targetGroupIds": ["g_sales_dept", "g_support_team"]
      }
    }
  }
}
```

---

## iOS プラットフォーム仕様および検証結果

本機能の設計・検証における iOS プラットフォームの制約および対応方針です。

| 機能項目 | iOS実現可能性 | 技術的理由および採用方針 |
|---|---|---|
| **通知受信時の通知音量操作** | **不可** | iOSでは一般アプリが端末のシステム通知音量・メディア音量をプログラム的に直接変更する一般APIは存在しません。そのため、アプリ側での通知音量の強制変更は非対応とします。 |
| **バックグラウンドアプリ独自読み上げ** | **不可** | アプリがバックグラウンド/ロック画面状態の場合、Notification Service Extension の実行制限（最大30秒・画面表示不可）およびオーディオセッション制約により、アプリ独自でスピーカーから音声自動読み上げを起動することはできません。 |
| **Time Sensitive Notifications** | **可能（採用）** | iOS 15+ の `interruption-level: "time-sensitive"` をサポートします。ユーザーが「集中モード」を設定している場合でも通知を割り込み表示させることができます。 |
| **Siri による通知読み上げ** | **可能（連携）** | `time-sensitive` ペイロードを設定することで、AirPodsや対応ヘッドフォン着用時の iOS 標準機能「Siriによる通知の読み上げ (Announce Notifications)」の優先対象となります。 |
| **フォアグラウンドアプリ内読み上げ** | **可能（採用）** | アプリ起動中に通知を受信した場合は、アプリ内設定に応じて `AVSpeechSynthesizer` により通知本文の読み上げを行います。 |

### iOS アプリ側の必要設定
- iOS アプリ起動時に `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])` を実行し、ユーザーから即時通知の権限を取得します。

---

## 監査およびエラーハンドリング

1. **メタデータ監査 (`AuditLog`)**:
   - 本文平文は保管せず、`action: "EXTERNAL_GROUP_NOTIFICATION"`、`tenantId`、`targetGroupIds`、`sentDeviceCount`、`actorId` (API Key Identifier) のみを `AuditLog` に安全に記録します。
2. **エラーハンドリング**:
   - 無効な FCM トークンが検出された場合、DB (`Device`) の該当トークンに無効フラグを立てるか削除処理を行います。
   - 配信失敗時は指数バックオフ戦略を用いて FCM 再送信を最大3回リトライします。

# 07-05: メタデータ監査（テナント管理者）

ロバストネス分析 #4 に対応する詳細設計です。

## シーケンス図

```mermaid
sequenceDiagram
    actor TenantAdmin as "テナント管理者"
    participant AuditUI@{ "type": "boundary" } as "Audit Console"
    participant AuditController@{ "type": "control" } as AuditController
    participant Server@{ "type": "boundary" } as "Server/Cloud Function"
    participant Firestore@{ "type": "database" } as Firestore

    TenantAdmin->>AuditUI: 監査画面アクセス
    AuditUI->>AuditController: loadAuditUI(tenantId)
    AuditController->>Server: getTenantRole(tenantId, adminId)
    
    alt 管理者権限確認
        Server->>AuditUI: 監査画面表示
        TenantAdmin->>AuditUI: 期間指定・フィルター設定
        AuditUI->>AuditController: fetchMetadata(tenantId, dateRange, filters)
        AuditController->>Server: getConversationMetadata(tenantId, startDate, endDate)
        Server->>Firestore: メタデータを集計（本文除外）
        
        Note over Firestore: 抽出内容:<br/>- conversationId<br/>- senderId<br/>- recipientId<br/>- timestamp<br/>- messageCount<br/>- (内容は除外)
        
        Firestore->>Server: metadataList
        Server->>AuditController: metadataList
        AuditController->>AuditUI: 表示
        AuditUI->>TenantAdmin: 監査ログ表示（グラフ・表）
    else 権限なし
        Server->>AuditUI: 403 Forbidden
        AuditUI->>TenantAdmin: エラー表示「権限がありません」
    end
```

## 取得可能なメタデータ

```
✓ 許可:
  - Sender ID, Recipient ID
  - Timestamp, MessageID
  - Conversation Type (direct/group)
  - Message Count, Attachment Type

✗ 禁止:
  - Message Content (encrypted)
  - Media Payload
  - Metadata Decryption Keys
```

## エラーハンドリング

| エラー | 対応 |
|--------|------|
| 監査権限不足 | エラー表示「権限がありません」 |
| メタデータ収集エラー | リトライ or タイムアウト |
| 監査範囲超過 | 期間を絞る or ページング |

## 関連 API

- `GET /api/v1/audit/metadata` - メタデータ取得（Firestore 直接アクセスではなく、権限・集計ロジックのため専用サーバーAPIを残します）

## 関連ドメインモデル

- Tenant
- User (role: admin/manager/user)
- Message (metadata only)
- Conversation

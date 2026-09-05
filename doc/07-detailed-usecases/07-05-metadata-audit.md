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

> [!NOTE]
> **現行ステータス: 未実装（Phase 2 構想）**
> 現在の Phase 1 では「クライアント直接 Firestore アクセス」を基本方針としており、専用バックエンド API サーバーは構築されていません。
> 以下の `GET /api/v1/audit/metadata` および監査コンソール機能は、Phase 2 の管理者向け Web コンソール展開時に Cloud Functions / サーバーレス API として実装が予定されている構想仕様です。

- `GET /api/v1/audit/metadata` - メタデータ取得（将来の管理者コンソール用サーバーAPI構想）

## 関連ドメインモデル

- Tenant
- User (role: admin/manager/user)
- Message (metadata only)
- Conversation

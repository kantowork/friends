# Shared Package

このディレクトリには、Friends プロジェクト全体（iOS / Web / Server / Cloud Functions）で共有するドメインモデル、Protocol Buffers スキーマ、および共通型定義を格納します。

## ディレクトリ構造

```text
shared/
├── model/                 # 最新ドキュメントに基づくドメインモデル (.proto)
│   ├── common.proto       # 共通 Enum (ChatType, MessageType, UserRole 等) & EncryptedPayload
│   ├── tenant.proto       # Tenant (t_) & Group (g_)
│   ├── user.proto         # PublicUserProfile (u_), UserPrivateData, Device (d_)
│   ├── chat.proto         # Chat (dm_ / gm_) & KeyBucket (v_)
│   └── message.proto      # Message (m_)
└── proto/                 # API サービス定義 (gRPC / Connect / Cloud Functions)
    └── friends/
        └── v1/
            ├── auth.proto         # 匿名アカウント復旧サービス (RecoverAnonymous)
            ├── notification.proto # 外部連携グループ通知サービス (SendGroupNotification)
            └── audit.proto        # テナント管理者用メタデータ監査サービス (GetAuditMetadata)
```

## ドキュメント・規約への完全準拠

すべての Proto 定義は以下の最新ドキュメントおよび規約に 100% 準拠しています：

- **ID 命名規約** (`doc/09-guidelines/09-01-id-naming-conventions.md`):
  - 全域ユーザー UID: プレフィックスなし
  - テナント内公開ユーザー: `u_`
  - 1:1 DM チャット ID: `dm_`
  - グループチャット ID: `gm_`
  - 暗号化メッセージ ID: `m_`
  - 鍵バージョン ID: `v_`
  - テナント ID: `t_`
  - 組織グループ ID: `g_`
  - デバイス ID: `d_`
- **E2EE メッセージ構造** (`doc/07-detailed-usecases/07-03-message-encryption.md`):
  - ペイロード: `EncryptedPayload` (`ciphertext`, `nonce`)
  - 共通鍵バケット: `KeyBucket` (`key_version`, `encrypted_group_keys`)
- **端末移行・アカウント復旧** (`doc/07-detailed-usecases/07-04-device-recovery.md`):
  - 復元データ: `UserPrivateData` (`recovery_hash`, `encrypted_private_key`, `nonce`)

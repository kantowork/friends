# Shared Package

このディレクトリには、Friends プロジェクト全体（iOS / Web / Server / Cloud Functions）で共有するドメインモデル、Protocol Buffers スキーマ、および共通型定義を格納します。

## ディレクトリ構造

```text
shared/
├── model/                 # ドメインモデル (Proto3 SSOT)
│   ├── common.proto       # 共通 Enum (ChatType, MessageType, UserRole 等) & EncryptedPayload
│   ├── tenant.proto       # Tenant (t_) & Group (g_)
│   ├── user.proto         # PublicUserProfile (u_), UserPrivateData, Device (d_)
│   ├── chat.proto         # Chat (dm_ / gm_) & KeyBucket (v_)
│   ├── friend.proto       # 友達関係 (u_)
│   └── message.proto      # Message (m_)
├── schema/                # REST API スキーマ定義 (TypeScript + Zod SSoT)
│   ├── index.ts           # 共通エクスポート
│   ├── helper.ts          # Zod メタデータ付与ヘルパー (withExample, withRef)
│   ├── auth.ts            # 匿名復旧スキーマ (RecoverAnonymousRequest/Response)
│   ├── messages.ts        # メッセージ送信スキーマ (SendMessageRequest/Response)
│   └── common.ts          # 共通エラーレスポンススキーマ (ErrorResponse)
└── api/                   # Zod から自動生成される TypeScript 型定義
    ├── index.ts           # 共通エクスポート
    └── generated/         # scripts/generate_api.mjs で自動生成 (.gitignore 対象)
        └── schema.ts      # 生成された TypeScript 型定義
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

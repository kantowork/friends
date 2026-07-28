# 07-01: テナント選択フロー（QR コードスキャン・マスターキー取り込み）

ロバストネス分析 #2 および暗号化仕様 [10-detailed-design/10-01-tenant-data-encryption.md](../10-detailed-design/10-01-tenant-data-encryption.md) に対応する詳細ユースケースです。

注: テナント用の QR コードは **テナント作成後にサーバー側で生成・出力** されます（管理者がダウンロードや印刷で配布可能）。アプリ側はその QR をスキャンして `tenantId` およびテナントマスターキー（$MK_T$）を取得し、Keychain に保存します。

## 1. シーケンス図

```mermaid
sequenceDiagram
  autonumber
  actor User
  participant App as "iOS App"
  participant QRScanner as "QR Scanner"
  participant Keychain as "iOS Keychain"
  participant Firestore as "Cloud Firestore"

  User->>App: アプリ起動
  App->>App: デフォルトテナント確認
  alt デフォルトテナント設定済み
    App->>App: テナント自動選択
  else デフォルトテナント未設定
    App->>User: A03m テナント選択画面表示（QR スキャン or 手動設定）
    alt QR スキャン
      User->>QRScanner: QRコードをスキャン
      QRScanner->>App: QRコード読み込み完了
      App->>App: tenantId, tenantMasterKey を抽出
      App->>Keychain: saveTenantMasterKey(tenantId, MK_T)
      App->>Firestore: /tenants/{tenantId} を取得
    else 手動設定 (JSON)
      User->>App: テナント設定(JSON) を入力
      App->>App: JSON を検証して tenantId, tenantMasterKey を抽出
      App->>Keychain: saveTenantMasterKey(tenantId, MK_T)
      App->>Firestore: /tenants/{tenantId} を取得
    end
    alt テナント存在
      Firestore->>App: Tenant情報
      App->>App: tenantId をローカル保存
      App->>User: 確認表示
    else テナント不存在
      Firestore->>App: 404 / null
      App->>User: エラー表示「テナントが見つかりません」
    end
  end
  App->>App: ユーザー登録・ログイン画面へ
```

## 2. ローカル管理と Firestore 管理の区分

- ローカル管理 (Keychain / UserDefaults)
  - 選択済み `tenantId` とユーザーが最後に利用したテナント状態
  - **テナントマスターキー ($MK_T$)** (Keychain: `friends_tenant_key_{tenantId}`)
  - オフライン復帰時のテナント選択リストキャッシュ
- Firestore 管理
  - テナントの正規構成データ（`/tenants/{tenantId}`）
  - テナントの有効/無効状態、公開設定

> 端末上のローカル保存は暗号化マスターキーの厳重管理とユーザー体験向上用であり、権威あるテナント構成は Firestore 側に置きます。

## 3. エラーハンドリング

| エラー                | 対応                                           |
| :-------------------- | :--------------------------------------------- |
| QR コード無効         | スキャン再試行                                 |
| JSON フォーマット不正 | 入力バリデーションメッセージ、テンプレート表示 |
| テナント不存在        | 管理者に確認依頼                               |
| ネットワークエラー    | リトライ or オフライン表示                     |

## 4. 関連ドメインモデル
- Tenant
- User (tenantId に紐付け)

## 5. 多言語化（ローカライズ）
- アプリの UI 文言は `L10n` を通じて多言語化（日本語・英語）管理。

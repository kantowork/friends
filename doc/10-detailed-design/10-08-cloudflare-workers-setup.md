# 10-08: Cloudflare Workers バックエンド基盤事前準備・運用手順書 (Cloudflare Workers Setup & Operations)

本ドキュメントは、**Friends** アプリケーションにおけるサーバーレス・バックエンド基盤（認証連携、アカウント復旧、通知中継、監査集計）として **Cloudflare Workers** をセットアップ・運用するための事前作業手順書です。

---

## 1. 概要と選定理由

Friends では、Firebase の **Spark プラン（完全無料枠・クレジットカード登録不要）** を維持しながら、セキュアなサーバー処理・API 機能を提供するため、プロジェクト全体のサーバー基盤として **Cloudflare Workers** を採用しています。

- **完全無料枠での運用（$0/月）**:
  - Firebase Functions（有料 Blaze プラン必須）を一切使用せず、Cloudflare Workers の無料枠（**1日10万リクエスト / 月間300万リクエスト**）内で完全運用可能。
- **Cloudflare エコシステムとの一元統合**:
  - すでに暗号化メディアストレージとして導入済みの **Cloudflare R2**（[10-06](10-06-r2-storage-setup.md)）と同一アカウント・インフラで一元管理でき、低レイテンシでセキュアな連携が可能。
- **Web Crypto API (RS256) による Firebase Custom Token 生成**:
  - Google サービスアカウントキーを用いて、Cloudflare Workers 上の標準 Web Crypto API (`crypto.subtle`) で Firebase Auth の Custom Token (JWT) を生成・署名可能。
- **ゼロ・ナレッジ（E2EE保護）の徹底**:
  - サーバーは暗号化照合ハッシュ（`recoveryHash`）のみを検証し、平文のパスワード、秘密鍵、ふっかつのじゅもんは一切受け取りません。

---

## 2. Workers が提供する API 一覧

Workers 基盤 (`server/workers/`) は、将来的な機能拡張に対応する統一ルーティング設計となっています：

| エンドポイント | メソッド | 機能概要 | 認証・認可 |
|:---|:---|:---|:---|
| `/api/v1/health` | `GET` | サーバーヘルスチェック | なし (Public) |
| `/api/v1/auth/recover-anonymous` | `POST` | ふっかつのじゅもんによるアカウント完全復旧・Custom Token 発行 | `recoveryHash` 照合 |
| `/api/v1/notifications/send` | `POST` | *(将来拡張)* FCM/APNs バックグラウンド通知配信制御 | テナント API キー |
| `/api/v1/audit/metadata` | `GET` | *(将来拡張)* テナント管理者向け集計・監査メタデータ取得 | テナント管理者署名 |

---

## 3. セットアップ手順（ユーザー事前作業チェックリスト）

開発者・運用担当者が本機能を本番稼働させるためのステップバイステップ手順です。

### ステップ 1: Google Cloud サービスアカウントキー (JSON) の取得

Firebase Auth の Custom Token を発行し、Firestore を安全に検索するための Google サービスアカウントキーを無料で作成します。

1. **Google Cloud Console** にアクセスし、Friends プロジェクトを選択:
   - URL: `https://console.cloud.google.com/iam-admin/serviceaccounts`
2. **「+ サービス アカウントを作成」** をクリック:
   - サービス アカウント名: `friends-workers-backend`
   - サービス アカウント ID: 自動入力（例: `friends-workers-backend@your-project-id.iam.gserviceaccount.com`）
   - 「作成して続行」をクリック。
3. **ロール（権限）の付与（最小権限の原則）**:
   - 以下のロールを付与します（必要最小限の権限）：
     - **Cloud Datastore 閲覧者** (`roles/datastore.viewer`)
   - 「続行」→「完了」をクリック。
4. **JSON キーの生成・ダウンロード**:
   - 作成したサービスアカウント一覧から `friends-workers-backend` をクリック。
   - **「キー」** タブを開き、**「鍵を追加」** → **「新しい鍵を作成」** を選択。
   - キーのタイプ: **JSON** を選択して「作成」をクリック。
   - JSON ファイル（例: `your-project-id-xxxxxxxxxxxx.json`）がダウンロードされます。
   > [!CAUTION]
   > この JSON ファイルにはサービスアカウントの秘密鍵が含まれます。**Git リポジトリには絶対にコミットしないでください**（`.gitignore` 対象）。

---

### ステップ 2: Cloudflare Workers のセットアップ

1. **リポジトリ内の Workers ディレクトリへ移動**:
   ```bash
   cd server/workers
   npm install
   ```

2. **Cloudflare CLI (Wrangler) のログイン & 初回デプロイ**:
   ```bash
   npx wrangler login
   npm run deploy
   ```
   ※ 初回デプロイを行うと、Cloudflare ダッシュボード上に Worker (`friends-api`) が作成されます。

3. **環境変数・シークレットの設定（Cloudflare ダッシュボード / ブラウザ操作）**:
   ダウンロードしたサービスアカウント JSON ファイルの内容を、ブラウザから Cloudflare ダッシュボードのシークレットとして登録します。
   （秘密鍵などの改行を含む長い値も、ブラウザのフォームから安全かつ確実に登録できます）

   1. [Cloudflare ダッシュボード](https://dash.cloudflare.com/) にログイン。
   2. 左側メニューの **「Workers & Pages」**（または **「Compute (Workers)」**）を開き、一覧から **`friends-api`** を選択。
   3. **「Settings（設定）」** タブをクリックし、左メニューから **「Variables and Secrets（変数とシークレット）」** を選択。
   4. **「Secrets（シークレット）」** セクションの **「Add（追加）」** をクリックして、以下の 3 つを登録します：

   | 変数名 (Variable Name) | タイプ | 設定する値（JSON ファイルから転記） |
   | :--- | :---: | :--- |
   | **`FIREBASE_PROJECT_ID`** | Secret | JSON 内の `project_id`（例: `friends-kanto-prod`） |
   | **`GOOGLE_CLIENT_EMAIL`** | Secret | JSON 内の `client_email`（例: `friends-workers-backend@...`） |
   | **`GOOGLE_PRIVATE_KEY`** | Secret | JSON 内の `private_key` 全文（`-----BEGIN PRIVATE KEY-----\n...` をそのまま貼り付け） |

   5. 入力後、**「Save and deploy（保存してデプロイ）」** をクリック。

   *(※ 代替手段としてターミナルから `npx wrangler secret put <KEY>` で登録することも可能です)*

4. **デプロイ完了確認**:
   ブラウザで発行された公開 URL にアクセスし、ヘルスチェックを確認します：
   `https://friends-api.<your-subdomain>.workers.dev/api/v1/health`
   `{"status":"ok"}` が返れば正常に稼働しています。

5. **Workers Logs（リアルタイム・保持ログ）の確認**:
   本プロジェクトでは `wrangler.toml` に `[observability] enabled = true` を設定しており、Cloudflare ダッシュボード上でログの確認・検索が可能です。
   - **ブラウザから確認**:
     - Cloudflare ダッシュボード > **Workers & Pages** > **`friends-api`** > **「Logs」** タブを開きます。
     - 直近のリクエスト履歴（ステータスコード、エラーログ、`console.log` 等）が表示され、リアルタイムログストリームも利用できます。
   - **ターミナルから確認 (CLI)**:
     ```bash
     cd server/workers
     npx wrangler tail
     ```

---

---

### ステップ 3: テナント QR コードへの接続先 URL 付与（構成管理非保持）

セキュリティおよびマルチテナント運用の観点から、**Cloudflare Workers の URL やテナントコードはアプリのソースコード（Git リポジトリ）には一切ハードコードしません**。
管理者が初回にユーザーへ提示・配布する **「テナント QR コード」のペイロードにのみ付与** します。

1. **テナント QR コードの JSON ペイロード形式**:
   ```json
   {
     "tenantId": "t_default",
     "tenantCode": "default",
     "masterKey": "<Base64 encoded MK_T>",
     "workerApiUrl": "https://..."
   }
   ```
2. **クライアントの挙動**:
   - ユーザーが初回または新端末でテナント QR コードをスキャンした際、アプリは `tenantCode` と `workerApiUrl` をローカル設定（UserDefaults / Keychain）に自動保存します。
   - 「ふっかつのじゅもん」による完全復元時、アプリは保存された `workerApiUrl` を読み取って Workers API と通信します。
   - ※ ローカル開発・CIテスト時のみ、環境変数 `FRIENDS_WORKERS_URL` での動的オーバーライドが可能です。

---

## 4. 運用・モニタリング手順

### 4.1 リアルタイムログ確認
Workers のリアルタイム実行ログ・エラーログは、以下のコマンドで即座にストリーミング監視できます：

```bash
cd server/workers
npx wrangler tail
```

### 4.2 セキュリティ運用基準
1. **レートリミット**:
   - `recover-anonymous` エンドポイントには、同一 IP からの連続総当たりを防ぐレートリミットガードが組み込まれています（デフォルト: 1分あたり最大10リクエスト）。
2. **秘密鍵ローテーション**:
   - 万が一 Google サービスアカウントキーが漏洩した疑いがある場合は、Google Cloud Console から既存キーを削除し、新しいキーを作成して `npx wrangler secret put GOOGLE_PRIVATE_KEY` で更新してください。


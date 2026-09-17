// Firestore REST API 操作汎用ライブラリ (インフラ層)
// 業務ロジックやドメイン知識を一切持たず、Firestore REST API との通信に専念します。

import { getGoogleOAuth2AccessToken } from "./jwt";

export interface FirestoreField {
  stringValue?: string;
  booleanValue?: boolean;
  integerValue?: string | number;
  doubleValue?: number;
  timestampValue?: string;
  mapValue?: {
    fields?: Record<string, FirestoreField>;
  };
  arrayValue?: {
    values?: FirestoreField[];
  };
  nullValue?: null;
}

export interface FirestoreDocument {
  name: string;
  fields?: Record<string, FirestoreField>;
  createTime?: string;
  updateTime?: string;
}

export interface FirestoreWrite {
  update?: {
    name: string;
    fields?: Record<string, FirestoreField>;
  };
  updateMask?: {
    fieldPaths: string[];
  };
  delete?: string;
}

export class FirestoreClient {
  private projectId: string;
  private clientEmail: string;
  private privateKeyPem: string;
  private firebaseApiKey: string;
  private cachedAccessToken: { token: string; expiresAt: number } | null = null;

  constructor(projectId: string, clientEmail: string, privateKeyPem: string, firebaseApiKey: string) {
    this.projectId = projectId;
    this.clientEmail = clientEmail;
    this.privateKeyPem = privateKeyPem;
    this.firebaseApiKey = firebaseApiKey;
  }

  /// サービスアカウント名義の Google Cloud OAuth2 Access Token を取得（キャッシュ管理）
  /// - Firebase ID Token ではなく Google OAuth2 Access Token を使用することで、Firestore Security Rules をバイパスして安全にサーバー権限で実行
  async getAccessToken(): Promise<string> {
    const now = Date.now();
    if (this.cachedAccessToken && this.cachedAccessToken.expiresAt > now + 60000) {
      return this.cachedAccessToken.token;
    }

    console.log(`[FirestoreClient] Fetching Google OAuth2 token for clientEmail=${this.clientEmail}, projectId=${this.projectId}`);

    const { accessToken, expiresIn } = await getGoogleOAuth2AccessToken(
      this.clientEmail,
      this.privateKeyPem,
      ["https://www.googleapis.com/auth/datastore", "https://www.googleapis.com/auth/cloud-platform"]
    );

    console.log(`[FirestoreClient] Obtained token: length=${accessToken.length}, expiresIn=${expiresIn}`);

    this.cachedAccessToken = {
      token: accessToken,
      expiresAt: now + (expiresIn - 60) * 1000,
    };
    return accessToken;
  }

  /// 単一ドキュメント取得 (GET)
  /// - relativeDocPath: 例 "tenants/t_123/users/u_456" または "recovery_vault/hash"
  async getDocument(relativeDocPath: string): Promise<FirestoreDocument | null> {
    const accessToken = await this.getAccessToken();
    const cleanPath = relativeDocPath.replace(/^\/+/, "");
    const url = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents/${cleanPath}`;

    const res = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });

    if (!res.ok) {
      const errText = await res.text();
      console.warn(`[FirestoreClient.getDocument] ${cleanPath} failed: status=${res.status}, body=${errText}`);
      return null;
    }

    return (await res.json()) as FirestoreDocument;
  }

  /// コレクション直下のドキュメント一覧取得 (GET)
  async listDocuments(relativeCollectionPath: string): Promise<FirestoreDocument[]> {
    const accessToken = await this.getAccessToken();
    const cleanPath = relativeCollectionPath.replace(/^\/+/, "");
    const url = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents/${cleanPath}`;

    const res = await fetch(url, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });

    if (!res.ok) {
      const errText = await res.text();
      console.warn(`[FirestoreClient.listDocuments] ${cleanPath} failed: status=${res.status}, body=${errText}`);
      return [];
    }

    const data = (await res.json()) as { documents?: FirestoreDocument[] };
    return data.documents || [];
  }

  /// プロジェクトIDの取得
  getProjectId(): string {
    return this.projectId;
  }

  /// ドキュメントパスの完全修飾名 (projects/{projectId}/databases/(default)/documents/{path}) を生成
  formatDocumentName(relativeDocPath: string): string {

    const cleanPath = relativeDocPath.replace(/^\/+/, "");
    return `projects/${this.projectId}/databases/(default)/documents/${cleanPath}`;
  }

  /// 複数操作のアトミックコミット (POST documents:commit)
  async commit(writes: FirestoreWrite[]): Promise<void> {
    if (writes.length === 0) return;

    const accessToken = await this.getAccessToken();
    const commitUrl = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents:commit`;

    const res = await fetch(commitUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ writes }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Firestore commit failed: ${res.status} ${errText}`);
    }
  }

  /// 構造化クエリの実行 (POST documents:runQuery)
  async runQuery(
    structuredQuery: Record<string, unknown>,
    parentDocPath?: string
  ): Promise<FirestoreDocument[]> {
    const accessToken = await this.getAccessToken();
    const basePath = parentDocPath
      ? `projects/${this.projectId}/databases/(default)/documents/${parentDocPath.replace(/^\/+/, "")}`
      : `projects/${this.projectId}/databases/(default)/documents`;
    const queryUrl = `https://firestore.googleapis.com/v1/${basePath}:runQuery`;

    const res = await fetch(queryUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ structuredQuery }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Firestore runQuery failed: ${res.status} ${errText}`);
    }

    const results = (await res.json()) as Array<{ document?: FirestoreDocument }>;
    const documents: FirestoreDocument[] = [];
    for (const r of results) {
      if (r.document) {
        documents.push(r.document);
      }
    }
    return documents;
  }
}

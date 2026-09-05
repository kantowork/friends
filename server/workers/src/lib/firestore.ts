// Firestore REST API 操作ライブラリ
import { getGoogleOAuth2AccessToken } from "./jwt";

export interface RecoveryRecord {
  uid: string;
  encryptedPrivateKey: string;
  nonce: string;
}

export class FirestoreClient {
  private projectId: string;
  private clientEmail: string;
  private privateKeyPem: string;
  private cachedToken: { token: string; expiresAt: number } | null = null;

  constructor(projectId: string, clientEmail: string, privateKeyPem: string) {
    this.projectId = projectId;
    this.clientEmail = clientEmail;
    this.privateKeyPem = privateKeyPem;
  }

  private async getAccessToken(): Promise<string> {
    const now = Date.now();
    if (this.cachedToken && this.cachedToken.expiresAt > now + 60000) {
      return this.cachedToken.token;
    }

    const token = await getGoogleOAuth2AccessToken(
      this.clientEmail,
      this.privateKeyPem,
      ["https://www.googleapis.com/auth/datastore"]
    );
    this.cachedToken = {
      token,
      expiresAt: now + 3500 * 1000,
    };
    return token;
  }

  /// recoveryHash から復旧用バックアップレコードを取得する
  async findRecoveryRecord(recoveryHash: string): Promise<RecoveryRecord | null> {
    const token = await this.getAccessToken();

    // 1. recovery_vault/{recoveryHash} からの単一ドキュメント直接取得 (最速・インデックス不要)
    const vaultUrl = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents/recovery_vault/${recoveryHash}`;
    const vaultResponse = await fetch(vaultUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });

    if (vaultResponse.ok) {
      const doc = (await vaultResponse.json()) as { fields?: Record<string, { stringValue?: string }> };
      if (doc.fields) {
        const uid = doc.fields.uid?.stringValue;
        const encryptedPrivateKey = doc.fields.encryptedPrivateKey?.stringValue;
        const nonce = doc.fields.nonce?.stringValue;

        if (uid && encryptedPrivateKey && nonce) {
          return { uid, encryptedPrivateKey, nonce };
        }
      }
    }

    // 2. フォールバック: /users/{uid}/private/data のコレクション横断検索
    const queryUrl = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents:runQuery`;
    const queryBody = {
      structuredQuery: {
        from: [{ collectionId: "private", allDescendants: true }],
        where: {
          fieldFilter: {
            field: { fieldPath: "recoveryHash" },
            op: "EQUAL",
            value: { stringValue: recoveryHash },
          },
        },
        limit: 1,
      },
    };

    const queryResponse = await fetch(queryUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(queryBody),
    });

    if (queryResponse.ok) {
      const results = (await queryResponse.json()) as Array<{
        document?: {
          name: string;
          fields?: Record<string, { stringValue?: string }>;
        };
      }>;

      for (const item of results) {
        if (item.document?.fields) {
          const fields = item.document.fields;
          const uid = fields.uid?.stringValue;
          const encryptedPrivateKey = fields.encryptedPrivateKey?.stringValue;
          const nonce = fields.nonce?.stringValue;

          if (uid && encryptedPrivateKey && nonce) {
            return { uid, encryptedPrivateKey, nonce };
          }
        }
      }
    }

    return null;
  }
}

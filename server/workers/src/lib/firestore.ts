// Firestore REST API 操作ライブラリ
import { createFirebaseCustomToken, exchangeCustomTokenToIdToken } from "./jwt";

export interface RecoveryRecord {
  uid: string;
  encryptedPrivateKey: string;
  nonce: string;
}

export class FirestoreClient {
  private projectId: string;
  private clientEmail: string;
  private privateKeyPem: string;
  private firebaseApiKey: string;
  private cachedIdToken: { token: string; expiresAt: number } | null = null;

  constructor(projectId: string, clientEmail: string, privateKeyPem: string, firebaseApiKey: string) {
    this.projectId = projectId;
    this.clientEmail = clientEmail;
    this.privateKeyPem = privateKeyPem;
    this.firebaseApiKey = firebaseApiKey;
  }

  /// サービスアカウント名義の Firebase ID Token を取得（Firestore セキュリティルール評価用）
  private async getIdToken(): Promise<string> {
    const now = Date.now();
    if (this.cachedIdToken && this.cachedIdToken.expiresAt > now + 60000) {
      return this.cachedIdToken.token;
    }

    // 1. Service Account で Custom Token 発行
    const customToken = await createFirebaseCustomToken(
      this.clientEmail,
      this.privateKeyPem,
      "service-account-recovery"
    );

    // 2. Identity Toolkit で ID Token に交換
    const idToken = await exchangeCustomTokenToIdToken(customToken, this.firebaseApiKey);
    this.cachedIdToken = {
      token: idToken,
      expiresAt: now + 3500 * 1000,
    };
    return idToken;
  }

  /// recoveryHash から復旧用バックアップレコードを取得する
  async findRecoveryRecord(recoveryHash: string): Promise<RecoveryRecord | null> {
    const idToken = await this.getIdToken();

    // recovery_vault/{recoveryHash} からの単一ドキュメント直接取得
    const vaultUrl = `https://firestore.googleapis.com/v1/projects/${this.projectId}/databases/(default)/documents/recovery_vault/${recoveryHash}`;
    const vaultResponse = await fetch(vaultUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${idToken}`,
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

    return null;
  }
}

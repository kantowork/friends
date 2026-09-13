// 匿名アカウント復旧業務サービス (業務ロジック層)
import { FirestoreClient } from "../lib/firestore";
import { createFirebaseCustomToken } from "../lib/jwt";

export interface RecoveryRecord {
  uid: string;
  encryptedPrivateKey: string;
  nonce: string;
}

export class RecoveryService {
  private firestore: FirestoreClient;
  private clientEmail: string;
  private privateKeyPem: string;

  constructor(firestore: FirestoreClient, clientEmail: string, privateKeyPem: string) {
    this.firestore = firestore;
    this.clientEmail = clientEmail;
    this.privateKeyPem = privateKeyPem;
  }

  /// recoveryHash から復旧用ボルトレコードを取得
  async findRecoveryRecord(recoveryHash: string): Promise<RecoveryRecord | null> {
    const doc = await this.firestore.getDocument(`recovery_vault/${recoveryHash}`);
    if (!doc || !doc.fields) {
      return null;
    }

    const uid = doc.fields.uid?.stringValue;
    const encryptedPrivateKey = doc.fields.encryptedPrivateKey?.stringValue;
    const nonce = doc.fields.nonce?.stringValue;

    if (uid && encryptedPrivateKey && nonce) {
      return { uid, encryptedPrivateKey, nonce };
    }

    return null;
  }

  /// 復旧対象ユーザーの Firebase Auth Custom Token を発行
  async createCustomToken(uid: string): Promise<string> {
    return await createFirebaseCustomToken(
      this.clientEmail,
      this.privateKeyPem,
      uid
    );
  }
}

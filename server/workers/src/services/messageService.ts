// メッセージ送受信業務サービス (業務ロジック層)
import { FirestoreClient, FirestoreWrite } from "../lib/firestore";
import type { SendMessagePayload, SendMessageResponse } from "@shared/api";

export class MessageService {
  private firestore: FirestoreClient;

  constructor(firestore: FirestoreClient) {
    this.firestore = firestore;
  }

  /// 送信者本人性の認可評価 (なりすまし防止)
  async verifySender(tenantId: string, senderId: string, authenticatedUid: string): Promise<boolean> {
    console.log(`[verifySender] Start: tenantId=${tenantId}, senderId=${senderId}, authUid=${authenticatedUid}`);
    if (senderId === authenticatedUid) {
      console.log(`[verifySender] Direct match: senderId === authUid`);
      return true;
    }

    // テナント内プロファイル (/tenants/{tenantId}/users/{senderId}) の uid を照合
    const docPath = `tenants/${tenantId}/users/${senderId}`;
    const userDoc = await this.firestore.getDocument(docPath);
    console.log(`[verifySender] getDocument(${docPath}):`, JSON.stringify(userDoc));

    if (userDoc && userDoc.fields) {
      const docUid = userDoc.fields.uid?.stringValue;
      console.log(`[verifySender] docUid=${docUid}, authUid=${authenticatedUid}`);
      if (docUid === authenticatedUid) {
        return true;
      }
    }

    console.warn(`[verifySender] Authorization failed for senderId=${senderId}, authUid=${authenticatedUid}`);
    return false;
  }

  /// メッセージ保存・親チャット更新・Push通知処理
  async sendMessage(params: {
    tenantId: string;
    chatId: string;
    message: SendMessagePayload;
    members?: string[];
  }): Promise<SendMessageResponse> {
    const { tenantId, chatId, message, members } = params;
    const nowIso = new Date().toISOString();

    const chatRelativePath = `tenants/${tenantId}/chats/${chatId}`;
    const messageRelativePath = `${chatRelativePath}/messages/${message.messageId}`;

    const chatDocName = this.firestore.formatDocumentName(chatRelativePath);
    const messageDocName = this.firestore.formatDocumentName(messageRelativePath);

    // 1. 親チャットの存在確認
    const existingChat = await this.firestore.getDocument(chatRelativePath);

    const writes: FirestoreWrite[] = [];

    if (existingChat) {
      // 既存チャット: lastMessageAt, updatedAt, updatedBy のみを更新
      writes.push({
        update: {
          name: chatDocName,
          fields: {
            lastMessageAt: { timestampValue: nowIso },
            updatedBy: { stringValue: message.senderId },
            updatedAt: { timestampValue: nowIso },
          },
        },
        updateMask: {
          fieldPaths: ["lastMessageAt", "updatedBy", "updatedAt"],
        },
      });
    } else {
      // 新規チャット作成
      let resolvedMembers: string[] = members && members.length > 0 ? members : [];

      // dm_u_alice_u_bob 形式からのメンバー自動解決 (フォールバック)
      if (resolvedMembers.length === 0 && chatId.startsWith("dm_")) {
        const parts = chatId.split("_");
        for (let i = 0; i < parts.length - 1; i++) {
          if (parts[i] === "u") {
            resolvedMembers.push("u_" + parts[i + 1]);
          }
        }
      }
      if (!resolvedMembers.includes(message.senderId)) {
        resolvedMembers.push(message.senderId);
      }
      resolvedMembers = Array.from(new Set(resolvedMembers)).sort();

      writes.push({
        update: {
          name: chatDocName,
          fields: {
            chatId: { stringValue: chatId },
            tenantId: { stringValue: tenantId },
            chatType: { stringValue: chatId.startsWith("gm_") ? "group" : "direct" },
            members: {
              arrayValue: {
                values: resolvedMembers.map((m) => ({ stringValue: m })),
              },
            },
            lastMessage: { stringValue: "" },
            lastMessageAt: { timestampValue: nowIso },
            createdBy: { stringValue: message.senderId },
            createdAt: { timestampValue: nowIso },
            updatedBy: { stringValue: message.senderId },
            updatedAt: { timestampValue: nowIso },
          },
        },
      });
    }

    // 2. メッセージドキュメントの書き込み
    writes.push({
      update: {
        name: messageDocName,
        fields: {
          messageId: { stringValue: message.messageId },
          tenantId: { stringValue: tenantId },
          chatId: { stringValue: chatId },
          senderId: { stringValue: message.senderId },
          keyVersion: { stringValue: message.keyVersion },
          encryptedPayload: {
            mapValue: {
              fields: {
                ciphertext: { stringValue: message.ciphertext },
                nonce: { stringValue: message.nonce },
              },
            },
          },
          messageType: { stringValue: message.messageType || "text" },
          createdBy: { stringValue: message.senderId },
          createdAt: { timestampValue: nowIso },
          updatedBy: { stringValue: message.senderId },
          updatedAt: { timestampValue: nowIso },
        },
      },
    });

    // 3. アトミックコミット
    await this.firestore.commit(writes);

    // 4. 将来の Push 通知 (FCM / APNs) ディスパッチ用フック
    // 将来ここに this.dispatchPushNotification(...) を追加

    return {
      success: true,
      messageId: message.messageId,
      chatId,
      tenantId,
    };
  }
}

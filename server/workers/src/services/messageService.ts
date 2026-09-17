// メッセージ送受信業務サービス (業務ロジック層)
import { FirestoreClient, FirestoreWrite } from "../lib/firestore";
import { PushNotificationService } from "./pushNotificationService";
import type { SendMessagePayload, SendMessageResponse } from "@shared/schema";

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
    let resolvedChatMembers: string[] = [];

    if (existingChat) {
      // 既存チャット: members の取得と lastMessageAt, updatedAt, updatedBy のみを更新
      const existingMembers = existingChat.fields?.members?.arrayValue?.values
        ?.map((v) => v.stringValue)
        .filter((v): v is string => typeof v === "string") || [];
      resolvedChatMembers = existingMembers;

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
      resolvedChatMembers = resolvedMembers;

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

    // 4. Push 通知 (FCM / APNs) ディスパッチ (非同期実行)
    const recipientUids = resolvedChatMembers.filter((uid) => uid !== message.senderId);
    this.dispatchPushNotification({
      tenantId,
      chatId,
      message,
      recipientUids,
    }).catch((err) => {
      console.error("[MessageService] Push notification dispatch error:", err);
    });

    return {
      success: true,
      messageId: message.messageId,
      chatId,
      tenantId,
    };
  }

  /// チャット参加者のデバイス宛に Push 通知を送信
  private async dispatchPushNotification(params: {
    tenantId: string;
    chatId: string;
    message: SendMessagePayload;
    recipientUids: string[];
  }): Promise<void> {
    const { tenantId, chatId, message, recipientUids } = params;
    if (recipientUids.length === 0) return;

    console.log(`[dispatchPushNotification] Collecting device tokens for recipients: ${recipientUids.join(", ")}`);

    const pushService = new PushNotificationService(this.firestore);
    const tokens = await pushService.getDeviceTokensForUsers(recipientUids);

    if (tokens.length === 0) {
      console.log(`[dispatchPushNotification] No registered devices found for recipients`);
      return;
    }

    await pushService.sendNotification({
      tokens,
      title: "Friends",
      body: "新着メッセージが届きました",
      data: {
        tenantId,
        chatId,
        messageId: message.messageId,
        senderId: message.senderId,
      },
    });
  }
}

import { FirestoreClient } from "../lib/firestore";

export interface PushNotificationPayload {
  tokens: string[];
  title?: string;
  body: string;
  data: {
    tenantId: string;
    chatId: string;
    messageId: string;
    senderId: string;
    [key: string]: string;
  };
}

// MARK: - PushNotificationService
/// FCM HTTP v1 API 経由でプッシュ通知を配信するサービス
export class PushNotificationService {
  private firestore: FirestoreClient;

  constructor(firestore: FirestoreClient) {
    this.firestore = firestore;
  }

  /// 複数ユーザーIDに紐づく有効なデバイストークン（FCM / APNs）を一括取得 (Collection Group クエリ)
  async getDeviceTokensForUsers(userIds: string[]): Promise<string[]> {
    if (userIds.length === 0) return [];

    // Firestore REST API の "IN" 句上限は30件
    const chunks: string[][] = [];
    for (let i = 0; i < userIds.length; i += 30) {
      chunks.push(userIds.slice(i, i + 30));
    }

    const tokens: string[] = [];

    for (const chunk of chunks) {
      const structuredQuery = {
        from: [
          {
            collectionId: "devices",
            allDescendants: true,
          },
        ],
        where: {
          compositeFilter: {
            op: "AND",
            filters: [
              {
                fieldFilter: {
                  field: { fieldPath: "enabled" },
                  op: "EQUAL",
                  value: { booleanValue: true },
                },
              },
              {
                fieldFilter: {
                  field: { fieldPath: "userId" },
                  op: "IN",
                  value: {
                    arrayValue: {
                      values: chunk.map((uid) => ({ stringValue: uid })),
                    },
                  },
                },
              },
            ],
          },
        },
      };

      try {
        const docs = await this.firestore.runQuery(structuredQuery);
        for (const doc of docs) {
          const isEnabled = doc.fields?.enabled?.booleanValue !== false;
          if (!isEnabled) continue;

          const token = doc.fields?.fcmToken?.stringValue || doc.fields?.apnsToken?.stringValue;
          if (token && !tokens.includes(token)) {
            tokens.push(token);
          }
        }
      } catch (err) {
        console.warn(`[PushNotificationService] Failed to query devices for chunk:`, err);
      }
    }

    return tokens;
  }

  /// 複数トークン宛に Push 通知をマルチキャスト送信 (FCM HTTP v1 API)
  async sendNotification(payload: PushNotificationPayload): Promise<{ successCount: number; failureCount: number }> {
    const { tokens, title = "Friends", body, data } = payload;
    if (tokens.length === 0) {
      return { successCount: 0, failureCount: 0 };
    }

    const projectId = this.firestore.getProjectId();
    let accessToken: string;
    try {
      accessToken = await this.firestore.getAccessToken();
    } catch (e) {
      console.error("[PushNotificationService] Failed to get OAuth2 access token for push notification:", e);
      return { successCount: 0, failureCount: tokens.length };
    }

    let successCount = 0;
    let failureCount = 0;

    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const sendPromises = tokens.map(async (token) => {
      const messageBody = {
        message: {
          token,
          notification: {
            title,
            body,
          },
          data,
          apns: {
            payload: {
              aps: {
                badge: 1,
                sound: "default",
              },
            },
          },
        },
      };

      try {
        const res = await fetch(fcmEndpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(messageBody),
        });

        if (res.ok) {
          successCount++;
        } else {
          failureCount++;
          const errText = await res.text();
          console.warn(`[PushNotificationService] FCM send error for token ${token.slice(0, 10)}...: ${res.status} ${errText}`);
        }
      } catch (err) {
        failureCount++;
        console.error(`[PushNotificationService] Network error sending notification to ${token.slice(0, 10)}...:`, err);
      }
    });

    await Promise.allSettled(sendPromises);
    console.log(`[PushNotificationService] Dispatched push notifications: success=${successCount}, failure=${failureCount}`);
    return { successCount, failureCount };
  }
}

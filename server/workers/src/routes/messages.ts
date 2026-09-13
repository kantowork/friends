import { Hono } from "hono";
import type { HonoEnv } from "../types";
import { authMiddleware } from "../middleware/auth";
import { MessageService } from "../services/messageService";
import { SendMessageRequestSchema } from "@shared/schema";
import type { SendMessageRequest, SendMessageResponse } from "@shared/schema";

export type { SendMessageRequest, SendMessageResponse };

export const messagesRoute = new Hono<HonoEnv>();

/**
 * POST /api/v1/tenants/:tenantId/chats/:chatId/messages
 * 
 * E2EE 暗号化メッセージの保存・親チャットの更新・送信者本人性検証
 */
messagesRoute.post("/", authMiddleware, async (c) => {
  const tenantId = c.req.param("tenantId");
  const chatId = c.req.param("chatId");

  if (!tenantId || !chatId) {
    return c.json({ error: "tenantId and chatId are required", code: "BAD_REQUEST" }, 400);
  }

  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "Invalid JSON payload", code: "BAD_REQUEST" }, 400);
  }

  // 1. Zod スキーマによるリクエストバリデーション
  const parseResult = SendMessageRequestSchema.safeParse(body);
  if (!parseResult.success) {
    return c.json(
      {
        error: "Validation error: Missing or invalid message fields",
        details: parseResult.error.issues,
        code: "VALIDATION_ERROR",
      },
      400
    );
  }

  const { message: msg, members } = parseResult.data;
  const verifiedUser = c.get("user");
  const firestoreClient = c.get("firestore");
  const messageService = new MessageService(firestoreClient);

  console.log(`[messagesRoute] Incoming message: tenantId=${tenantId}, chatId=${chatId}, senderId=${msg.senderId}, verifiedUid=${verifiedUser?.uid}`);

  // 2. 送信者と認証ユーザーの照合評価 (なりすまし防止・業務認可)
  const isAuthorized = await messageService.verifySender(tenantId, msg.senderId, verifiedUser.uid);
  if (!isAuthorized) {
    console.warn(`[messagesRoute] 403 Forbidden: senderId=${msg.senderId} does not match verifiedUid=${verifiedUser?.uid}`);
    return c.json(
      {
        error: "Forbidden: Sender does not match authenticated user",
        senderId: msg.senderId,
        code: "FORBIDDEN",
      },
      403
    );
  }

  // 3. メッセージ保存・親チャット更新 (業務ロジック実行)
  try {
    const result = await messageService.sendMessage({
      tenantId,
      chatId,
      message: msg,
      members,
    });
    return c.json(result, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Internal Server Error";
    return c.json({ error: message, code: "INTERNAL_ERROR" }, 500);
  }
});

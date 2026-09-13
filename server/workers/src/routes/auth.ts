import { Hono } from "hono";
import type { HonoEnv } from "../types";
import { RecoveryService } from "../services/recoveryService";
import { RecoverAnonymousRequestSchema } from "@shared/schema";
import type { RecoverAnonymousRequest, RecoverAnonymousResponse } from "@shared/schema";

export type { RecoverAnonymousRequest, RecoverAnonymousResponse };

export const authRoute = new Hono<HonoEnv>();

/**
 * POST /api/v1/auth/recover-anonymous
 * 
 * 端末移行時の「ふっかつのじゅもん」recoveryHash によるアカウント復旧・Custom Token 発行
 */
authRoute.post("/recover-anonymous", async (c) => {
  let body: unknown;
  try {
    body = await c.req.json();
  } catch {
    return c.json({ error: "Invalid JSON payload", code: "BAD_REQUEST" }, 400);
  }

  // 1. Zod スキーマによるリクエストバリデーション
  const parseResult = RecoverAnonymousRequestSchema.safeParse(body);
  if (!parseResult.success) {
    return c.json(
      {
        error: "Invalid recoveryHash format (must be 64-char hex string)",
        details: parseResult.error.issues,
        code: "INVALID_FORMAT",
      },
      400
    );
  }

  const { recoveryHash } = parseResult.data;
  const firestoreClient = c.get("firestore");
  const recoveryService = new RecoveryService(
    firestoreClient,
    c.env.GOOGLE_CLIENT_EMAIL,
    c.env.GOOGLE_PRIVATE_KEY
  );

  try {
    const record = await recoveryService.findRecoveryRecord(recoveryHash.toLowerCase());
    if (!record) {
      return c.json(
        {
          error: "No account found matching this recovery phrase",
          code: "ACCOUNT_NOT_FOUND",
        },
        404
      );
    }

    // 復旧対象ユーザーの Firebase Auth Custom Token の生成
    const customToken = await recoveryService.createCustomToken(record.uid);

    const responsePayload: RecoverAnonymousResponse = {
      success: true,
      uid: record.uid,
      customToken: customToken,
      encryptedPrivateKey: record.encryptedPrivateKey,
      nonce: record.nonce,
    };

    return c.json(responsePayload, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Internal Server Error";
    return c.json({ error: message, code: "INTERNAL_ERROR" }, 500);
  }
});

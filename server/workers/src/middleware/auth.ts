import type { Context, Next } from "hono";
import type { HonoEnv } from "../types";
import { verifyFirebaseIdToken } from "../lib/jwt";

/**
 * Firebase ID Token 認証ミドルウェア (Authorizer)
 * Authorization: Bearer <token> を抽出し、Google Identity Toolkit で署名・有効期限を検証します。
 * 成功時は検証済みユーザー情報 (uid, email) を c.set('user', ...) へ格納します。
 */
export async function authMiddleware(c: Context<HonoEnv>, next: Next) {
  const authHeader = c.req.header("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return c.json(
      {
        error: "Unauthorized: Bearer token required",
        code: "UNAUTHORIZED",
      },
      401
    );
  }

  const idToken = authHeader.substring("Bearer ".length).trim();
  if (!idToken) {
    return c.json(
      {
        error: "Unauthorized: Token empty",
        code: "UNAUTHORIZED",
      },
      401
    );
  }

  try {
    const verifiedUser = await verifyFirebaseIdToken(idToken, c.env.FIREBASE_API_KEY);
    c.set("user", verifiedUser);
    await next();
  } catch (error) {
    const message = error instanceof Error ? error.message : "Token validation failed";
    return c.json(
      {
        error: `Unauthorized: ${message}`,
        code: "UNAUTHORIZED",
      },
      401
    );
  }
}

import type { Context, Next } from "hono";
import type { HonoEnv } from "../types";
import { FirestoreClient } from "../lib/firestore";

/**
 * サーバー設定値（必須シークレット）検証ミドルウェア
 * 必須環境変数の存在を保証し、FirestoreClient インスタンスをコンテキストへ注入します。
 */
export async function configMiddleware(c: Context<HonoEnv>, next: Next) {
  const missing: string[] = [];
  if (!c.env.FIREBASE_PROJECT_ID) missing.push("FIREBASE_PROJECT_ID");
  if (!c.env.FIREBASE_API_KEY) missing.push("FIREBASE_API_KEY");
  if (!c.env.GOOGLE_CLIENT_EMAIL) missing.push("GOOGLE_CLIENT_EMAIL");
  if (!c.env.GOOGLE_PRIVATE_KEY) missing.push("GOOGLE_PRIVATE_KEY");

  if (missing.length > 0) {
    return c.json(
      {
        error: `Server configuration missing (${missing.join(", ")})`,
        code: "SERVER_CONFIG_MISSING",
      },
      500
    );
  }

  // FirestoreClient をリクエストコンテキストへ注入
  const firestore = new FirestoreClient(
    c.env.FIREBASE_PROJECT_ID,
    c.env.GOOGLE_CLIENT_EMAIL,
    c.env.GOOGLE_PRIVATE_KEY,
    c.env.FIREBASE_API_KEY
  );
  c.set("firestore", firestore);

  await next();
}

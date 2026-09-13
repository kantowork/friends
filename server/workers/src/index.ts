// Friends Cloudflare Workers Serverless API Gateway (Hono Architecture)
import { Hono } from "hono";
import { cors } from "hono/cors";
import type { HonoEnv } from "./types";
import { configMiddleware } from "./middleware/config";
import { authRoute } from "./routes/auth";
import { messagesRoute } from "./routes/messages";

const app = new Hono<HonoEnv>();

// 1. グローバルミドルウェア (CORS & サーバー設定値検証)
app.use("*", cors());
app.use("/api/*", configMiddleware);

// 2. ヘルスチェック
app.get("/api/v1/health", (c) => {
  return c.json({
    status: "ok",
    service: "friends-api",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

// 3. 認証・復旧 API
app.route("/api/v1/auth", authRoute);
app.route("/api/v1/tenants/:tenantId/chats/:chatId/messages", messagesRoute);


// 5. 将来拡張エンドポイント (未実装スタブ)
app.all("/api/v1/notifications/*", (c) => c.json({ error: "Endpoint not yet implemented" }, 501));
app.all("/api/v1/audit/*", (c) => c.json({ error: "Endpoint not yet implemented" }, 501));

// 6. 404 / 500 ハンドラ
app.notFound((c) => {
  return c.json({ error: "Not Found", path: c.req.path }, 404);
});

app.onError((err, c) => {
  const message = err instanceof Error ? err.message : "Unhandled Server Error";
  return c.json({ error: message, code: "INTERNAL_ERROR" }, 500);
});

export default app;

// Friends Cloudflare Workers Serverless API Gateway
import { handleRecoverAnonymous, Env } from "./routes/auth";

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const pathname = url.pathname;

    // CORS プリフライト対応
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    // 共通レスポンスヘルパー
    const jsonResponse = (data: unknown, status = 200) => {
      return new Response(JSON.stringify(data), {
        status,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    };

    // ルーティング
    try {
      // 1. ヘルスチェック
      if (pathname === "/api/v1/health" && request.method === "GET") {
        return jsonResponse({
          status: "ok",
          service: "friends-api",
          version: "1.0.0",
          timestamp: new Date().toISOString(),
        });
      }

      // 2. 認証・復旧 API
      if (pathname === "/api/v1/auth/recover-anonymous") {
        return await handleRecoverAnonymous(request, env);
      }

      // 3. 将来拡張エンドポイント (404 または未実装レスポンス)
      if (pathname.startsWith("/api/v1/notifications/") || pathname.startsWith("/api/v1/audit/")) {
        return jsonResponse({ error: "Endpoint not yet implemented" }, 501);
      }

      // 未定義ルート
      return jsonResponse({ error: "Not Found", path: pathname }, 404);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unhandled Server Error";
      return jsonResponse({ error: message }, 500);
    }
  },
};

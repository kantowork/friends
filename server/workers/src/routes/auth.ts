// 認証・復旧関連ルートハンドラ
import { createFirebaseCustomToken } from "../lib/jwt";
import { FirestoreClient } from "../lib/firestore";

export interface Env {
  FIREBASE_PROJECT_ID: string;
  GOOGLE_CLIENT_EMAIL: string;
  GOOGLE_PRIVATE_KEY: string;
  FIREBASE_API_KEY?: string;
}

const DEFAULT_FIREBASE_API_KEY = "AIzaSyCGtfJeKx84ogLGkwzy8Ic_QHvn0543Hxg";

export async function handleRecoverAnonymous(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = (await request.json()) as { recoveryHash?: string };
    const recoveryHash = body.recoveryHash?.trim();

    if (!recoveryHash || recoveryHash.length !== 64 || !/^[0-9a-fA-F]+$/.test(recoveryHash)) {
      return new Response(
        JSON.stringify({
          error: "Invalid recoveryHash format (must be 64-char hex string)",
          code: "INVALID_FORMAT",
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const missing: string[] = [];
    if (!env.FIREBASE_PROJECT_ID) missing.push("FIREBASE_PROJECT_ID");
    if (!env.GOOGLE_CLIENT_EMAIL) missing.push("GOOGLE_CLIENT_EMAIL");
    if (!env.GOOGLE_PRIVATE_KEY) missing.push("GOOGLE_PRIVATE_KEY");

    if (missing.length > 0) {
      return new Response(
        JSON.stringify({
          error: `Server configuration missing (${missing.join(", ")})`,
          code: "SERVER_CONFIG_MISSING",
        }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const apiKey = env.FIREBASE_API_KEY || DEFAULT_FIREBASE_API_KEY;
    const firestore = new FirestoreClient(
      env.FIREBASE_PROJECT_ID,
      env.GOOGLE_CLIENT_EMAIL,
      env.GOOGLE_PRIVATE_KEY,
      apiKey
    );

    const record = await firestore.findRecoveryRecord(recoveryHash.toLowerCase());
    if (!record) {
      return new Response(
        JSON.stringify({
          error: "No account found matching this recovery phrase",
          code: "ACCOUNT_NOT_FOUND",
        }),
        {
          status: 404,
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      );
    }

    // 復旧対象ユーザーの Firebase Auth Custom Token の生成
    const customToken = await createFirebaseCustomToken(
      env.GOOGLE_CLIENT_EMAIL,
      env.GOOGLE_PRIVATE_KEY,
      record.uid
    );

    return new Response(
      JSON.stringify({
        success: true,
        uid: record.uid,
        customToken: customToken,
        encryptedPrivateKey: record.encryptedPrivateKey,
        nonce: record.nonce,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Internal Server Error";
    return new Response(
      JSON.stringify({
        error: message,
        code: "INTERNAL_ERROR",
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
}

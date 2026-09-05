// 認証・復旧関連ルートハンドラ
import { createFirebaseCustomToken } from "../lib/jwt";
import { FirestoreClient } from "../lib/firestore";

export interface Env {
  FIREBASE_PROJECT_ID: string;
  GOOGLE_CLIENT_EMAIL: string;
  GOOGLE_PRIVATE_KEY: string;
}

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
        JSON.stringify({ error: "Invalid recoveryHash format (must be 64-char hex string)" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    if (!env.FIREBASE_PROJECT_ID || !env.GOOGLE_CLIENT_EMAIL || !env.GOOGLE_PRIVATE_KEY) {
      return new Response(
        JSON.stringify({ error: "Server configuration missing (service account credentials)" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    const firestore = new FirestoreClient(
      env.FIREBASE_PROJECT_ID,
      env.GOOGLE_CLIENT_EMAIL,
      env.GOOGLE_PRIVATE_KEY
    );

    const record = await firestore.findRecoveryRecord(recoveryHash.toLowerCase());
    if (!record) {
      return new Response(
        JSON.stringify({ error: "No account found matching this recovery phrase" }),
        { status: 404, headers: { "Content-Type": "application/json" } }
      );
    }

    // Firebase Auth Custom Token の生成
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
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
}

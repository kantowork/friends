import type { VerifiedUser } from "./lib/jwt";
import type { FirestoreClient } from "./lib/firestore";

/**
 * Cloudflare Workers 環境変数 / Secrets
 */
export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_API_KEY: string;
  GOOGLE_CLIENT_EMAIL: string;
  GOOGLE_PRIVATE_KEY: string;
  ENVIRONMENT?: string;
}

/**
 * Hono コンテキスト変数 (c.set / c.get)
 */
export interface Variables {
  user: VerifiedUser;
  firestore: FirestoreClient;
}

export type HonoEnv = {
  Bindings: Env;
  Variables: Variables;
};

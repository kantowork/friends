import { z } from "zod";
import { withExample } from "./helper.ts";

/**
 * 匿名アカウント復旧リクエストスキーマ
 */
export const RecoverAnonymousRequestSchema = z.object({
  recoveryHash: withExample(
    z
      .string()
      .length(64, "recoveryHash must be a 64-character hex string")
      .regex(/^[0-9a-fA-F]+$/, "recoveryHash must contain only hex characters")
      .describe("64文字 Hex SHA-256 復元ハッシュ"),
    "a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef"
  ),
});

export type RecoverAnonymousRequest = z.infer<typeof RecoverAnonymousRequestSchema>;

/**
 * 匿名アカウント復旧レスポンススキーマ
 */
export const RecoverAnonymousResponseSchema = z.object({
  success: withExample(z.boolean().describe("復旧成否"), true),
  uid: withExample(
    z.string().describe("復旧された Firebase Auth UID"),
    "firebase_auth_uid_12345"
  ),
  customToken: withExample(
    z.string().describe("Firebase ログイン用 Custom Token (JWT)"),
    "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
  ),
  encryptedPrivateKey: withExample(
    z.string().describe("暗号化された Curve25519 秘密鍵 (Base64)"),
    "aW5pdGlhbEVuY3J5cHRlZFByaXZhdGVLZXlFeGFtcGxl..."
  ),
  nonce: withExample(
    z.string().describe("秘密鍵暗号化時の Nonce (Base64)"),
    "nonceExampleBase64=="
  ),
});

export type RecoverAnonymousResponse = z.infer<typeof RecoverAnonymousResponseSchema>;

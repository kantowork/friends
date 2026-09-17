import { z } from "zod";


/**
 * 匿名アカウント復旧リクエストスキーマ
 */
export const RecoverAnonymousRequestSchema = z.object({
  recoveryHash: z
    .string()
    .length(64, "recoveryHash must be a 64-character hex string")
    .regex(/^[0-9a-fA-F]+$/, "recoveryHash must contain only hex characters")
    .describe("64文字 Hex SHA-256 復元ハッシュ")
    .meta({
      example:
        "a1b2c3d4e5f60718293a4b5c6d7e8f901234567890abcdef1234567890abcdef",
    }),
});

export type RecoverAnonymousRequest = z.infer<typeof RecoverAnonymousRequestSchema>;

/**
 * 匿名アカウント復旧レスポンススキーマ
 */
export const RecoverAnonymousResponseSchema = z.object({
  success: z
    .boolean()
    .describe("復旧成否")
    .meta({ example: true }),
  uid: z
    .string()
    .describe("復旧された Firebase Auth UID")
    .meta({ example: "firebase_auth_uid_12345" }),
  customToken: z
    .string()
    .describe("Firebase ログイン用 Custom Token (JWT)")
    .meta({ example: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..." }),
  encryptedPrivateKey: z
    .string()
    .describe("暗号化された Curve25519 秘密鍵 (Base64)")
    .meta({ example: "aW5pdGlhbEVuY3J5cHRlZFByaXZhdGVLZXlFeGFtcGxl..." }),
  nonce: z
    .string()
    .describe("秘密鍵暗号化時の Nonce (Base64)")
    .meta({ example: "nonceExampleBase64==" }),
});

export type RecoverAnonymousResponse = z.infer<typeof RecoverAnonymousResponseSchema>;

import { z } from "zod";


/**
 * 送信メッセージペイロードスキーマ
 */
export const SendMessagePayloadSchema = z.object({
  messageId: z
    .string()
    .min(1, "messageId is required")
    .describe("メッセージID (m_xxx)")
    .meta({ example: "m_1234567890abcdef" }),
  tenantId: z
    .string()
    .min(1, "tenantId is required")
    .describe("テナントID (t_xxx)")
    .meta({ example: "t_preset_default" }),
  chatId: z
    .string()
    .min(1, "chatId is required")
    .describe("チャットID (dm_xxx または gm_xxx)")
    .meta({ example: "dm_u_alice_u_bob" }),
  senderId: z
    .string()
    .min(1, "senderId is required")
    .describe("送信者のユーザーID (u_xxx)")
    .meta({ example: "u_1234567890ab" }),
  keyVersion: z
    .string()
    .min(1, "keyVersion is required")
    .describe("使用暗号鍵バージョン (v_1 等)")
    .meta({ example: "v_1" }),
  ciphertext: z
    .string()
    .min(1, "ciphertext is required")
    .describe("暗号文 (Base64)")
    .meta({ example: "encryptedCiphertextBase64==" }),
  nonce: z
    .string()
    .min(1, "nonce is required")
    .describe("Nonce (Base64)")
    .meta({ example: "nonceExampleBase64==" }),
  messageType: z
    .string()
    .default("text")
    .describe("メッセージ種別 (text / image)")
    .meta({ example: "text" }),
});

export type SendMessagePayload = z.infer<typeof SendMessagePayloadSchema>;

/**
 * メッセージ送信リクエストスキーマ
 */
export const SendMessageRequestSchema = z.object({
  message: SendMessagePayloadSchema.describe("暗号化メッセージペイロード"),
  members: z
    .array(z.string())
    .optional()
    .describe("チャット参加者のユーザーIDリスト (u_xxx)")
    .meta({ example: ["u_alice", "u_bob"] }),
});

export type SendMessageRequest = z.infer<typeof SendMessageRequestSchema>;

/**
 * メッセージ送信レスポンススキーマ
 */
export const SendMessageResponseSchema = z.object({
  success: z
    .boolean()
    .describe("送信成否")
    .meta({ example: true }),
  messageId: z
    .string()
    .describe("送信されたメッセージID")
    .meta({ example: "m_1234567890abcdef" }),
  chatId: z
    .string()
    .describe("対象チャットID")
    .meta({ example: "dm_u_alice_u_bob" }),
  tenantId: z
    .string()
    .describe("対象テナントID")
    .meta({ example: "t_preset_default" }),
});

export type SendMessageResponse = z.infer<typeof SendMessageResponseSchema>;

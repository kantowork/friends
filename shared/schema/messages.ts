import { z } from "zod";
import { withExample, withRef } from "./helper.ts";

/**
 * 送信メッセージペイロードスキーマ
 */
export const SendMessagePayloadSchema = z.object({
  messageId: withExample(
    z.string().min(1, "messageId is required").describe("メッセージID (m_xxx)"),
    "m_1234567890abcdef"
  ),
  tenantId: withExample(
    z.string().min(1, "tenantId is required").describe("テナントID (t_xxx)"),
    "t_preset_default"
  ),
  chatId: withExample(
    z.string().min(1, "chatId is required").describe("チャットID (dm_xxx または gm_xxx)"),
    "dm_u_alice_u_bob"
  ),
  senderId: withExample(
    z.string().min(1, "senderId is required").describe("送信者のユーザーID (u_xxx)"),
    "u_1234567890ab"
  ),
  keyVersion: withExample(
    z.string().min(1, "keyVersion is required").describe("使用暗号鍵バージョン (v_1 等)"),
    "v_1"
  ),
  ciphertext: withExample(
    z.string().min(1, "ciphertext is required").describe("暗号文 (Base64)"),
    "encryptedCiphertextBase64=="
  ),
  nonce: withExample(
    z.string().min(1, "nonce is required").describe("Nonce (Base64)"),
    "nonceExampleBase64=="
  ),
  messageType: withExample(
    z.string().default("text").describe("メッセージ種別 (text / image)"),
    "text"
  ),
});

export type SendMessagePayload = z.infer<typeof SendMessagePayloadSchema>;

/**
 * メッセージ送信リクエストスキーマ
 */
export const SendMessageRequestSchema = z.object({
  message: withRef(
    SendMessagePayloadSchema.describe("暗号化メッセージペイロード"),
    "SendMessagePayload"
  ),
  members: withExample(
    z.array(z.string()).optional().describe("チャット参加者のユーザーIDリスト (u_xxx)"),
    ["u_alice", "u_bob"]
  ),
});

export type SendMessageRequest = z.infer<typeof SendMessageRequestSchema>;

/**
 * メッセージ送信レスポンススキーマ
 */
export const SendMessageResponseSchema = z.object({
  success: withExample(z.boolean().describe("送信成否"), true),
  messageId: withExample(
    z.string().describe("送信されたメッセージID"),
    "m_1234567890abcdef"
  ),
  chatId: withExample(
    z.string().describe("対象チャットID"),
    "dm_u_alice_u_bob"
  ),
  tenantId: withExample(
    z.string().describe("対象テナントID"),
    "t_preset_default"
  ),
});

export type SendMessageResponse = z.infer<typeof SendMessageResponseSchema>;

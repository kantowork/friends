import { z } from "zod";
import { withExample } from "./helper.ts";

/**
 * 共通エラーレスポンススキーマ
 */
export const ErrorResponseSchema = z.object({
  error: withExample(
    z.string().describe("エラーメッセージ"),
    "Unauthorized: Bearer token required"
  ),
  code: withExample(
    z.string().optional().describe("エラーコード"),
    "UNAUTHORIZED"
  ),
  senderId: withExample(
    z.string().optional().describe("認可失敗時の送信者ID"),
    "u_1234567890ab"
  ),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

import { z } from "zod";


/**
 * 共通エラーレスポンススキーマ
 */
export const ErrorResponseSchema = z.object({
  error: z
    .string()
    .describe("エラーメッセージ")
    .meta({ example: "Unauthorized: Bearer token required" }),
  code: z
    .string()
    .optional()
    .describe("エラーコード")
    .meta({ example: "UNAUTHORIZED" }),
  senderId: z
    .string()
    .optional()
    .describe("認可失敗時の送信者ID")
    .meta({ example: "u_1234567890ab" }),
});

export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

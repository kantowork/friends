import type { z } from "zod";

/**
 * Zod スキーマに example メタデータを付与するヘルパー
 */
export function withExample<T extends z.ZodTypeAny>(schema: T, example: unknown): T {
  (schema._def as { example?: unknown }).example = example;
  return schema;
}

/**
 * Zod スキーマに OpenAPI $ref 参照メタデータを付与するヘルパー
 */
export function withRef<T extends z.ZodTypeAny>(schema: T, componentName: string): T {
  (schema._def as { refComponent?: string }).refComponent = componentName;
  return schema;
}

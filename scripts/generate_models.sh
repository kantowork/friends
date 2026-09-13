#!/usr/bin/env bash
set -e

# scripts/generate_models.sh
# 1. shared/model/*.proto (Proto3 ドメインモデル SSOT) -> Apple 公式 swift-protobuf による Swift コード生成
# 2. shared/schema/*.ts (Zod REST API SSOT) -> scripts/generate_api.mjs による TypeScript / Swift 一括自動生成
# を一括同期実行します。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODEL_DIR="${PROJECT_ROOT}/shared/model"
OUTPUT_DIR="${PROJECT_ROOT}/ios/Sources/Models/Generated"

mkdir -p "${OUTPUT_DIR}"

echo "🔄 [Friends Model Generator] 1. Apple 公式 swift-protobuf で Proto3 ドメインモデルを自動生成しています..."

MODEL_FILES=$(find "${MODEL_DIR}" -name "*.proto")
protoc --proto_path="${MODEL_DIR}" --swift_out="${OUTPUT_DIR}" ${MODEL_FILES}

echo "✅ [swift-protobuf] Swift ドメインモデルの自動生成に成功いたしました: ${OUTPUT_DIR}"

echo "🔄 [Friends Model Generator] 2. shared/schema/*.ts (Zod SSoT) から TypeScript & Swift API モデルを一括自動生成しています..."
node --experimental-strip-types "${SCRIPT_DIR}/generate_api.mjs"

echo "🎉 [Friends Model Generator] すべてのモデル・型定義の同期が完了しました。"

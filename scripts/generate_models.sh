#!/usr/bin/env bash
set -e

# scripts/generate_models.sh
# Apple 公式の protoc-gen-swift (swift-protobuf) を使用して
# shared/model/*.proto から Swift プロトコルバッファーコードを自動生成します。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROTO_DIR="${PROJECT_ROOT}/shared/model"
OUTPUT_DIR="${PROJECT_ROOT}/ios/Sources/Models/Generated"

mkdir -p "${OUTPUT_DIR}"

echo "🔄 [Friends Model Generator] Apple 公式 swift-protobuf (protoc-gen-swift) でコードを自動生成しています..."

PROTO_FILES=$(find "${PROTO_DIR}" -name "*.proto")

echo "▶ Executing: protoc --proto_path=\"${PROTO_DIR}\" --swift_out=\"${OUTPUT_DIR}\" ${PROTO_FILES}"

protoc --proto_path="${PROTO_DIR}" --swift_out="${OUTPUT_DIR}" ${PROTO_FILES}

echo "✅ [swift-protobuf] Swift コードの自動生成に成功いたしました: ${OUTPUT_DIR}"

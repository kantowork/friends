#!/usr/bin/env bash
set -euo pipefail

# Friends アプリ用: ビルド & 複数シミュレーター一括配信スクリプト
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IOS_DIR="${WORKSPACE_ROOT}/ios"
PROJECT_PATH="${IOS_DIR}/Friends.xcodeproj"
SCHEME="Friends"
BUNDLE_ID="work.kanto.friends"
BUILD_DIR="${IOS_DIR}/build"

echo "=== 1. プロジェクト同期 (xcodegen) ==="
cd "${IOS_DIR}"
if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate --quiet
fi

# 対象シミュレーター (指定がない場合は Booted の全デバイス、またはデフォルト2台)
# 現在起動中のシミュレーターを取得
BOOTED_DEVICES=($(xcrun simctl list devices | grep -E "Booted" | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/'))

# 引数でデバイスUDIDが渡された場合はそれを使用、なければ起動中デバイス、なければデフォルト定義
TARGET_DEVICES=()
if [ "$#" -gt 0 ]; then
    TARGET_DEVICES=("$@")
elif [ "${#BOOTED_DEVICES[@]}" -gt 0 ]; then
    TARGET_DEVICES=("${BOOTED_DEVICES[@]}")
else
    # フォールバック: iPhone 17e と iPhone SE3
    TARGET_DEVICES=("32595ACD-1D80-4259-92E1-56F9FCB34C4F" "DD39645B-9B2D-4B9A-9943-42BA9C1DBC98")
fi

echo "対象シミュレーター数: ${#TARGET_DEVICES[@]}"

echo "=== 2. アプリのビルド (xcodebuild) ==="
# 最初のターゲットデバイスをビルド先Destinationとして指定
FIRST_DEVICE="${TARGET_DEVICES[0]}"
xcodebuild build \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -destination "id=${FIRST_DEVICE}" \
    -configuration Debug \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -quiet

# 生成された .app パスを検索
APP_PATH=$(find "${BUILD_DIR}/DerivedData/Build/Products/Debug-iphonesimulator" -name "${SCHEME}.app" -maxdepth 1 | head -n 1)

if [ -z "${APP_PATH}" ] || [ ! -d "${APP_PATH}" ]; then
    echo "エラー: ビルド済み .app が見つかりませんでした。"
    exit 1
fi

echo "ビルド成果物: ${APP_PATH}"

echo "=== 3. 各シミュレーターへのインストール & 起動 ==="
for UDID in "${TARGET_DEVICES[@]}"; do
    # デバイス名を取得
    DEV_NAME=$(xcrun simctl list devices | grep "${UDID}" | head -n 1 | sed -E 's/^[[:space:]]*//; s/ \([0-9A-F-]+\).*//')
    echo "----------------------------------------"
    echo "デバイス: ${DEV_NAME:-$UDID} (${UDID})"
    
    # 起動していない場合は起動
    STATE=$(xcrun simctl list devices | grep "${UDID}" | grep -o "Booted" || true)
    if [ "${STATE}" != "Booted" ]; then
        echo "シミュレーターを起動中..."
        xcrun simctl boot "${UDID}" || true
    fi
    
    echo "アプリをインストール中..."
    xcrun simctl install "${UDID}" "${APP_PATH}"
    
    echo "アプリを再起動中..."
    xcrun simctl terminate "${UDID}" "${BUNDLE_ID}" 2>/dev/null || true
    xcrun simctl launch "${UDID}" "${BUNDLE_ID}"
done

echo "----------------------------------------"
echo "✅ すべてのシミュレーターへのビルドと配信が完了しました。"

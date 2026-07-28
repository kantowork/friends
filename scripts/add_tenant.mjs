import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { homedir } from "os";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { v4 as uuidv4, parse as parseUUID } from "uuid";
import bs58 from "bs58";
import { createCipheriv, randomBytes } from "crypto";
import qrcode from "qrcode-terminal";

// ---------------------------------------------------------------------------
// 引数パース & 設定解決
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
const rootDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const defaultPresetPath = join(rootDir, "shared/data/preset-tenant.json");

function generateTenantId() {
  const uuidBytes = parseUUID(uuidv4());
  return `t_${bs58.encode(uuidBytes)}`;
}

// ---------------------------------------------------------------------------
// プリセット設定および既存 PresetTenant.plist の読み込み
// ---------------------------------------------------------------------------
const presetPlistPath = join(rootDir, "ios/Sources/Resources/PresetTenant.plist");
let existingMasterKey = null;

let tenantId = "";
let tenantCode = "";
let tenantName = "";
let isDefaultTenant = false;

if (existsSync(presetPlistPath)) {
  try {
    const plistRaw = readFileSync(presetPlistPath, "utf-8");
    const match = plistRaw.match(/<key>TENANT_MASTER_KEY<\/key>\s*<string>([^<]+)<\/string>/);
    if (match && match[1]) {
      existingMasterKey = match[1].trim();
      console.log(`ℹ️ [Preset] 既存の PresetTenant.plist を検出しました (既存マスターキーを再利用します)`);
    }
  } catch {
    // パース失敗時はスキップ
  }
}

// 1. 引数が無い場合、または --preset / --from-file が渡された場合は preset-tenant.json を読み込み
if (args.length === 0 || args.includes("--preset") || args.includes("--from-file")) {
  const filePathIndex = args.indexOf("--from-file");
  const jsonPath = filePathIndex !== -1 ? args[filePathIndex + 1] : defaultPresetPath;
  if (!existsSync(jsonPath)) {
    console.error(`❌ 指定されたJSONファイルが見つかりません: ${jsonPath}`);
    process.exit(1);
  }
  console.log(`📄 [Friends] '${jsonPath}' からプリセット設定を読み込みます...`);
  const preset = JSON.parse(readFileSync(jsonPath, "utf-8"));
  tenantId = preset.tenantId || "t_sample";
  tenantCode = preset.tenantCode || "sample";
  tenantName = preset.tenantName || "サンプル";
  isDefaultTenant = preset.isDefaultTenant === true;
} else {
  // 2. コマンドライン引数から直接取得
  tenantName = args[0] || "サンプル";
  tenantCode = args[1] || "sample";
  isDefaultTenant = false;
  tenantId = generateTenantId();
}

// ---------------------------------------------------------------------------
// テナントマスターキー (MK_T: 256-bit AES-GCM) の解決 / 自動生成
// ---------------------------------------------------------------------------
let masterKeyBuffer;
let tenantMasterKey;

if (isDefaultTenant && existingMasterKey) {
  tenantMasterKey = existingMasterKey;
  masterKeyBuffer = Buffer.from(existingMasterKey, "base64");
} else {
  masterKeyBuffer = randomBytes(32);
  tenantMasterKey = masterKeyBuffer.toString("base64");
}

// ---------------------------------------------------------------------------
// Project ID の解決: 環境変数 > .firebaserc > エラー
// ---------------------------------------------------------------------------
function resolveProjectId() {
  if (process.env.FIREBASE_PROJECT_ID) return process.env.FIREBASE_PROJECT_ID;
  for (const rcPath of [join(rootDir, ".firebaserc"), join(rootDir, "infra", ".firebaserc")]) {
    try {
      const rc = JSON.parse(readFileSync(rcPath, "utf-8"));
      const id = rc?.projects?.default;
      if (id) return id;
    } catch {
      // ファイルなし or パース失敗
    }
  }
  console.error("❌ Project ID が特定できません。FIREBASE_PROJECT_ID 環境変数を設定するか、.firebaserc を用意してください。");
  process.exit(1);
}

const projectId = resolveProjectId();
// ---------------------------------------------------------------------------
// firebase-admin 初期化 & Firestore 保存
// ---------------------------------------------------------------------------
if (getApps().length === 0) {
  initializeApp({ projectId });
}

const db = getFirestore();

// テナント名 (tenantName) を MK_T で AES-256-GCM 暗号化
const nonce = randomBytes(12);
const cipher = createCipheriv("aes-256-gcm", masterKeyBuffer, nonce);
const encrypted = Buffer.concat([cipher.update(tenantName, "utf8"), cipher.final()]);
const authTag = cipher.getAuthTag();
const combined = Buffer.concat([encrypted, authTag]);

const encryptedTenantName = combined.toString("base64");
const tenantNameNonce = nonce.toString("base64");

try {
  await db.collection("tenants").doc(tenantId).set({
    tenantCode: tenantCode,
    encryptedTenantName: encryptedTenantName,
    tenantNameNonce: tenantNameNonce,
    isDefaultTenant: isDefaultTenant,
    createdAt: FieldValue.serverTimestamp()
  });
} catch (error) {
  console.error("❌ Firestore Error:", error.message);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// 招待ペイロード & QRコードの出力
// ---------------------------------------------------------------------------
const invitePayload = {
  type: "tenant_invite",
  version: 1,
  tenantId: tenantId,
  tenantCode: tenantCode,
  tenantName: tenantName,
  tenantMasterKey: tenantMasterKey,
  isDefaultTenant: isDefaultTenant
};

const tenantJson = JSON.stringify(invitePayload, null, 2);
const qrDataString = `FRIENDS_TENANT:${Buffer.from(JSON.stringify(invitePayload)).toString("base64")}`;

console.log("");
console.log("🚀 [Friends] 新規テナント作成および秘密鍵生成が完了しました！");
console.log(`✅ Cloud Firestore (/tenants/${tenantId}) [Project: ${projectId}]`);
console.log("");
console.log(`📌 内部システムID (不変): ${tenantId}`);
console.log(`🏷  表示用テナントコード: ${tenantCode}`);
console.log(`🏢 テナント表示名:       ${tenantName}`);
console.log(`⭐ デフォルトテナント:   ${isDefaultTenant}`);
console.log("");
console.log("------------------------------------------------------------");
console.log("🔑 テナントマスターキー (MK_T):");
console.log(tenantMasterKey);
console.log("------------------------------------------------------------");
console.log("");
console.log("📱 ログイン画面 モーダル入力用 テナントJSON:");
console.log(tenantJson);
console.log("");
console.log("------------------------------------------------------------");
console.log("📷 [コンソール用 QRコード (iOSアプリでスキャン可能)]:");
qrcode.generate(qrDataString, { small: true });

// ---------------------------------------------------------------------------
// プリセットテナント情報 (PresetTenant.plist) の自動生成 (未存在かつ isDefaultTenant 時)
// ---------------------------------------------------------------------------
if (isDefaultTenant && !existsSync(presetPlistPath)) {
  const plistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<!-- プリセット・デフォルトテナント情報 (npm run tenant:init で自動生成・同期) -->
\t<key>TENANT_ID</key>
\t<string>${tenantId}</string>
\t<key>TENANT_CODE</key>
\t<string>${tenantCode}</string>
\t<key>TENANT_NAME</key>
\t<string>${tenantName}</string>
\t<key>TENANT_MASTER_KEY</key>
\t<string>${tenantMasterKey}</string>
\t<key>IS_DEFAULT_TENANT</key>
\t<true/>
</dict>
</plist>
`;
  try {
    writeFileSync(presetPlistPath, plistContent, "utf-8");
    console.log(`✅ [Preset] iOS プリセット設定を新規作成しました: ${presetPlistPath}`);
  } catch (err) {
    console.warn(`⚠️ [Preset] PresetTenant.plist の作成に失敗しました: ${err.message}`);
  }
} else if (isDefaultTenant) {
  console.log(`ℹ️ [Preset] 既存の PresetTenant.plist を保持しました (再作成・上書きはスキップされました)`);
}

console.log("");
console.log(`🔗 QRデータ文字列: ${qrDataString}`);
console.log("");

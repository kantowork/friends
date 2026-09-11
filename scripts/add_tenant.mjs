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
let workerApiUrl = "";
let r2Config = null;

// 1. 引数が無い場合、または --preset / --from-file が渡された場合は preset-tenant.json を読み込み
if (args.length === 0 || args.includes("--preset") || args.includes("--from-file")) {
  const filePathIndex = args.indexOf("--from-file");
  let jsonPath = filePathIndex !== -1 ? args[filePathIndex + 1] : defaultPresetPath;
  if (!existsSync(jsonPath)) {
    // preset-tenant.json が未作成の場合は .example の確認案内
    const examplePath = join(rootDir, "shared/data/preset-tenant.json.example");
    if (existsSync(examplePath)) {
      console.log(`ℹ️ '${jsonPath}' が見つからないため、テンプレート '${examplePath}' を利用します。`);
      jsonPath = examplePath;
    } else {
      console.error(`❌ 指定されたJSONファイルが見つかりません: ${jsonPath}`);
      process.exit(1);
    }
  }
  console.log(`📄 [Friends] '${jsonPath}' からプリセット設定を読み込みます...`);
  const preset = JSON.parse(readFileSync(jsonPath, "utf-8"));
  tenantId = preset.tenantId || "t_sample";
  tenantCode = preset.tenantCode || "sample";
  tenantName = preset.tenantName || "サンプル";
  isDefaultTenant = preset.isDefaultTenant === true;
  workerApiUrl = preset.workerApiUrl || "";
  r2Config = preset.r2Config || null;
  if (preset.tenantMasterKey) {
    existingMasterKey = preset.tenantMasterKey;
  }
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

if (existingMasterKey) {
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
// プリセット設定 (PresetTenant.plist / R2Config.plist) のローカル自動生成・同期
// ---------------------------------------------------------------------------
const resourcesDir = join(rootDir, "ios/Sources/Resources");
if (!existsSync(resourcesDir)) {
  mkdirSync(resourcesDir, { recursive: true });
}

if (isDefaultTenant) {
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
\t<key>WORKER_API_URL</key>
\t<string>${workerApiUrl || ""}</string>
</dict>
</plist>
`;
  try {
    writeFileSync(presetPlistPath, plistContent, "utf-8");
    console.log(`✅ [Preset] iOS プリセット設定を自動生成・同期しました: ${presetPlistPath}`);
  } catch (err) {
    console.warn(`⚠️ [Preset] PresetTenant.plist の作成に失敗しました: ${err.message}`);
  }
}

if (r2Config) {
  const r2PlistPath = join(resourcesDir, "R2Config.plist");
  const r2PlistContent = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<!-- Cloudflare R2 設定 (npm run tenant:init で自動生成・同期) -->
\t<key>R2_PUBLIC_BASE_URL</key>
\t<string>${r2Config.publicBaseUrl || ""}</string>
\t<key>R2_BUCKET_NAME</key>
\t<string>${r2Config.bucketName || ""}</string>
\t<key>R2_ENDPOINT_URL</key>
\t<string>${r2Config.endpointUrl || ""}</string>
\t<key>R2_ACCESS_KEY_ID</key>
\t<string>${r2Config.accessKeyId || ""}</string>
\t<key>R2_SECRET_ACCESS_KEY</key>
\t<string>${r2Config.secretAccessKey || ""}</string>
</dict>
</plist>
`;
  try {
    writeFileSync(r2PlistPath, r2PlistContent, "utf-8");
    console.log(`✅ [R2] iOS R2設定を自動生成・同期しました: ${r2PlistPath}`);
  } catch (err) {
    console.warn(`⚠️ [R2] R2Config.plist の作成に失敗しました: ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// 招待ペイロード & 二次元コードの出力
// ---------------------------------------------------------------------------
const invitePayload = {
  type: "tenant_invite",
  version: 1,
  tenantId: tenantId,
  tenantCode: tenantCode,
  tenantName: tenantName,
  tenantMasterKey: tenantMasterKey,
  isDefaultTenant: isDefaultTenant,
  ...(workerApiUrl ? { workerApiUrl } : {}),
  ...(r2Config ? { r2Config } : {})
};

const tenantJson = JSON.stringify(invitePayload, null, 2);
const qrDataString = `FRIENDS_TENANT:${Buffer.from(JSON.stringify(invitePayload)).toString("base64")}`;

console.log("");
console.log("🚀 [Friends] テナント設定および秘密鍵生成が完了しました！");
console.log(`📌 内部システムID (不変): ${tenantId}`);
console.log(`🏷  表示用テナントコード: ${tenantCode}`);
console.log(`🏢 テナント表示名:       ${tenantName}`);
console.log(`⭐ デフォルトテナント:   ${isDefaultTenant}`);
if (workerApiUrl) console.log(`⚡️ Workers API URL:    ${workerApiUrl}`);
if (r2Config)     console.log(`📦 R2 Bucket Name:     ${r2Config.bucketName || "設定あり"}`);
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
console.log("📷 [コンソール用 二次元コード (iOSアプリでスキャン可能)]:");
qrcode.generate(qrDataString, { small: true });
console.log("");
console.log(`🔗 二次元コードデータ文字列: ${qrDataString}`);
console.log("");

// ---------------------------------------------------------------------------
// Firestore への保存 (接続可能な場合のみ非ブロッキングで実行)
// ---------------------------------------------------------------------------
if (!args.includes("--local-only")) {
  try {
    if (getApps().length === 0) {
      initializeApp({ projectId });
    }
    const db = getFirestore();

    const nonce = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", masterKeyBuffer, nonce);
    const encrypted = Buffer.concat([cipher.update(tenantName, "utf8"), cipher.final()]);
    const authTag = cipher.getAuthTag();
    const combined = Buffer.concat([encrypted, authTag]);

    const encryptedTenantName = combined.toString("base64");
    const tenantNameNonce = nonce.toString("base64");

    const writePromise = db.collection("tenants").doc(tenantId).set({
      tenantCode: tenantCode,
      encryptedTenantName: encryptedTenantName,
      tenantNameNonce: tenantNameNonce,
      isDefaultTenant: isDefaultTenant,
      createdAt: FieldValue.serverTimestamp()
    });

    const timeoutPromise = new Promise((_, reject) => setTimeout(() => reject(new Error("Timeout")), 3000));
    await Promise.race([writePromise, timeoutPromise]);
    console.log(`✅ Cloud Firestore (/tenants/${tenantId}) に同期完了しました [Project: ${projectId}]`);
  } catch (error) {
    if (error.message === "Timeout") {
      console.log(`ℹ️ [Firestore] クラウドへの同期はスキップされました（ローカル設定のみ同期完了）`);
    } else {
      console.log(`ℹ️ [Firestore] クラウド書き込みスキップ: ${error.message}`);
    }
  }
}
process.exit(0);

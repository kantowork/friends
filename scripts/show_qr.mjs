#!/usr/bin/env node
import { readFileSync, existsSync } from "fs";
import { resolve } from "path";
import qrcode from "qrcode-terminal";

const args = process.argv.slice(2);
let filePath = "shared/data/preset-tenant.json";

const fIndex = args.indexOf("-f");
if (fIndex !== -1 && args[fIndex + 1]) {
  filePath = args[fIndex + 1];
} else if (args.length > 0 && !args[0].startsWith("-")) {
  filePath = args[0];
}

const targetPath = resolve(process.cwd(), filePath);
if (!existsSync(targetPath)) {
  console.error(`❌ ファイルが見つかりません: ${targetPath}`);
  process.exit(1);
}

try {
  const content = readFileSync(targetPath, "utf-8");
  // JSONの場合はminifyしてQRコードの密度を下げ、スキャン精度を高める
  let qrData = content.trim();
  try {
    const parsed = JSON.parse(content);
    qrData = JSON.stringify(parsed);
  } catch {
    // JSON以外の場合はそのまま利用
  }

  console.log(`\n📱 QR Code for: ${filePath}`);
  console.log("------------------------------------------------------------");
  qrcode.generate(qrData, { small: true });
  console.log("------------------------------------------------------------\n");
} catch (err) {
  console.error(`❌ エラー: ${err.message}`);
  process.exit(1);
}

#!/usr/bin/env node

/**
 * sync_legal.mjs
 * 
 * shared/legal/ 配下の利用規約 (terms_of_service.md) および
 * プライバシーポリシー (privacy_policy.md) を、
 * iOS アプリのリソースフォルダ (ios/Sources/Resources/legal/) に同期・組み込むスクリプト。
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

const sharedLegalDir = path.join(rootDir, 'shared', 'legal');
const iosLegalDir = path.join(rootDir, 'ios', 'Sources', 'Resources', 'legal');

if (!fs.existsSync(sharedLegalDir)) {
  console.error(`❌ shared/legal ディレクトリが存在しません: ${sharedLegalDir}`);
  process.exit(1);
}

if (!fs.existsSync(iosLegalDir)) {
  fs.mkdirSync(iosLegalDir, { recursive: true });
  console.log(`📁 作成しました: ${iosLegalDir}`);
}

const files = fs.readdirSync(sharedLegalDir).filter(f => f.endsWith('.md'));

if (files.length === 0) {
  console.warn('⚠️ shared/legal/ 内に .md ファイルが見つかりませんでした。');
  process.exit(0);
}

console.log(`🔄 法的ドキュメントの同期を開始します (${files.length} ファイル)...`);

for (const file of files) {
  const srcPath = path.join(sharedLegalDir, file);
  const dstPath = path.join(iosLegalDir, file);
  
  const content = fs.readFileSync(srcPath, 'utf8');
  fs.writeFileSync(dstPath, content, 'utf8');
  console.log(`  ✅ 同期完了: shared/legal/${file} -> ios/Sources/Resources/legal/${file} (${content.length} bytes)`);
}

console.log('🎉 すべての法的ドキュメントの同期が完了しました。');

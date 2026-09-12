#!/usr/bin/env node

/**
 * generate_licenses.mjs
 *
 * Swift Package Manager (SPM) の Package.resolved および DerivedData のチェックアウトフォルダから、
 * アプリが使用しているすべてのオープンソースライブラリのライセンス情報を抽出し、
 * ios/Sources/Resources/legal/licenses.md に自動集約・出力するスクリプト。
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '..');

// 1. Package.resolved の探索
const resolvedCandidates = [
  path.join(rootDir, 'ios', 'Friends.xcodeproj', 'project.xcworkspace', 'xcshareddata', 'swiftpm', 'Package.resolved'),
  path.join(rootDir, 'ios', 'build', 'DerivedData', 'SourcePackages', 'Package.resolved')
];

let resolvedPath = resolvedCandidates.find(p => fs.existsSync(p));
if (!resolvedPath) {
  const homeDir = process.env.HOME || '';
  const derivedDataRoot = path.join(homeDir, 'Library', 'Developer', 'Xcode', 'DerivedData');
  try {
    if (fs.existsSync(derivedDataRoot)) {
      const entries = fs.readdirSync(derivedDataRoot);
      for (const entry of entries) {
        if (entry.startsWith('Friends-')) {
          const candidate = path.join(derivedDataRoot, entry, 'SourcePackages', 'Package.resolved');
          if (fs.existsSync(candidate)) {
            resolvedPath = candidate;
            break;
          }
        }
      }
    }
  } catch (e) {
    // ignore sandbox EPERM
  }
}

if (!resolvedPath) {
  console.error('❌ Package.resolved が見つかりませんでした。先に Xcode でパッケージを解決してください。');
  process.exit(1);
}

console.log(`📄 Package.resolved: ${resolvedPath}`);
const resolvedData = JSON.parse(fs.readFileSync(resolvedPath, 'utf8'));
const pins = resolvedData.pins || [];
console.log(`📦 検出された依存パッケージ数: ${pins.length}`);

// 2. checkouts ディレクトリの探索
const checkoutsCandidates = [
  path.join(rootDir, 'ios', 'build', 'DerivedData', 'SourcePackages', 'checkouts'),
];

const homeDir = process.env.HOME || '';
const derivedDataRoot = path.join(homeDir, 'Library', 'Developer', 'Xcode', 'DerivedData');
try {
  if (fs.existsSync(derivedDataRoot)) {
    const entries = fs.readdirSync(derivedDataRoot);
    for (const entry of entries) {
      if (entry.startsWith('Friends-')) {
        checkoutsCandidates.push(path.join(derivedDataRoot, entry, 'SourcePackages', 'checkouts'));
      }
    }
  }
} catch (e) {
  // ignore
}

const checkoutsDir = checkoutsCandidates.find(p => fs.existsSync(p));
if (checkoutsDir) {
  console.log(`📂 checkouts ディレクトリ: ${checkoutsDir}`);
} else {
  console.warn('⚠️ checkouts ディレクトリが見つかりませんでした。');
}

// 3. ライセンスファイル探索ヘルパー
const licenseFilePatterns = [
  /^license(\.(md|txt|rst))?$/i,
  /^licence(\.(md|txt|rst))?$/i,
  /^copying(\.(md|txt|rst))?$/i,
  /^copyright(\.(md|txt|rst))?$/i
];

function findLicenseInDir(dirPath) {
  if (!fs.existsSync(dirPath)) return null;
  try {
    const files = fs.readdirSync(dirPath);
    for (const pattern of licenseFilePatterns) {
      const match = files.find(f => pattern.test(f));
      if (match) {
        return fs.readFileSync(path.join(dirPath, match), 'utf8');
      }
    }
  } catch (e) {
    // ignore
  }
  return null;
}

const results = [];

for (const pin of pins) {
  const name = pin.identity;
  const location = pin.location;
  let licenseText = null;

  if (checkoutsDir) {
    const candidates = [
      path.join(checkoutsDir, name),
      path.join(checkoutsDir, path.basename(location, '.git')),
      path.join(checkoutsDir, name.toLowerCase())
    ];

    for (const c of candidates) {
      licenseText = findLicenseInDir(c);
      if (licenseText) break;
    }
  }

  if (!licenseText) {
    licenseText = `License text not bundled locally.\nPlease visit repository: ${location}`;
  }

  results.push({
    name: name,
    license: licenseText.trim()
  });
}

// 名前順（アルファベット順）にソート
results.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));

// 4. Markdown の構築
let mdContent = `# オープンソースライセンス (Open Source Licenses)

本アプリケーションでは、以下のオープンソースソフトウェア(OSS)を使用しています。各ソフトウェアの著作権者およびライセンス条項は以下のとおりです。

---
`;

results.forEach((item, index) => {
  mdContent += `
**${item.name}**

${item.license}
`;
});

// 5. 出力先 (ios/Sources/Resources/legal/licenses.md)
const iosOutputDir = path.join(rootDir, 'ios', 'Sources', 'Resources', 'legal');
if (!fs.existsSync(iosOutputDir)) {
  fs.mkdirSync(iosOutputDir, { recursive: true });
}
const iosOutputPath = path.join(iosOutputDir, 'licenses.md');
fs.writeFileSync(iosOutputPath, mdContent, 'utf8');

console.log(`✅ ${results.length} 件のライセンス情報をパッケージ情報から出力しました:`);
console.log(`  - ${iosOutputPath}`);

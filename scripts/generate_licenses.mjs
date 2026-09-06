#!/usr/bin/env node

/**
 * generate_licenses.mjs
 * 
 * Swift Package Manager (SPM) の Package.resolved および DerivedData のチェックアウトフォルダから、
 * アプリが使用しているすべてのオープンソースライブラリのライセンス情報を抽出し、
 * ios/Sources/Resources/licenses.json に自動集約・出力するスクリプト。
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
  // ~/Library/Developer/Xcode/DerivedData/Friends-*/SourcePackages/Package.resolved を検索
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
  path.join(rootDir, 'ios', 'build', 'DerivedDataTest', 'SourcePackages', 'checkouts')
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
  // sandbox環境下でのパーミッション制約をスキップ
}

const checkoutsDir = checkoutsCandidates.find(p => fs.existsSync(p));
console.log(`📂 checkouts ディレクトリ: ${checkoutsDir || 'なし (フォールバック使用)'}`);

const licenseFileNames = [
  'LICENSE', 'LICENSE.md', 'LICENSE.txt', 'LICENSE.rst',
  'LICENCE', 'LICENCE.md', 'LICENCE.txt',
  'COPYING', 'COPYING.txt'
];

function findLicenseInDir(dir) {
  if (!fs.existsSync(dir)) return null;
  const files = fs.readdirSync(dir);
  for (const name of licenseFileNames) {
    const match = files.find(f => f.toLowerCase() === name.toLowerCase());
    if (match) {
      const fullPath = path.join(dir, match);
      if (fs.statSync(fullPath).isFile()) {
        return fs.readFileSync(fullPath, 'utf8');
      }
    }
  }
  return null;
}

// パッケージの表示名マッピング
const friendlyNames = {
  'firebase-ios-sdk': 'Firebase iOS SDK',
  'swift-protobuf': 'SwiftProtobuf',
  'swift-crypto': 'Apple Swift Crypto',
  'swift-asn1': 'Apple Swift ASN.1',
  'swift-mnemonic': 'SwiftMnemonic',
  'swift-base58': 'SwiftBase58',
  'base58swift': 'Base58Swift',
  'ulid.swift': 'ULID.swift',
  'bigint': 'BigInt',
  'promises': 'Google Promises',
  'googleutilities': 'Google Utilities',
  'googledatatransport': 'Google Data Transport',
  'googleappmeasurement': 'Google App Measurement',
  'google-ads-on-device-conversion-ios-sdk': 'Google Ads On-Device Conversion',
  'app-check': 'Firebase App Check',
  'interop-ios-for-google-sdks': 'Google SDK Interop for iOS',
  'gtm-session-fetcher': 'Google Toolbox for Mac Session Fetcher',
  'grpc-binary': 'gRPC Binary',
  'abseil-cpp-binary': 'Abseil C++ Binary',
  'nanopb': 'nanopb',
  'leveldb': 'LevelDB'
};

const results = [];

for (const pin of pins) {
  const identity = pin.identity;
  const location = pin.location || '';
  const version = pin.state?.version || pin.state?.revision?.substring(0, 7) || 'latest';
  const name = friendlyNames[identity.toLowerCase()] || identity;

  let licenseText = null;

  if (checkoutsDir) {
    // フォルダ名候補（identity そのまま、または location の末尾）
    const candidates = [
      path.join(checkoutsDir, identity),
      path.join(checkoutsDir, path.basename(location, '.git')),
      path.join(checkoutsDir, identity.toLowerCase())
    ];

    for (const c of candidates) {
      licenseText = findLicenseInDir(c);
      if (licenseText) break;
    }
  }

  // ライセンスが見つからない場合の標準フォールバック
  if (!licenseText) {
    licenseText = `License text not bundled locally.\nPlease visit repository: ${location}`;
  }

  results.push({
    id: identity,
    name: name,
    version: version,
    url: location,
    license: licenseText.trim()
  });
}

// 名前順（アルファベット順）にソート
results.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));

// 出力先
const outputDir = path.join(rootDir, 'ios', 'Sources', 'Resources');
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

const outputPath = path.join(outputDir, 'licenses.json');
fs.writeFileSync(outputPath, JSON.stringify(results, null, 2), 'utf8');

console.log(`✅ ${results.length} 件のライセンス情報を ${outputPath} に出力しました。`);

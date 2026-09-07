#!/usr/bin/env swift

import AppKit
import Foundation

// プロジェクトルートパスの解決
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let rootDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent().path

let svgPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "\(rootDir)/shared/data/friends.icon.svg"
let xcassetsDir = "\(rootDir)/ios/Sources/Assets.xcassets"
let appIconSetDir = "\(xcassetsDir)/AppIcon.appiconset"
let pngPath = "\(appIconSetDir)/AppIcon.png"

guard FileManager.default.fileExists(atPath: svgPath) else {
    fputs("❌ SVGファイルが存在しません: \(svgPath)\n", stderr)
    exit(1)
}

// 1. ディレクトリの準備
try FileManager.default.createDirectory(atPath: appIconSetDir, withIntermediateDirectories: true)

// 2. Assets.xcassets/Contents.json
let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try rootContents.write(toFile: "\(xcassetsDir)/Contents.json", atomically: true, encoding: .utf8)

// 3. AppIcon.appiconset/Contents.json (Xcode 14+ Single Size)
let appIconContents = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try appIconContents.write(toFile: "\(appIconSetDir)/Contents.json", atomically: true, encoding: .utf8)

// 4. FriendsIcon.imageset の準備 (SwiftUI Image("FriendsIcon") 用)
let imagesetDir = "\(xcassetsDir)/FriendsIcon.imageset"
try FileManager.default.createDirectory(atPath: imagesetDir, withIntermediateDirectories: true)

let imagesetContents = """
{
  "images" : [
    {
      "filename" : "FriendsIcon.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try imagesetContents.write(toFile: "\(imagesetDir)/Contents.json", atomically: true, encoding: .utf8)

// 5. SVG -> 1024x1024 PNG のラスタライズ
print("🎨 AppIcon.png および FriendsIcon.png (1024x1024) を生成中...")

guard let image = NSImage(contentsOfFile: svgPath) else {
    fputs("❌ Failed to load SVG from \(svgPath)\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = NSSize(width: 1024, height: 1024)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
           from: NSRect(origin: .zero, size: image.size),
           operation: .copy,
           fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("❌ Failed to create PNG representation\n", stderr)
    exit(1)
}

try data.write(to: URL(fileURLWithPath: pngPath))
let friendsIconPngPath = "\(imagesetDir)/FriendsIcon.png"
try data.write(to: URL(fileURLWithPath: friendsIconPngPath))

print("✅ アプリアイコンおよび FriendsIcon.imageset の生成が完了しました:")
print("  - \(pngPath)")
print("  - \(friendsIconPngPath)")

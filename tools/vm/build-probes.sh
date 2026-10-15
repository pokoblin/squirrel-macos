#!/bin/bash
# 编译测试小工具，输出到 tools/vm/ 下（测试机里通过共享文件夹 /Volumes/My Shared Files/vm/ 访问）
set -euo pipefail
cd "$(dirname "$0")"

clang -O2 -Wall -o rime-type-probe rime-type-probe.c
echo "已编译 tools/vm/rime-type-probe"

APP=TRProbe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O tr-probe.swift -o "$APP/Contents/MacOS/TRProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.squirrel-macos.tr-probe</string>
  <key>CFBundleName</key><string>TRProbe</string>
  <key>CFBundleExecutable</key><string>TRProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "已编译 tools/vm/$APP"

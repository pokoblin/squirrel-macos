#!/bin/bash
# 编译应用并拼成 .build/app/squirrel-macos.app（本机临时签名，只给测试机用）。
# 不要在宿主机上运行这个应用：它会读写真实的 ~/Library/Rime。
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --product SquirrelMacOSApp >&2
BIN="$(swift build --show-bin-path)"
APP=".build/app/squirrel-macos.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SquirrelMacOSApp" "$APP/Contents/MacOS/"
# RimeKit 的资源包（方案清单）：Bundle.module 会在 Contents/Resources 里找
cp -R "$BIN/SquirrelMacOS_RimeKit.bundle" "$APP/Contents/Resources/"
cp tools/app/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >&2
echo "$APP"

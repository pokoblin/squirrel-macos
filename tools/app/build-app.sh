#!/bin/bash
# 编译应用并拼成 .build/app/鼠须管助手.app，最后一行输出它的路径。
# 默认：debug 编译、本机临时签名，只给测试机用（./tools/vm/install-app.sh）。
# 发布：CONFIGURATION=release SIGN_IDENTITY="Developer ID Application: …" 用正式身份签名
#       （打开 hardened runtime、加时间戳），由 tools/release/build-release.sh 调用。
# 不要在宿主机上运行这个应用：它会读写真实的 ~/Library/Rime。
set -euo pipefail
cd "$(dirname "$0")/../.."
CONFIGURATION="${CONFIGURATION:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
swift build -c "$CONFIGURATION" --product SquirrelMacOSApp >&2
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP=".build/app/鼠须管助手.app"
rm -rf .build/app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SquirrelMacOSApp" "$APP/Contents/MacOS/"
# RimeKit 的资源包（方案清单）：Bundle.module 会在 Contents/Resources 里找
cp -R "$BIN/SquirrelMacOS_RimeKit.bundle" "$APP/Contents/Resources/"
cp tools/app/Info.plist "$APP/Contents/Info.plist"
cp LICENSE THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP" >&2
else
  # 里面的资源包先用同一个身份重签（SwiftPM 给它的是临时签名）
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/SquirrelMacOS_RimeKit.bundle" >&2
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP" >&2
fi
echo "$APP"

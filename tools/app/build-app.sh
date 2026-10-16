#!/bin/bash
# 编译应用并拼成 .build/app/SquirrelHelper.app，最后一行输出它的路径。
# 应用名按系统语言显示：中文系统是「鼠须管助手」，其他是 SquirrelHelper（tools/app/*.lproj）。
# 默认：debug 编译、本机临时签名，只给测试机用（./tools/vm/install-app.sh）。
# 发布：CONFIGURATION=release SIGN_IDENTITY="Developer ID Application: …" 用正式身份签名
#       （打开 hardened runtime、加时间戳），由 tools/release/build-release.sh 调用。
# 不要在宿主机上运行这个应用：它会读写真实的 ~/Library/Rime。
set -euo pipefail
cd "$(dirname "$0")/../.."
CONFIGURATION="${CONFIGURATION:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
swift build -c "$CONFIGURATION" --product SquirrelMacOSApp >&2
swift build -c "$CONFIGURATION" --product rime-preview-helper >&2
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP=".build/app/SquirrelHelper.app"
rm -rf .build/app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/SquirrelMacOSApp" "$APP/Contents/MacOS/"
# 试打的辅助程序（加载鼠须管的 librime，所以单独签、带 disable-library-validation）
cp "$BIN/rime-preview-helper" "$APP/Contents/Helpers/"
# RimeKit 的资源包（方案清单）：Bundle.module 会在 Contents/Resources 里找
cp -R "$BIN/SquirrelMacOS_RimeKit.bundle" "$APP/Contents/Resources/"
cp tools/app/Info.plist "$APP/Contents/Info.plist"
cp -R tools/app/*.lproj "$APP/Contents/Resources/"
# 应用图标（由 tools/app/make-icon.sh 生成）
cp tools/app/AppIcon.icns "$APP/Contents/Resources/"
cp LICENSE THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/"
# 签名顺序：资源包 → 辅助程序（带 entitlement）→ 应用本身（不带）。不用 --deep：它会把辅助程序的 entitlement 覆盖掉。
HELPER_ENT="tools/app/preview-helper.entitlements"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP/Contents/Resources/SquirrelMacOS_RimeKit.bundle" >&2
  codesign --force --sign - --entitlements "$HELPER_ENT" "$APP/Contents/Helpers/rime-preview-helper" >&2
  codesign --force --sign - "$APP" >&2
else
  # 资源包先用同一个身份重签（SwiftPM 给它的是临时签名）
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/SquirrelMacOS_RimeKit.bundle" >&2
  codesign --force --options runtime --timestamp --entitlements "$HELPER_ENT" --sign "$SIGN_IDENTITY" "$APP/Contents/Helpers/rime-preview-helper" >&2
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP" >&2
fi
echo "$APP"

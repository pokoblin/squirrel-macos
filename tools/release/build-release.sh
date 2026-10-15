#!/bin/bash
# 打发布包：release 编译 → Developer ID 签名（hardened runtime）→ 公证 → 钉上公证票据 → 打 zip、算 sha256。
# 用法：
#   ./tools/release/build-release.sh                    完整流程（先按 docs/release.md 存好公证凭据）
#   SKIP_NOTARIZE=1 ./tools/release/build-release.sh    只签名、不公证（试流程用）
# 环境变量：SIGN_IDENTITY（默认 TONDA K.K. 的 Developer ID）、NOTARY_PROFILE（默认 squirrel-helper-notary）
# 版本号取自 tools/app/Info.plist 的 CFBundleShortVersionString。
set -euo pipefail
cd "$(dirname "$0")/../.."
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: TONDA K.K. (VS555M5VA8)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-squirrel-helper-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' tools/app/Info.plist)"
OUT=".build/release-out"
ZIP="$OUT/SquirrelHelper-$VERSION.zip"
rm -rf "$OUT"
mkdir -p "$OUT"

APP="$(CONFIGURATION=release SIGN_IDENTITY="$SIGN_IDENTITY" ./tools/app/build-app.sh | tail -1)"
codesign --verify --deep --strict --verbose=2 "$APP" >&2

if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
  echo "注意：没有公证（SKIP_NOTARIZE=1），这个包不能发布" >&2
else
  ditto -c -k --norsrc --noextattr --keepParent "$APP" "$OUT/upload.zip"
  result="$(xcrun notarytool submit "$OUT/upload.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)"
  status="$(printf '%s' "$result" | plutil -extract status raw -o - -)"
  id="$(printf '%s' "$result" | plutil -extract id raw -o - -)"
  echo "公证结果：$status（$id）" >&2
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
    exit 1
  fi
  rm "$OUT/upload.zip"
  xcrun stapler staple "$APP" >&2
  xcrun stapler validate "$APP" >&2
  spctl --assess --type execute --verbose=4 "$APP" >&2
fi

ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
# 不带扩展属性：否则 zip 里会有 ._ 文件，用命令行 unzip 等工具解开后签名失效、被当成「已损坏」
[ "${SKIP_NOTARIZE:-}" = "1" ] || ./tools/release/check-zip.sh "$ZIP" >&2
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "$ZIP"

#!/bin/bash
# 打发布包（dmg）：release 编译 → Developer ID 签名（hardened runtime）→ 公证应用、钉票据
#   → 做 dmg（应用 + 指向「应用程序」的快捷方式）→ 给 dmg 签名 → 公证 dmg、钉票据 → 算 sha256。
# 应用和 dmg 都钉了票据：从 dmg 里拖出来的应用，没联网也能通过 Gatekeeper。
# 用法：
#   ./tools/release/build-release.sh                    完整流程（要先存好公证凭据，见下）
#   SKIP_NOTARIZE=1 ./tools/release/build-release.sh    只签名、不公证（试流程用）
# 环境变量：SIGN_IDENTITY（默认 TONDA K.K. 的 Developer ID）、NOTARY_PROFILE（默认 squirrel-helper-notary）
# 版本号取自 tools/app/Info.plist 的 CFBundleShortVersionString。
# 第一次在一台 Mac 上发布时存公证凭据（App 专用密码自己输入）：
#   xcrun notarytool store-credentials squirrel-helper-notary --apple-id <Apple ID> --team-id VS555M5VA8
set -euo pipefail
cd "$(dirname "$0")/../.."
# 发布包要和提交对得上：工作区有没提交的改动就不打包（试流程可以加 ALLOW_DIRTY=1）
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-}" != "1" ]; then
  echo "工作区有没提交的改动，先提交再打发布包（只是试流程的话加 ALLOW_DIRTY=1）" >&2
  exit 1
fi
# 内置清单要和已发布的在线清单一样：不然内置的比在线的新，在线那份就不起作用了
if ! cmp -s Sources/RimeKit/Resources/catalog.json catalog/v1/catalog.json; then
  echo "内置方案清单和 catalog/v1/catalog.json 不一样：先用 ./tools/catalog/publish.sh 发布清单，再打发布包" >&2
  exit 1
fi
echo "提交：$(git rev-parse --short HEAD)" >&2
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: TONDA K.K. (VS555M5VA8)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-squirrel-helper-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' tools/app/Info.plist)"
OUT=".build/release-out"
DMG="$OUT/SquirrelHelper-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT"

# 交给苹果公证并等结果。失败（断网、超时、被拒）时也要留下结果和 submission id，不让 set -e 直接退出
notarize() {
  local file="$1" name="$2"
  local result status id
  result="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || true
  printf '%s\n' "$result" > "$OUT/notary-$name.json"
  status="$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)"
  echo "公证结果（${name}）：${status:-（没拿到）}（${id:-没有 id}）" >&2
  if [ "$status" != "Accepted" ]; then
    if [ -n "$id" ]; then xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true; fi
    echo "公证没通过，完整结果在 $OUT/notary-$name.json" >&2
    exit 1
  fi
}

APP="$(CONFIGURATION=release SIGN_IDENTITY="$SIGN_IDENTITY" ./tools/app/build-app.sh | tail -1)"
codesign --verify --deep --strict --verbose=2 "$APP" >&2
./tools/release/check-entitlements.sh "$APP" --release >&2

# 1. 公证应用本身，把票据钉在应用上
if [ "${SKIP_NOTARIZE:-}" = "1" ]; then
  echo "注意：没有公证（SKIP_NOTARIZE=1），这个包不能发布" >&2
else
  ditto -c -k --norsrc --noextattr --keepParent "$APP" "$OUT/upload.zip"
  notarize "$OUT/upload.zip" app
  rm "$OUT/upload.zip"
  xcrun stapler staple "$APP" >&2
  xcrun stapler validate "$APP" >&2
  spctl --assess --type execute --verbose=4 "$APP" >&2
fi

# 2. 做 dmg：打开后是应用和「应用程序」快捷方式，用户把应用拖过去就装好了
ROOT="$OUT/dmg-root"
mkdir -p "$ROOT"
ditto "$APP" "$ROOT/$(basename "$APP")"
ln -s /Applications "$ROOT/Applications"
hdiutil create -volname "SquirrelHelper $VERSION" -srcfolder "$ROOT" -fs HFS+ -format UDZO -ov "$DMG" >&2
rm -rf "$ROOT"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG" >&2

# 3. 公证 dmg，把票据钉在 dmg 上
if [ "${SKIP_NOTARIZE:-}" != "1" ]; then
  notarize "$DMG" dmg
  xcrun stapler staple "$DMG" >&2
  ./tools/release/check-dmg.sh "$DMG" >&2
fi
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "$DMG"

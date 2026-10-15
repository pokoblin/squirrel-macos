#!/bin/bash
# 打发布包：release 编译 → Developer ID 签名（hardened runtime）→ 公证 → 钉上公证票据 → 打 zip、算 sha256。
# 用法：
#   ./tools/release/build-release.sh                    完整流程（先按 docs/release.md 存好公证凭据）
#   SKIP_NOTARIZE=1 ./tools/release/build-release.sh    只签名、不公证（试流程用）
# 环境变量：SIGN_IDENTITY（默认 TONDA K.K. 的 Developer ID）、NOTARY_PROFILE（默认 squirrel-helper-notary）
# 版本号取自 tools/app/Info.plist 的 CFBundleShortVersionString。
set -euo pipefail
cd "$(dirname "$0")/../.."
# 发布包要和提交对得上：工作区有没提交的改动就不打包（试流程可以加 ALLOW_DIRTY=1）
if [ -n "$(git status --porcelain)" ] && [ "${ALLOW_DIRTY:-}" != "1" ]; then
  echo "工作区有没提交的改动，先提交再打发布包（只是试流程的话加 ALLOW_DIRTY=1）" >&2
  exit 1
fi
echo "提交：$(git rev-parse --short HEAD)" >&2
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
  # 失败（断网、超时、被拒）时也要留下结果和 submission id，不让 set -e 直接退出
  result="$(xcrun notarytool submit "$OUT/upload.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)" || true
  printf '%s\n' "$result" > "$OUT/notary.json"
  status="$(printf '%s' "$result" | plutil -extract status raw -o - - 2>/dev/null || true)"
  id="$(printf '%s' "$result" | plutil -extract id raw -o - - 2>/dev/null || true)"
  echo "公证结果：${status:-（没拿到）}（${id:-没有 id}）" >&2
  if [ "$status" != "Accepted" ]; then
    if [ -n "$id" ]; then xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true; fi
    echo "公证没通过，完整结果在 $OUT/notary.json" >&2
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

#!/bin/bash
# 发布在线方案清单（在线方案清单设计 5.1）：校验 → 复制到 catalog/v1/ → 签名。提交、推送另外问过再做。
#   ./tools/catalog/publish.sh                   校验、复制、签名
#   ./tools/catalog/publish.sh --verify-remote   推送以后，从 GitHub 拉回来再验一次
set -euo pipefail
cd "$(dirname "$0")/../.."
SERVICE="squirrel-macos-catalog-signing"
SOURCE="Sources/RimeKit/Resources/catalog.json"
DEST="catalog/v1"
REMOTE="https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1"
swift build --product rimectl >/dev/null
RIMECTL=".build/debug/rimectl"

if [[ "${1:-}" == "--verify-remote" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$REMOTE/catalog.json" -o "$TMP/catalog.json"
  curl -fsSL "$REMOTE/catalog.json.sig" -o "$TMP/catalog.json.sig"
  "$RIMECTL" catalog verify "$TMP/catalog.json" "$TMP/catalog.json.sig"
  if ! cmp -s "$TMP/catalog.json" "$DEST/catalog.json"; then
    echo "GitHub 上的清单和本地 $DEST 不一样：可能还没推送，或者 GitHub 还在用缓存（几分钟后再试）" >&2
    exit 1
  fi
  echo "GitHub 上的方案清单签名正确，和本地一致"
  exit 0
fi

mkdir -p "$DEST"
"$RIMECTL" catalog verify-source "$SOURCE" "$DEST/catalog.json"
cp "$SOURCE" "$DEST/catalog.json"
security find-generic-password -s "$SERVICE" -w | "$RIMECTL" catalog sign "$DEST/catalog.json" --out "$DEST/catalog.json.sig"
"$RIMECTL" catalog verify "$DEST/catalog.json" "$DEST/catalog.json.sig"
echo "已写好 $DEST/catalog.json 和签名。接下来："
echo "  1. swift test；RIMEKIT_ONLINE=1 swift test --filter 真实下载内置清单里的包；加了新方案的话再跑 OnlineGenerateTests"
echo "  2. 问过以后提交、推送 main"
echo "  3. ./tools/catalog/publish.sh --verify-remote，然后 RIMEKIT_ONLINE=1 swift test --filter OnlineTests"

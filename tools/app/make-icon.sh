#!/bin/bash
# 由 tools/app/AppIcon-source.png（1024×1024、圆角方形铺满整张图）生成 tools/app/AppIcon.icns。
# 按 macOS 图标网格：圆角方形缩到 824×824，四周留 100 像素透明边，和别的应用在程序坞里一样大。
# 换图标后运行一次，把生成的 AppIcon.icns 一起提交。
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sips -z 824 824 AppIcon-source.png --out "$TMP/body.png" >/dev/null
sips -p 1024 1024 "$TMP/body.png" --out "$TMP/full.png" >/dev/null
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$TMP/full.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$TMP/full.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o AppIcon.icns
echo "tools/app/AppIcon.icns"

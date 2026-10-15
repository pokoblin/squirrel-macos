#!/bin/bash
# 检查发布用的 zip：用命令行 unzip（不认 AppleDouble 的 ._ 文件）解开后，签名和公证票据都还有效。
# 用法：./tools/release/check-zip.sh .build/release-out/SquirrelHelper-<版本>.zip
set -euo pipefail
zip="${1:?用法：$0 <zip>}"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
if unzip -l "$zip" | grep -q '/\._'; then
  echo "zip 里有 ._ 文件（扩展属性），别的解压工具解开后签名会失效" >&2
  exit 1
fi
unzip -q "$zip" -d "$dir"
app="$(find "$dir" -maxdepth 1 -name '*.app' | head -1)"
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app" >/dev/null
echo "ok：$zip"

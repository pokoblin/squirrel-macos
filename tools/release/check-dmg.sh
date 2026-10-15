#!/bin/bash
# 检查发布用的 dmg：dmg 本身签了名、钉了公证票据，Gatekeeper 认；挂载后里面的应用签名有效、也钉了票据，
# 还有指向「应用程序」的快捷方式。只挂载、不运行应用。
# 用法：./tools/release/check-dmg.sh .build/release-out/SquirrelHelper-<版本>.dmg
set -euo pipefail
dmg="${1:?用法：$0 <dmg>}"
codesign --verify --verbose=2 "$dmg"
xcrun stapler validate "$dmg" >/dev/null
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
mount="$(mktemp -d)"
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dmg" >/dev/null
trap 'hdiutil detach "$mount" -quiet || true; rmdir "$mount" 2>/dev/null || true' EXIT
app="$(find "$mount" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$app" ] || { echo "dmg 里没有应用" >&2; exit 1; }
[ "$(readlink "$mount/Applications")" = "/Applications" ] || { echo "dmg 里没有「应用程序」快捷方式" >&2; exit 1; }
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app" >/dev/null
echo "ok：$dmg"

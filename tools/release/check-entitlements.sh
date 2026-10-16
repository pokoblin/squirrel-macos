#!/bin/bash
# 检查应用包里试打辅助程序的签名：
#   1. Contents/Helpers/rime-preview-helper 存在、签名有效
#   2. 辅助程序有 com.apple.security.cs.disable-library-validation（否则加载不了鼠须管的 librime）
#   3. 主程序没有这个 entitlement（主程序保持库验证）
#   加 --release 时：4. 辅助程序和主程序都打开了 hardened runtime
# 用法：./tools/release/check-entitlements.sh <应用> [--release]
# 不满足就非零退出，并说明是哪一条。
set -euo pipefail
app="${1:?用法：$0 <应用> [--release]}"
release=0
[ "${2:-}" = "--release" ] && release=1
KEY="com.apple.security.cs.disable-library-validation"
helper="$app/Contents/Helpers/rime-preview-helper"
main="$app/Contents/MacOS/SquirrelMacOSApp"

fail() { echo "失败：$1" >&2; exit 1; }

[ -d "$app" ] || fail "找不到应用：$app"
[ -f "$helper" ] || fail "应用里没有辅助程序（$helper）"
[ -f "$main" ] || fail "应用里没有主程序（$main）"
codesign --verify --strict "$helper" 2>/dev/null || fail "辅助程序的签名无效"

# 这个 entitlement 是不是 true；没有这个键、值不是 true 都算没有
has_entitlement() {
  local xml
  xml="$(codesign -d --entitlements - --xml "$1" 2>/dev/null || true)"
  [ -n "$xml" ] || return 1
  # 键里的点要转义，plutil 才不会当成路径分隔
  [ "$(printf '%s' "$xml" | plutil -extract "${KEY//./\\.}" raw -o - - 2>/dev/null || true)" = "true" ]
}

has_runtime() {
  codesign -dv "$1" 2>&1 | grep -E '^CodeDirectory .*flags=.*\(.*runtime.*\)' >/dev/null
}

has_entitlement "$helper" || fail "辅助程序没有 $KEY（试打会因为库验证加载不了 librime）"
if has_entitlement "$main"; then
  fail "主程序不该有 $KEY（只有辅助程序要）"
fi
if [ "$release" = "1" ]; then
  has_runtime "$helper" || fail "辅助程序没有打开 hardened runtime"
  has_runtime "$main" || fail "主程序没有打开 hardened runtime"
fi
echo "ok：$app"

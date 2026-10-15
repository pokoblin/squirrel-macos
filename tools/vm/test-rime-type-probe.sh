#!/bin/bash
# 测试 rime-type-probe 的防误用检查：真实 ~/Library/Rime（换各种写法）都要拒绝（退出码 3）。
# 只用 --guard-only 模式：只做检查，不加载 librime，所以即使检查有漏洞也不会碰真实目录。
set -u
cd "$(dirname "$0")"
P=./rime-type-probe
REAL_HOME=$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')
FAKE=$(mktemp -d)
mkdir -p "$FAKE/copy/build" "$FAKE/home/Library/Rime/build"
pass=0; fail=0

expect() {  # expect <期望退出码> <说明> <命令...>
  local want=$1 name=$2; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $name（期望 $want，实际 $got）"; fi
}

if [ -d "$REAL_HOME/Library/Rime" ]; then
  expect 3 "真实目录"            $P --guard-only "$REAL_HOME/Library/Rime"
  expect 3 "真实目录加斜杠"      $P --guard-only "$REAL_HOME/Library/Rime/"
  expect 3 "firmlink 路径"       $P --guard-only "/System/Volumes/Data$REAL_HOME/Library/Rime"
  expect 3 "HOME 没设置"         env -u HOME $P --guard-only "$REAL_HOME/Library/Rime"
  expect 3 "HOME 指向别处"       env HOME="$FAKE" $P --guard-only "$REAL_HOME/Library/Rime"
  expect 3 "相对路径"            bash -c "cd '$REAL_HOME/Library' && '$PWD/rime-type-probe' --guard-only Rime"
  [ -d "$REAL_HOME/Library/Rime/build" ] && expect 3 "真实目录的子目录" $P --guard-only "$REAL_HOME/Library/Rime/build"
fi
expect 3 "HOME 下的 Rime 子目录"  env HOME="$FAKE/home" $P --guard-only "$FAKE/home/Library/Rime/build"
expect 3 "不存在的路径"           $P --guard-only "$FAKE/nope"
expect 0 "普通副本"               $P --guard-only "$FAKE/copy"
expect 0 "副本里的 build 子目录"  $P --guard-only "$FAKE/copy/build"

rm -rf "$FAKE"
echo "通过 $pass，失败 $fail"
[ "$fail" = 0 ]

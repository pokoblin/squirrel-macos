#!/bin/bash
# 有些应用（备忘录、Safari 这类沙盒应用）里鼠须管突然只出英文、光标旁一直显示 A 时运行：./tools/fix-english-only.sh
# 按顺序试：重启鼠须管 → 重新登记鼠须管 → 提示重启电脑。每一步做完由你去出问题的应用里试，好了就停。
# 原因还没查清（见 README「常见问题」），最后会告诉你是第几步好的，方便报告问题。
set -euo pipefail

app="/Library/Input Methods/Squirrel.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
user="$(id -un)"

[ -d "$app" ] || { echo "没找到 $app，鼠须管好像没装。" >&2; exit 1; }

running() { pgrep -x -U "$(id -u)" Squirrel >/dev/null; }

# 最多等 5 秒，等到条件成立返回 0
wait_until() {
  for _ in $(seq 1 50); do
    "$@" && return 0
    sleep 0.1
  done
  return 1
}
stopped() { ! running; }

# 先普通退出，卡住了再强制退出，然后启动
restart_squirrel() {
  if running; then
    killall -u "$user" Squirrel 2>/dev/null || true
    if ! wait_until stopped; then
      killall -KILL -u "$user" Squirrel 2>/dev/null || true
      wait_until stopped || { echo "鼠须管退不掉。" >&2; return 1; }
    fi
  fi
  open "$app"
  wait_until running || { echo "鼠须管没有启动起来。" >&2; return 1; }
}

# 好了返回 0
ask_fixed() {
  local answer
  echo "等一两分钟，回到出问题的应用里打几个字试试（不用重开应用）。"
  while true; do
    read -r -p "能打中文了吗？[y/n] " answer
    case "$answer" in
      y|Y) return 0 ;;
      n|N) return 1 ;;
    esac
  done
}

done_at() {
  echo
  echo "好了：第 $1 步（$2）起作用，时间 $(date '+%Y-%m-%d %H:%M')。"
  echo "如果方便，请到 https://github.com/pokoblin/squirrel-macos/issues 报告是第几步好的，帮忙找原因。"
  exit 0
}

echo "第 1 步：重启鼠须管"
restart_squirrel
echo "鼠须管已重新启动。"
ask_fixed && done_at 1 "重启鼠须管"

echo
echo "第 2 步：重新登记鼠须管"
"$lsregister" -f "$app"
echo "已重新登记。"
ask_fixed && done_at 2 "重新登记鼠须管"

echo
echo "第 3 步：前两步都没用，请重启电脑。重启一定能恢复。"
exit 1

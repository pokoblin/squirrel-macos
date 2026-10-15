#!/bin/bash
# 测试虚拟机小工具：从干净底板 macos-base 克隆测试机、SSH 连进去、用完删掉
# 用法：
#   ./tools/vm/vm.sh new <名字> [--headless]   克隆一台新测试机并启动（默认带窗口）
#   ./tools/vm/vm.sh ssh <名字> [命令...]      连进测试机；带命令就只执行这条命令
#   ./tools/vm/vm.sh rm <名字>                 关机并删除测试机
#   ./tools/vm/vm.sh list                      列出所有虚拟机
set -euo pipefail

BASE="macos-base"
VM_USER="tester"
KEY="$HOME/.ssh/tart_vm_ed25519"
PROJECT="$(cd "$(dirname "$0")/../.." && pwd)"
SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=5 -o LogLevel=ERROR
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

cmd="${1:-}"; name="${2:-}"

case "$cmd" in
  new)
    [ -n "$name" ] || usage
    [ "$name" != "$BASE" ] || { echo "不能用底板的名字"; exit 1; }
    tart clone "$BASE" "$name"
    run_args=(--dir="vm:$PROJECT/tools/vm:ro" --dir="project:$PROJECT:ro")
    [ "${3:-}" = "--headless" ] && run_args+=(--no-graphics)
    nohup tart run "$name" "${run_args[@]}" >"${TMPDIR:-/tmp}/tart-$name.log" 2>&1 &
    disown
    echo "正在启动 $name ……"
    ip="$(tart ip "$name" --wait 120)"
    for _ in $(seq 1 60); do
      ssh "${SSH_OPTS[@]}" "$VM_USER@$ip" true 2>/dev/null && break
      sleep 2
    done
    ssh "${SSH_OPTS[@]}" "$VM_USER@$ip" true
    echo "$name 已就绪：$ip"
    echo "项目文件夹在虚拟机里的位置（只读）：/Volumes/My Shared Files/project"
    ;;
  ssh)
    [ -n "$name" ] || usage
    shift 2
    exec ssh "${SSH_OPTS[@]}" "$VM_USER@$(tart ip "$name")" "$@"
    ;;
  rm)
    [ -n "$name" ] || usage
    [ "$name" != "$BASE" ] || { echo "不会删除底板 $BASE"; exit 1; }
    tart stop "$name" 2>/dev/null || true
    tart delete "$name"
    echo "已删除 $name"
    ;;
  list)
    tart list
    ;;
  *)
    usage
    ;;
esac

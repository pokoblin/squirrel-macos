#!/bin/bash
# 编译测试小工具，输出到 tools/vm/ 下（测试机里通过共享文件夹 /Volumes/My Shared Files/vm/ 访问）
set -euo pipefail
cd "$(dirname "$0")"

clang -O2 -Wall -o rime-type-probe rime-type-probe.c
echo "已编译 tools/vm/rime-type-probe"

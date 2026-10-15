#!/bin/bash
# 第一次发布在线方案清单前运行一次（在线方案清单设计 5.2）：
# 生成签名密钥，私钥存进登录钥匙串，打印公钥。私钥不落盘、不打印。
set -euo pipefail
cd "$(dirname "$0")/../.."
SERVICE="squirrel-macos-catalog-signing"
if security find-generic-password -s "$SERVICE" >/dev/null 2>&1; then
  echo "钥匙串里已经有 $SERVICE，不重新生成（要换密钥，先在「钥匙串访问」里删掉它，并且要发新版应用换公钥）" >&2
  exit 1
fi
swift build --product rimectl >/dev/null
OUTPUT="$(.build/debug/rimectl catalog keygen)"
PRIVATE="$(echo "$OUTPUT" | awk '$1=="private"{print $2}')"
PUBLIC="$(echo "$OUTPUT" | awk '$1=="public"{print $2}')"
# 私钥作为参数传给 security，运行的一瞬间会出现在本机进程列表里；单用户的开发机可以接受
security add-generic-password -s "$SERVICE" -a catalog -w "$PRIVATE"
echo "私钥已存进登录钥匙串（服务名 $SERVICE）。请另外备份一份，例如存进密码管理器："
echo "  security find-generic-password -s $SERVICE -w"
echo "公钥（写进 Sources/RimeKit/Catalog/CatalogSignature.swift 的 publicKeys）："
echo "$PUBLIC"

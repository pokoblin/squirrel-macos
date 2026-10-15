#!/bin/bash
# 在虚拟机「里面」运行一次：让宿主机能用 SSH 免密登录进来做测试
# 用法（在虚拟机的「终端」里）：bash "/Volumes/My Shared Files/vm/setup-guest.sh"
# 会要求输入一次虚拟机账户的密码（sudo 用）
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PUBKEY="$HERE/tart_vm_ed25519.pub"

if [ ! -f "$PUBKEY" ]; then
  echo "找不到公钥 $PUBKEY ，请确认虚拟机是用 --dir 共享了 vm 目录启动的。"
  exit 1
fi

# 1. 宿主机的公钥加进 authorized_keys，SSH 登录不用密码
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
grep -qxF "$(cat "$PUBKEY")" ~/.ssh/authorized_keys || cat "$PUBKEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
echo "✓ 已添加宿主机公钥"

# 2. 这个账户用 sudo 不再问密码（只在测试虚拟机里这么做）
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee "/etc/sudoers.d/$USER" >/dev/null
sudo chmod 440 "/etc/sudoers.d/$USER"
echo "✓ sudo 免密码"

# 3. 不休眠、不锁屏，免得测试做到一半虚拟机睡着
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
defaults -currentHost write com.apple.screensaver idleTime 0
echo "✓ 已关闭休眠和屏保"

# 4. 打开「远程登录」（SSH）
sudo launchctl enable system/com.openssh.sshd
sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
sleep 1
if nc -z localhost 22 2>/dev/null; then
  echo "✓ 远程登录（SSH）已打开"
else
  echo "✗ 远程登录没打开成功：请到「系统设置 → 通用 → 共享」里手动打开「远程登录」"
  exit 1
fi

echo
echo "全部完成。虚拟机账户名：$USER"

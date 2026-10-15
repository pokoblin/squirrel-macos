#!/bin/bash
# 打包应用，放进测试机的 ~/Applications 并打开。用法：./tools/vm/install-app.sh <测试机名字>
# 测试机的共享文件夹只读，而且宿主机原地重编后直接运行可能被杀，所以先复制到测试机本地。
set -euo pipefail
cd "$(dirname "$0")/../.."
vm="${1:?用法：$0 <测试机名字>}"
app="$(./tools/app/build-app.sh)"
./tools/vm/vm.sh ssh "$vm" "pkill -x SquirrelMacOSApp || true; mkdir -p ~/Applications && rm -rf ~/Applications/SquirrelHelper.app ~/Applications/squirrel-macos.app ~/Applications/鼠须管助手.app && cp -R '/Volumes/My Shared Files/project/$app' ~/Applications/ && xattr -cr ~/Applications/SquirrelHelper.app && sudo launchctl asuser \$(id -u) sudo -u tester open ~/Applications/SquirrelHelper.app"
echo "已在 $vm 里打开 ~/Applications/SquirrelHelper.app"

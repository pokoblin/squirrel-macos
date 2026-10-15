# 测试虚拟机

安装鼠须管、启用输入法、改 `~/Library/Rime` 这些会改动系统的测试，都放在虚拟 Mac 里做，不碰自己的电脑。

用的是 [Tart](https://tart.run/)。做法是先有一台**干净的底板** `macos-base`，每次测试从它**克隆**一台出来，测完删掉。

## 现状（2026-10-15）

- Tart 2.41.0：装在 `~/Applications/tart.app`，命令是 `/opt/homebrew/bin/tart`（一个包装脚本）。
  - Homebrew 上的官方配方 `cirruslabs/cli/tart` 和新版 Homebrew 不兼容，所以是从 GitHub Release 下载的，校验了哈希和苹果公证。
- 底板 `macos-base`：macOS 27.0.1，6 核、8 GB 内存、60 GB 磁盘（实际占用约 32 GB），账户 `tester`。已经运行过 `setup-guest.sh`：SSH 免密登录、sudo 免密码、不休眠。**和 squirrel-wubi86 项目共用。**
- SSH 密钥：`~/.ssh/tart_vm_ed25519`（只给虚拟机用）。
- 系统安装镜像缓存在 `~/.tart/cache/IPSWs`（约 25 GB），只有重建底板时才用得到。

## 平时用法

```bash
./tools/vm/vm.sh new test-1
```

从底板克隆一台叫 `test-1` 的测试机并启动（带窗口；加 `--headless` 就不开窗口）。大约 10 秒就能连。

```bash
./tools/vm/vm.sh ssh test-1
```

连进去；也可以直接带一条命令，例如 `./tools/vm/vm.sh ssh test-1 sw_vers`。

```bash
./tools/vm/vm.sh rm test-1
```

测完删掉。底板不会被删。

- 测试机里能看到本项目（只读）：`/Volumes/My Shared Files/project`。
- 克隆出来的测试机启动后停在登录界面。SSH 能用，但**输入法相关的测试必须先在窗口里登录桌面**（要用户本人输入 `tester` 的密码）。
- 查输入法状态要在桌面会话里运行：`sudo launchctl asuser $(id -u) sudo -u tester <命令>`。

## 查看输入法状态：`tis-probe`

```bash
swiftc -O tools/vm/tis-probe.swift -o tools/vm/tis-probe
```

```bash
scp -i ~/.ssh/tart_vm_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null tools/vm/tis-probe tester@$(tart ip test-1):/tmp/
```

```bash
./tools/vm/vm.sh ssh test-1 'sudo launchctl asuser $(id -u) sudo -u tester /tmp/tis-probe list squirrel'
```

- `list 关键字`：列出已安装的输入法，以及是否启用、是否选中。
- `current`：当前选中的输入法。
- `enable ID` / `select ID`：启用或切换。ID 前加 `=` 表示精确匹配，要加引号，例如 `"=im.rime.inputmethod.Squirrel.Hans"`（zsh 会把不加引号、以 `=` 开头的参数当成特殊语法）。

## 重建底板（一般用不到）

1. 删除旧底板：`tart delete macos-base`
2. 新建：`tart create macos-base --from-ipsw latest --disk-size 60 --disk-format asif`，然后 `tart set macos-base --cpu 6 --memory 8192 --display 1440x900`
3. 启动：`tart run macos-base --dir=vm:$PWD/tools/vm:ro`，在窗口里走完开机设置。Apple 账户跳过；账户名 `tester`；FileVault 不开。
4. 在虚拟机终端里运行：`bash "/Volumes/My Shared Files/vm/setup-guest.sh"`（需要 `tools/vm/tart_vm_ed25519.pub`，这个文件不进 git，从 `~/.ssh/tart_vm_ed25519.pub` 复制过来）。
5. 关机定型：`ssh -i ~/.ssh/tart_vm_ed25519 tester@$(tart ip macos-base) 'sudo shutdown -h now'`

## 注意

- 创建镜像（`tart create`）时 Dock 上 Tart 的图标会一直跳，这是正常的，别点退出。
- 苹果规定一台 Mac 最多同时运行 2 台 macOS 虚拟机。
- 宿主机的剪贴板目前粘贴不进虚拟机。
- 用 computer-use 点 Tart 窗口里的内容，坐标会偏。需要点界面时，最好请用户自己点。

# squirrel-macos 项目约定

鼠须管（Squirrel / Rime）的 macOS 图形前端。阶段 0–8 已完成（待验证项；方案清单和下载缓存；设置和生成配置；写入真实配置、部署、备份还原；安装鼠须管、启用、环境检查；接管已有配置；一键导出导入；文本替换同步；应用骨架和第一次打开的引导；主窗口），已发布 0.1.0、0.1.1（预发布），应用名「鼠须管助手」（英文 SquirrelHelper）；0.2.0（改用 dmg、正式版）的改动已提交，还没打包发布。路线图：`docs/superpowers/plans/2026-10-15-roadmap.md`。

第二版按子项目做，路线图：`docs/superpowers/plans/2026-10-15-v2-roadmap.md`。子项目 1「在线方案清单」已完成（2026-10-16）：清单签名发布在 `catalog/v1/`，第一份编号 2026101501。子项目 2「试打预览」已完成（2026-10-16）。

## 先读这些

- `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`：第一版设计（SwiftUI；RimeKit 核心库 + 应用 + `rimectl`；不做 Profile，只做一键导入导出）。
- `docs/superpowers/specs/2026-10-15-online-catalog-design.md`：在线方案清单设计（签名、防回滚、只在用户点按钮时联网）。
- `docs/superpowers/specs/2026-10-16-typing-preview-design.md`：试打预览设计（辅助进程加载鼠须管的 librime、在临时副本上打字，不碰真实目录）。
- `docs/verified-facts.md`：已验证的事实。改设计、写代码前先看，**别凭印象重新推断**。
- `docs/install-test-log.md`：首次安装的实测结论（不用注销；必须在系统设置手动添加输入法；新 Mac 没有 python3/git）。
- `docs/upstream-layouts.md`：极点五笔、雾凇各个 zip 解压后的目录结构（写方案清单时用）。
- `docs/phase0-log.md`：阶段 0 的验证过程记录。
- `docs/requirements-draft.md`：需求和用户已确认的决定（看「已确认的决定」「第一版范围（已确认）」两节）。
- `docs/design-draft.md`：已被第一版设计取代，只作历史参考。

## 工作方式

- 用简单直白的中文写文档和说明；代码、命令、标识符保持原样。
- 提交、推送前先问用户，用户同意了再做。
- 发布方案清单：改 `Sources/RimeKit/Resources/catalog.json`（`serial` 改大，已发布的 id 不能删），`./tools/catalog/publish.sh` 签名，步骤见 `docs/release.md`「发布方案清单」。签名私钥在宿主机登录钥匙串（`squirrel-macos-catalog-signing`），钥匙串问时点「允许」不点「始终允许」；推送前先问用户。
- 发布：`./tools/release/build-release.sh`，发布包一律用 dmg（0.2.0 起，用户定的），步骤见 `docs/release.md`。打 tag、建 GitHub Release、改仓库简介前先问用户。
- 应用（SquirrelMacOSApp）不在宿主机上运行，只编译和跑单元测试；用 `./tools/vm/install-app.sh <测试机>` 放进测试机打开。测试机里 SSH 会话进不了 `~/Downloads` 等隐私保护目录，要给应用的文件放在 `/Users/Shared`。
- **不要碰宿主机的真实配置**：`~/Library/Rime`、`/Library/Input Methods`、输入法启用状态都不要改。需要验证时：
  - 配置和打字效果：复制一份 `~/Library/Rime` 到临时目录，用 librime 模拟（方法见 `docs/verified-facts.md`「用 librime 模拟打字」）。
  - 安装、启用输入法这类系统级操作：在测试虚拟机里做（`tools/vm/`）。
- 隐私：用户的 macOS「文本替换」内容（`~/Library/KeyboardServices/TextReplacements.db`、生成的 `custom_phrase.txt`）是个人信息，检查时只统计条数、比对哈希，不打印内容，不进 git。
- 改 Rime 配置项前，先用 `strings` 查 Squirrel 二进制确认键名真的存在（踩过 `candidate_font_point` 无效的坑）。
- Swift 工程：`swift test` 跑全部单元测试（只用临时目录）；`RIMEKIT_ONLINE=1 swift test --filter OnlineTests` 联网检查上游；手动试 `rimectl fetch` 一律加 `--data-dir`，别写进真实的 `~/Library/Application Support/squirrel-macos`。测试机里可以直接运行 `/Volumes/My Shared Files/project/.build/debug/rimectl`。联网的端到端测试（真实上游包生成、编译、打字）：`RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests`；生成配置的测试要先运行 `./tools/vm/build-probes.sh` 编译打字检查工具。

## 测试虚拟机

- Tart 2.41.0 装在 `~/Applications/tart.app`，命令是 `/opt/homebrew/bin/tart`（Homebrew 上的 cirruslabs 配方已坏，不要用 brew 装）。
- 干净底板 `macos-base`（macOS 27.0.1，账户 `tester`，SSH 免密、sudo 免密），和 squirrel-wubi86 项目共用。**不要直接启动或修改底板**，测试一律克隆：`./tools/vm/vm.sh new <名字>`。
- **长期测试机 `squirrel-dev`**：已装鼠须管 1.1.2、已添加并选中输入法、`~/Library/Rime` 里有雾凇全拼和小鹤双拼，日常开发用（登录过一次桌面）。测从零安装、导入时再克隆干净的，测完删。
- 测试「试打」页要用发布签名的包（`ALLOW_DIRTY=1 SKIP_NOTARIZE=1 ./tools/release/build-release.sh`）：debug 包没有 hardened runtime，复现不了库验证的问题。
- 测试小工具：`./tools/vm/build-probes.sh` 编译出 `rime-type-probe`（在配置副本上模拟打字）和 `TRProbe.app`（检查能否读文本替换），测试机里在 `/Volumes/My Shared Files/vm/`。测试机的远程 shell 是 zsh，通配符没匹配到会报错。
- 测试机要在窗口里登录桌面后，输入法相关的检查才有意义；登录需要用户本人输入密码。
- 在测试机里查输入法状态要用桌面会话运行：`sudo launchctl asuser $(id -u) sudo -u tester <命令>`。
- 在测试机里跑 `rimectl apply/restore` 要用桌面会话（`open` 和 `--reload` 需要）：`sudo launchctl asuser $(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' … --data-dir /tmp/rk`。测试机的 `/tmp/rk` 是阶段 3 实测用的应用数据目录。
- `rimectl takeover` 也要用桌面会话（`--confirm` 会通知鼠须管）。测试机里试接管时用新的数据目录（如 `/tmp/rk5`），别动 `/tmp/rk`。
- `rimectl export/import` 也要用桌面会话（要退出、启动鼠须管来导出、合并输入习惯）。测试机里的共享文件夹是只读的：导出要先写到测试机自己的目录（如 `/tmp`），再用 `vm.sh ssh … cat` 拷出来。
- 宿主机重新编译后，测试机里直接运行共享文件夹里的 rimectl 可能被系统杀掉（退出码 137）。先把 `.build/debug/rimectl` 和旁边的 `SquirrelMacOS_RimeKit.bundle` 一起复制到测试机的 `/tmp/rimectl-bin/` 再运行。
- 宿主机删掉再重建一个目录后（比如 `.build/release-out/`），测试机的共享文件夹有时一时看不到新文件：改用 `./tools/vm/vm.sh ssh 测试机 "cat > /Users/Shared/文件名" < 本地文件` 传过去。

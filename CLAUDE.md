# squirrel-macos 项目约定

鼠须管（Squirrel / Rime）的 macOS 图形前端。目前处于**第一版设计审阅**阶段，还没有代码。

## 先读这些

- `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`：第一版设计（SwiftUI；RimeKit 核心库 + 应用 + `rimectl`；不做 Profile，只做一键导入导出）。
- `docs/verified-facts.md`：已验证的事实。改设计、写代码前先看，**别凭印象重新推断**。
- `docs/install-test-log.md`：首次安装的实测结论（不用注销；必须在系统设置手动添加输入法；新 Mac 没有 python3/git）。
- `docs/requirements-draft.md`：需求和用户已确认的决定（看「已确认的决定」「第一版范围（已确认）」两节）。
- `docs/design-draft.md`：已被第一版设计取代，只作历史参考。

## 工作方式

- 用简单直白的中文写文档和说明；代码、命令、标识符保持原样。
- 提交、推送前先问用户，用户同意了再做。
- **不要碰宿主机的真实配置**：`~/Library/Rime`、`/Library/Input Methods`、输入法启用状态都不要改。需要验证时：
  - 配置和打字效果：复制一份 `~/Library/Rime` 到临时目录，用 librime 模拟（方法见 `docs/verified-facts.md`「用 librime 模拟打字」）。
  - 安装、启用输入法这类系统级操作：在测试虚拟机里做（`tools/vm/`）。
- 隐私：用户的 macOS「文本替换」内容（`~/Library/KeyboardServices/TextReplacements.db`、生成的 `custom_phrase.txt`）是个人信息，检查时只统计条数、比对哈希，不打印内容，不进 git。
- 改 Rime 配置项前，先用 `strings` 查 Squirrel 二进制确认键名真的存在（踩过 `candidate_font_point` 无效的坑）。

## 测试虚拟机

- Tart 2.41.0 装在 `~/Applications/tart.app`，命令是 `/opt/homebrew/bin/tart`（Homebrew 上的 cirruslabs 配方已坏，不要用 brew 装）。
- 干净底板 `macos-base`（macOS 27.0.1，账户 `tester`，SSH 免密、sudo 免密），和 squirrel-wubi86 项目共用。**不要直接启动或修改底板**，测试一律克隆：`./tools/vm/vm.sh new <名字>`。
- 测试机要在窗口里登录桌面后，输入法相关的检查才有意义；登录需要用户本人输入密码。
- 在测试机里查输入法状态要用桌面会话运行：`sudo launchctl asuser $(id -u) sudo -u tester <命令>`。

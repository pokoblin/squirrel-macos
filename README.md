# 鼠须管助手（SquirrelHelper）

鼠须管（Squirrel，macOS 上的 Rime 输入法）的图形界面助手：点几下就能装好鼠须管、选方案（拼音、五笔、双拼）、调外观、同步 macOS 文本替换，并把整套配置一键导出、在新电脑上一键导入。

> **非官方**：这是个人项目，不是鼠须管 / Rime 官方出品。

应用名跟着系统语言：中文系统里显示「鼠须管助手」，其他语言显示 SquirrelHelper。

## 下载和安装

- 要求：macOS 27 或更新，Apple 芯片的 Mac。
- 到 [Releases](https://github.com/pokoblin/squirrel-macos/releases) 下载 `SquirrelHelper-版本号.zip`，解压后把应用拖进「应用程序」文件夹，然后打开。
- 应用已经用 Developer ID 签名，并通过了苹果公证。第一次打开时系统会问「是从互联网下载的，确定要打开吗」，点「打开」。

第一次打开会一步步带你：
1. 安装鼠须管（会弹出系统授权框，输入这台 Mac 的登录密码）；
2. 在系统设置里添加输入法；
3. 选一个起步方案，或者接管已有的配置，或者从导出文件导入。

## 能做什么

- 方案：启用、排序（第一个是默认方案）、方案的选项。
- 外观：字号、候选个数、横排竖排、配色。
- 文本替换：把「系统设置 → 键盘 → 文本替换」变成鼠须管的短语。打开应用时会检查有没有变化。
- 导入导出：设置、个人词库、手动短语、输入习惯打成一个 zip，文件名带导出时间。
- 备份：每次应用改动前自动备份，可以还原。
- 诊断：检查鼠须管有没有装好、启用、部署成功。

改设置后要点「应用改动」才生效。

## 隐私

- 文本替换、个人词库只在你的电脑上处理，不上传。读文本替换不需要另外授权。
- 导出文件里不放文本替换生成的短语（同一个 Apple 账户在新电脑上会自动同步）。
- 应用只在安装鼠须管、下载方案时联网（从鼠须管和各方案的 GitHub 下载）。

## 许可证

- 鼠须管助手：[MIT](LICENSE)。用到的开源库见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。
- 应用不包含任何输入方案。雾凇拼音、极点五笔等方案是使用时从上游下载的，许可证见各项目。

---

以下是给开发者看的。

- 第一版设计：[docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md)
- 实现路线图：[docs/superpowers/plans/2026-10-15-roadmap.md](docs/superpowers/plans/2026-10-15-roadmap.md)
- 发布新版本：[docs/release.md](docs/release.md)

## 文档

| 文件 | 内容 |
|---|---|
| [docs/verified-facts.md](docs/verified-facts.md) | **已验证的事实**：鼠须管安装包、命令行参数、输入法启用、部署、日志、文本替换、上游方案的来源和许可证等，每条都写了怎么验证的 |
| [docs/install-test-log.md](docs/install-test-log.md) | 在全新虚拟 Mac 里“从零安装”的完整实测记录：**不用注销，但必须在系统设置里手动添加一次输入法** |
| [docs/requirements-draft.md](docs/requirements-draft.md) | 需求，以及和用户逐条确认过的决定（不做 Profile，只做一键导入导出） |
| [docs/design-draft.md](docs/design-draft.md) | 初步设计草案，已被第一版设计取代，只作历史参考 |
| [docs/reference-wubi-profile.md](docs/reference-wubi-profile.md) | 样板配置：我自己在用的“五笔 + 拼音混输 + 雾凇词库”配置，逐项说明它改了什么 |

## 测试环境

所有会改动系统的测试（安装鼠须管、启用输入法、改 `~/Library/Rime`）都在**虚拟 Mac** 里做，不碰自己的电脑。工具在 [tools/vm/](tools/vm/)，用法见 [tools/vm/README.md](tools/vm/README.md)。

## 开发

Swift Package（需要 Xcode 27）：`RimeKit` 是全部逻辑，`rimectl` 是命令行入口。

- 跑测试（只用临时目录，不碰真实配置）：`swift test`
- 联网检查上游结构有没有变：`RIMEKIT_ONLINE=1 swift test --filter OnlineTests`
- 试用命令行：`swift build && .build/debug/rimectl catalog`；下载时请加 `--data-dir 某个临时目录`
- 试生成配置：`rimectl settings init wubi-pinyin --data-dir D`，再 `rimectl generate --data-dir D --out D/rime`（生成的测试要先运行 `./tools/vm/build-probes.sh`）
- 宿主机上试 `rimectl apply` 只用 `--rime-dir` 指向临时目录；写真实配置只在测试机里做
- 接管已有配置：`rimectl takeover --rime-dir 临时目录 --data-dir D` 只预览、不改文件；加 `--confirm` 才真的接管（会通知鼠须管，只在测试机里做）
- 导出导入：`rimectl export 文件`、`rimectl import 文件`（会暂时退出鼠须管合并输入习惯，只在测试机里做）
- 文本替换：`rimectl textreplacement status` 看状态，`sync` 打开同步并应用，`off` 关掉（只在测试机里同步）
- 应用：`./tools/app/build-app.sh` 打包成 `.build/app/SquirrelHelper.app`；第一次打开走引导，之后是主窗口（方案、外观、文本替换、导入导出、备份、诊断）。只在测试机里打开（`./tools/vm/install-app.sh 测试机名字`，装在测试机的 `~/Applications`）
- 安装、启用鼠须管只在测试机里试：`rimectl install --gui-auth`、`rimectl activate`、`rimectl doctor`

# squirrel-macos

给鼠须管（Squirrel，macOS 上的 Rime 输入法）做的图形界面前端。

目标：让不会用终端的人，也能在界面上点几下完成鼠须管的安装、选方案（拼音、五笔、双拼……）、调外观、管词库，并且能把整套配置一键导出、在新电脑上一键还原。

## 现在在哪个阶段

**第一版设计已确认，正在做阶段 0（待验证项）。** 还没有应用代码。

这些调研来自上一个项目 [squirrel-wubi86](../squirrel-wubi86)。那个项目只为我自己的“极点五笔 + 拼音混输”做配置，所有步骤都是手动在终端里完成的。这里的结论都在虚拟机或真机上实际验证过。

- 第一版设计：[docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md)
- 实现路线图：[docs/superpowers/plans/2026-10-15-roadmap.md](docs/superpowers/plans/2026-10-15-roadmap.md)

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

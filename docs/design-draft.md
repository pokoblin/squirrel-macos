# 初步设计草案

状态：**已被 [第一版设计](superpowers/specs/2026-10-15-squirrel-macos-v1-design.md) 取代**，只作历史参考（其中的 Profile 设计已作废）。原状态：草案。依据是 [verified-facts.md](verified-facts.md) 和 [install-test-log.md](install-test-log.md) 里的实测结果。需求还没确认（见 [requirements-draft.md](requirements-draft.md) 的待确认问题），这里只是方向，不是定稿。

## 1. 哪些必须用户手动，哪些自动，哪些做进应用

### ① 必须用户亲手做（系统限制）

| 事项 | 原因 | 应用能做到什么 |
|---|---|---|
| 安装鼠须管时**输入管理员密码** | 要写入 `/Library/Input Methods` | 弹出系统授权框，用户只输一次密码，不用终端 |
| **在系统设置里添加鼠须管** | 实测：程序只能启用到「简体」子模式，本体启用不了；注销也没用 | 一键打开系统设置的键盘页，配上图文说明，并**轮询检测**本体是否已启用，好了自动切换过去 |
| （可能）授权读取“文本替换”数据库 | 独立 .app 可能受隐私权限限制（**待验证**） | 被拦住时，引导用户去「隐私与安全性」里授权 |

不需要：注销、重启、终端、Homebrew、python3、git。

### ② 点一下自动下载

| 组件 | 来源 | 说明 |
|---|---|---|
| 鼠须管 | `rime/squirrel` 的 Release 里的 pkg | 安装前校验签名（团队 ID `28HU5A7B46`）和公证 |
| 各种方案 | GitHub 仓库 zip（`codeload.github.com`）或 Release 里的打包文件 | 雾凇有现成的 `cn_dicts.zip`、`full.zip` |
| 词库更新 | 同上 | 记录版本（提交号或发布时间），有新版本时提示 |

GPL 的方案（雾凇、官方双拼）建议都运行时下载，不打包进应用。

### ③ 直接做进应用

- 生成所有配置文件（`default.custom.yaml`、`squirrel.custom.yaml`、各方案的 `.custom.yaml`、总词库文件、个人词库、`custom_phrase.txt`）。
- 编译校验：调用 `rime_deployer --build`，先在副本上编译。
- 部署：鼠须管在运行就用 `Squirrel --reload`，没运行就 `open` 启动它（实测：没运行时 `--reload` 不起作用）。
- 读日志、判断部署结果。
- 备份和还原。
- 读 macOS 文本替换（SQLite，Swift 自带库）。
- 试打预览（加载鼠须管里的 `librime.1.dylib`）。
- 检测和切换输入法（Carbon TIS 接口）。

## 2. 核心思路：应用拥有“生成出来的配置”

上一个项目的教训：极点五笔仓库里**自带了** `default.custom.yaml` 和 `squirrel.custom.yaml`，用户改了字号，一更新方案就被覆盖掉。

所以：

```
上游方案文件（只读，按版本缓存）
        +
Profile（用户的选择和个人内容）
        ↓  配置生成器
暂存目录（完整的 Rime 用户目录）
        ↓  rime_deployer --build 校验
备份当前 ~/Library/Rime  →  应用到 ~/Library/Rime  →  通知鼠须管部署
        ↓
检查日志 / build 文件；失败就一键还原
```

- 上游文件只当“底稿”，永远不直接改。
- 上游自带的 `*.custom.yaml`（比如极点五笔的那两个）当成**默认值**读进来，再叠加用户的设置，最后由应用生成同名文件。
- `~/Library/Rime` 里应用不认识的文件：先不动，并提示用户（具体策略待确认）。

## 3. Profile（初步）

### 内容

| 部分 | 例子 |
|---|---|
| 基本信息 | 名字、说明、创建时间、应用版本 |
| 方案 | 启用哪些方案、顺序、默认方案；每个方案来自哪个包、哪个版本 |
| 词库搭配 | 方案用哪个词库，例如“五笔混输的拼音反查 → 雾凇 8105 + base + ext + 个人拼音词” |
| 外观 | 配色（浅色、深色）、字号、横排竖排、候选数 |
| 按键 | 翻页键、切换方案快捷键、Shift 行为 |
| 个人内容 | 个人词库（五笔、拼音）、自定义短语、是否同步 macOS 文本替换 |

### 导出文件（初步想法）

一个 zip 包，比如 `我的五笔.squirrelprofile`：

```
manifest.json          # 上表的设置 + 用到的方案包清单（仓库、版本、校验值）
personal/              # 可选：个人词库、自定义短语（导出时用户选择要不要带）
```

- 默认**不打包方案本身**，只记录“需要哪些包、哪个版本”，导入时联网下载。好处：文件小、许可证干净。是否需要“离线完整包”待确认。
- 由 macOS 文本替换生成的短语**默认不导出**（个人隐私，而且同一个 Apple 账户在新电脑上会自动同步）。

### 本机存放位置（初步）

```
~/Library/Application Support/squirrel-macos/
├── packages/   # 下载的上游方案，按“包名@版本”缓存，多个 Profile 共用
├── profiles/   # 每个 Profile 一个文件夹
├── staging/    # 生成和校验用的暂存目录
└── backups/    # 每次应用前对 ~/Library/Rime 的备份
```

## 4. 模块划分（初步）

| 模块 | 职责 | 依赖 |
|---|---|---|
| SquirrelInstaller | 检测版本；下载 pkg；校验签名；带授权安装 | 网络、系统授权 |
| InputSourceService | 用 TIS 检测、切换输入法；打开系统设置；轮询“添加好了没” | Carbon |
| PackageCatalog | 方案目录：有哪些方案、来源、许可证、依赖 | 内置清单（或在线清单，待定） |
| PackageStore | 下载 zip、解压、按版本缓存、校验 | 网络 |
| ProfileStore | Profile 的增删改、导入导出 | 文件系统 |
| ConfigGenerator | Profile + 上游文件 → 完整的 Rime 用户目录 | PackageStore |
| Deployer | `rime_deployer` 校验；备份；应用；`--reload` 或启动鼠须管；读日志 | 鼠须管程序 |
| PreviewEngine | 加载 librime，在暂存目录上模拟打字 | `librime.1.dylib` |
| TextReplacementImporter | 读系统文本替换数据库，生成短语 | SQLite |

界面：安装向导、方案、词库、外观、按键、短语、Profile、诊断。

## 5. 技术路线（建议）

**推荐 SwiftUI 原生应用。**
- 要用的几乎都是 macOS 系统能力：TIS 输入法接口、授权安装、加载 librime（C 接口）、SQLite，原生写最直接。
- 体积小，不用额外打包运行时。

**不能上 App Store / 不能开沙盒**（初步判断）：要写 `~/Library/Rime`、运行安装程序、加载 `/Library/Input Methods` 里的库。所以走“Developer ID 签名 + 公证 + 官网或 GitHub 发布”。这需要苹果开发者账号（如果要给别人用）。

管理员权限安装的两种做法：
- 简单：`NSAppleScript` 执行 `do shell script "installer -pkg … -target /" with administrator privileges`，系统会弹出密码框。
- 正规：`SMAppService` 特权辅助程序，实现复杂。
- 建议第一版用简单做法。

备选：Tauri（网页技术写界面）。只在以后确定要支持 Windows（小狼毫）时才值得考虑，系统相关部分仍然要用 Swift 或 Rust 另写。

## 6. 风险和待验证

1. 系统设置键盘页的打开链接是否有效。
2. 独立 .app 读取 `TextReplacements.db` 是否被隐私权限拦住。
3. 用 `NSAppleScript` 带管理员权限运行 `installer` 时，postinstall 能不能正确拿到当前桌面用户（它用 `stat -f%Su /dev/console`）。
4. 已装旧版鼠须管、已有 `~/Library/Rime` 的电脑：怎么接管而不破坏原配置。
5. 各方案的依赖关系怎么自动识别（`schema.yaml` 里的 `dependencies`、`reverse_lookup/dictionary`、词库的 `import_tables`）。
6. 雾凇的 Lua 脚本、OpenCC 文件在鼠须管 1.1.2 上能否正常工作（鼠须管自带 Lua 插件，应该可以，但没实测雾凇完整方案）。
7. 方案切换后，输入习惯数据（`*.userdb`）怎么处理。
8. 加载鼠须管自带的 librime 做试打预览：鼠须管升级、换 librime 版本后，函数表下标会不会变（要按 `data_size` 和版本号做兼容）。

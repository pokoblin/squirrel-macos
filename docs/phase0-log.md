# 阶段 0 验证记录

日期：2026-10-15。环境：Tart 测试机 `squirrel-dev`（从 `macos-base` 克隆，macOS 27.0.1），宿主机 macOS 27.0.1。

| # | 验证项 | 结论 | 详情 |
|---|---|---|---|
| 1 | 系统设置键盘页链接 | **能** | `x-apple.systempreferences:com.apple.Keyboard-Settings.extension` 直接打开「键盘」页，「文字输入 → 输入法 → 编辑…」就在页面上。用户在这里添加鼠须管后，本体 enabled=true，切换成功。另外发现：用 TIS 切换后鼠须管进程不会马上启动，要用 `open` 启动 |
| 2 | 授权弹窗安装时 postinstall 拿到桌面用户 | **能** | `osascript … with administrator privileges` 弹出系统授权框，输密码后安装成功（约 9 秒）。postinstall 以桌面用户身份注册、启用了 `Squirrel.Hans`，状态和 `sudo installer` 完全一样（本体仍 enabled=false，选中失败）。见「过程」 |
| 3 | 独立 .app 读文本替换数据库 | | |
| 4 | `ditto` 解压 GitHub zip | **能** | 干净测试机里 `/usr/bin/ditto -x -k` 解压三个 zip 全部 `exit=0`。结构见 [upstream-layouts.md](upstream-layouts.md)：极点五笔 zip 带顶层目录 `rime-wubi86-jidian-master/`；雾凇 `full.zip` 没有顶层目录，并自带 `default.yaml`、`squirrel.yaml`、`custom_phrase.txt` |
| 5 | 鼠须管运行时 `rime_dict_manager` 导出/合并 | | |
| 6 | 雾凇全拼、小鹤双拼在鼠须管 1.1.2 上部署和打字 | **能** | 部署约 9 秒，`4 success, 0 failure`，没有 ERROR 日志。用户实际打字和 `rime-type-probe` 结果一致：`nihao` → 你好，`rq`/`sj` 出日期和时间（Lua 正常），`xiaolian` 有 😀（OpenCC 正常），小鹤 `nihc` → 你好。`rime-type-probe` 也能加载 Lua 插件 |

## 宿主机

- TRProbe（本机临时签名、未授权的独立 app，用 `open` 启动）：`path_exists=true`、`readable=true`、`open_rc=0`、`count=11`，**没有弹出权限对话框**，能直接读。
- `rime-type-probe` 在参考配置（`../squirrel-wubi86/rime` 副本）上：`g` → 一、`weixin` → 微信、`qukuailian` → 区块链、`neijuan` → 内卷，全部正确。日志显示 librime 加载了 `lua` 模块（插件在工具里也能加载）。

## 过程

### 验证 2：用授权弹窗安装（任务 4）

- 安装包签名：`Developer ID Installer: Yuncao Liu (28HU5A7B46)`，`Notarization: trusted by the Apple notary service`；`spctl`：`accepted`，`source=Notarized Developer ID`。
- 命令（通过 SSH 在桌面会话里运行，模拟应用里的 `NSAppleScript`）：
  `sudo launchctl asuser $(id -u) sudo -u tester osascript -e 'do shell script "installer -pkg /tmp/Squirrel-1.1.2.pkg -target /" with administrator privileges'`
- 测试机窗口弹出授权框，用户输入 tester 的密码后：`The install was successful.`、`The install requires logging out now.`，`exit=0`。
- 安装后 TIS：本体 `Squirrel` enabled=false；`Squirrel.Hans` enabled=true；`Hant` enabled=false。和 `install-test-log.md` 里用 `sudo installer` 的结果一致。
- `install.log` 里 postinstall 的输出：`User already registered Squirrel method(s): ["…Squirrel.Hans"]`、`User already enabled …`、`Selection fails for input source: …Squirrel.Hans`。说明 postinstall 拿到了桌面用户并以他的身份执行了注册和启用（选中失败是已知的系统限制，要用户在系统设置里添加）。
- 另有一行 `User notification authorization error: Couldn’t communicate with a helper application.`，不影响安装。

### 验证 1：系统设置键盘页链接（任务 5）

- `open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"`（桌面会话里运行）：`exit=0`，系统设置打开后**直接停在「键盘」页**，能看到「Text Input → Input Sources … Edit…」和「Text Replacements…」按钮（用户截图确认）。备用链接 `com.apple.preference.keyboard` 没有必要再试。
- 用户在这一页手动添加鼠须管后：本体 `im.rime.inputmethod.Squirrel` enabled=true；`tis-probe select "=…Squirrel.Hans"` → OSStatus 0，`selected=true`。
- **新发现**：切换成功后等了 30 多秒，鼠须管进程**一直没有启动**，`~/Library/Rime` 也没生成（之前的记录里进程是在用户实际打字时才启动的）。用 `open "/Library/Input Methods/Squirrel.app"` 后 4 秒内启动，自动生成了 `build/`、`installation.yaml`、`user.yaml`。
  → 应用在用户添加好输入法、切换过去之后，应该主动 `open` 一次鼠须管，不要等它自己启动。

### 验证 4：下载和解压（任务 6）

- 测试机里 `curl` 下载：`jidian.zip` 1.9 MB、`full.zip` 16.0 MB、`cn_dicts.zip` 14.7 MB。
- `/usr/bin/ditto -x -k <zip> <目录>`：三个都 `exit=0`。干净的 macOS 27 上 `ditto` 自带可用。
- 目录结构整理在 [upstream-layouts.md](upstream-layouts.md)。对设计有影响的两点：
  - 雾凇 `full.zip` 自带 `custom_phrase.txt`，和应用要生成的同名文件冲突。
  - 雾凇 `full.zip` 自带 `default.yaml`、`squirrel.yaml`，放进用户目录后会覆盖鼠须管自带的默认设置。应用的外观、方案列表仍然通过 `*.custom.yaml` 补丁改，不受影响，但「上游默认值」要从这两个文件读。

### 验证 6：雾凇全拼、小鹤双拼（任务 7）

- 把 `full.zip` 解压后的内容 `rsync` 进测试机的 `~/Library/Rime`，加 `default.custom.yaml` 只启用 `rime_ice`、`double_pinyin_flypy`，然后 `Squirrel --reload`（鼠须管在运行）。
- 约 10 秒后 `build/` 里生成 `rime_ice.prism.bin`、`rime_ice.table.bin`（约 58 MB）、`rime_ice.reverse.bin`、`double_pinyin_flypy.prism.bin`。INFO 日志：`dictionary 'rime_ice' is ready`、`melt_eng`、`radical_pinyin` 都 ready，`finished updating schemas: 4 success, 0 failure`，耗时约 9 秒（12:16:30 → 12:16:38）。
- 没有 ERROR 日志（日志目录里没有 `*ERROR*` 文件）。WARNING 里只有上游词库的 `duplicate word definition`（英文词重复）和 `radical_pinyin.schema` 的 `circular dependencies detected`，都是上游自身的问题，不影响使用。
- `rime-type-probe`（在配置副本上）：

  | 方案 | 编码 | 前几个候选 |
  |---|---|---|
  | rime_ice | `nihao` | 你好、👋、拟好 |
  | rime_ice | `rq` | 2026-10-15、2026/10/15、…（Lua） |
  | rime_ice | `sj` | 12:17、12:17:14、…（Lua） |
  | rime_ice | `xiaolian` | 笑脸、😀、小脸（OpenCC emoji） |
  | double_pinyin_flypy | `nihc` | 你好 |
  | double_pinyin_flypy | `vsgo` | 中国、🇨🇳 |

  → `rime-type-probe` **能加载 Lua 和 OpenCC**，阶段 2 的打字检查可以测这类方案。
- 用户在测试机「文本编辑」里实际打字：`nihao` → 你好，`rq` 出日期，`sj` 出时间，`xiaolian` 有 emoji，小鹤 `nihc` → 你好。全部正常。

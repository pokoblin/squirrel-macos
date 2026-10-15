# 已验证的事实

调研时间：2026-10-14 ～ 2026-10-15。环境：Apple 芯片 Mac（M4 Pro），macOS 27.0.1，鼠须管 1.1.2（内置 librime 1.16）。

每条后面的「验证」说明这条是怎么确认的：
- **实测**：在真机或虚拟机里实际跑过。
- **查看**：读了文件或程序内容。
- **待验证**：还没确认，设计时不能当真。

---

## 1. 鼠须管本体

### 安装包

| 项目 | 内容 | 验证 |
|---|---|---|
| 下载地址 | `https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg`（25 MB） | 查看（GitHub API） |
| 签名 | `Developer ID Installer: Yuncao Liu (28HU5A7B46)`，已通过苹果公证 | 实测（`pkgutil --check-signature`、`spctl -a -t install`） |
| 安装位置 | `/Library/Input Methods/Squirrel.app`（系统目录，**要管理员密码**） | 实测 |
| 安装命令 | `sudo installer -pkg Squirrel-1.1.2.pkg -target /`，虚拟机里只用了 8 秒 | 实测 |
| Homebrew | cask `squirrel-app` 只是下载同一个 pkg 再运行，没有额外步骤。**不需要 Homebrew** | 查看（`brew info --cask --json=v2`） |
| 自动更新 | 鼠须管自带 Sparkle 2.6.2，自己会更新，前端不用管升级 | 查看（pkg 的 PackageInfo） |
| 许可证 | GPL-3.0 | 查看 |

### 安装包的 postinstall 脚本做了什么（查看）

1. 以当前登录用户身份 `killall Squirrel`；
2. `Squirrel --register-input-source`；
3. 在 `SharedSupport` 里运行 `Squirrel --build`，预编译自带方案（设置环境变量 `RIME_NO_PREBUILD` 可跳过）；
4. 以当前登录用户身份运行 `--enable-input-source` 和 `--select-input-source`。

PackageInfo 里写着 `postinstall-action="logout"`，所以安装程序会提示“需要注销”。**但实测不注销也能用**，见 [install-test-log.md](install-test-log.md)。

### 程序包内容（查看）

- `Contents/MacOS/`：`Squirrel`、`rime_deployer`、`rime_dict_manager`、`rime-install`
- `Contents/Frameworks/`：`librime.1.dylib`、`Sparkle.framework`、`rime-plugins/`（`librime-lua`、`librime-octagram`、`librime-predict`）
  - 自带 Lua 插件，所以雾凇拼音这类用 Lua 脚本的方案可以直接运行。
- `Contents/SharedSupport/` 自带的方案：
  - 明月拼音：`luna_pinyin`、`luna_pinyin_simp`、`luna_pinyin_fluency`、`luna_pinyin_tw`、`luna_quanpin`
  - 地球拼音：`terra_pinyin`、`terra_pinyin_12345`
  - 注音：`bopomofo`、`bopomofo_express`、`bopomofo_tw`
  - 仓颉：`cangjie5`、`cangjie5_express`
  - 笔画：`stroke`
  - 公共文件：`default.yaml`、`squirrel.yaml`、`key_bindings.yaml`、`punctuation.yaml`、`symbols.yaml`、`essay.txt`、`opencc/`

### `Squirrel` 命令行参数

| 参数 | 作用 | 验证 |
|---|---|---|
| `--register-input-source` | 向系统注册输入法 | 实测 |
| `--enable-input-source` | 启用（**只能启用到「简体」子模式，本体启用不了**，见第 2 节） | 实测 |
| `--select-input-source` | 切换到鼠须管（本体没启用时会失败：`Selection fails for input source`） | 实测 |
| `--disable-input-source` | 停用 | 查看（`strings`），未实测 |
| `--reload` | 让**正在运行的**鼠须管重新部署；异步，没有输出。鼠须管没在运行时什么也不发生 | 实测 |
| `--build` | 在当前目录编译方案（postinstall 用它预编译 SharedSupport） | 查看 |

### 单独编译：`rime_deployer`（实测）

不用启动鼠须管，就能直接把用户目录的配置编译好：

```bash
"/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer" --build <用户目录> "/Library/Input Methods/Squirrel.app/Contents/SharedSupport" <用户目录>/build
```

前端可以用它在副本上先编译、校验，再应用到真实配置。

### `rime-install`（东风破 plum）不能直接用（查看）

`rime-install` 是 bash 脚本，第一步就要 `git clone` 东风破仓库。新 Mac 上的 `/usr/bin/git` 只是一个空壳（201 KB），一运行就会弹窗要求安装“命令行开发者工具”。**前端要自己下载方案（GitHub 的 zip 包），不能依赖 git 或 rime-install。**

---

## 2. 输入法的启用和切换（最关键）

详细过程见 [install-test-log.md](install-test-log.md)。结论：

| 事实 | 验证 |
|---|---|
| 安装后，系统里有三个输入源：本体 `im.rime.inputmethod.Squirrel`，子模式 `…Squirrel.Hans`（简体）、`…Squirrel.Hant`（繁体） | 实测 |
| postinstall 之后：`Hans` 显示 enabled，**本体 enabled=false**；输入法菜单里看不到；`TISSelectInputSource` 返回 **-50** | 实测 |
| 用 `TISEnableInputSource` 启用本体，返回 0，但状态**不变** | 实测 |
| 启动鼠须管程序、重启 `TextInputMenuAgent`、重新注册和启用：**都没用** | 实测 |
| **注销再登录：也没用** | 实测 |
| 用户在「系统设置 → 键盘 → 文字输入 → 输入法 → 编辑… → + → 简体中文 → 鼠须管」**手动添加**后，本体立即 enabled=true，**马上能切换**，不用注销，也没有任何弹窗 | 实测（两台全新虚拟机） |
| 对照：用同样的程序方法切换系统自带的日文输入法，正常 | 实测（排除测试方法本身的问题） |
| 切换到鼠须管后，鼠须管进程才会启动；或者用 `open "/Library/Input Methods/Squirrel.app"` 手动启动 | 实测 |
| 判断“用户添加好了没有”：看本体 `im.rime.inputmethod.Squirrel` 的 `kTISPropertyInputSourceIsEnabled` | 实测 |
| 在宿主机上，`com.apple.HIToolbox` 偏好里的 `AppleEnabledInputSources` **找不到**鼠须管（只在 `AppleInputSourceHistory` 里），但 TIS 显示已启用。所以**别用读偏好文件的方法判断启用状态**，要用 TIS API | 实测 |
| 打开系统设置键盘页的链接 `x-apple.systempreferences:com.apple.Keyboard-Settings.extension` | **待验证** |

查看和切换输入源的小工具：[tools/vm/tis-probe.swift](../tools/vm/tis-probe.swift)。

---

## 3. 配置目录、部署和日志

| 事实 | 验证 |
|---|---|
| 用户配置目录 `~/Library/Rime`；鼠须管第一次运行时自动创建 | 实测 |
| 部署结果在 `~/Library/Rime/build/`（自动生成，别往里放东西）；第一次部署会生成 `installation.yaml`、`user.yaml` | 实测 |
| 改配置的正确方式：**写 `xxx.custom.yaml` 补丁**，不改原文件。部署时 Rime 自动把补丁合并进去 | 实测 |
| 日志在 `$TMPDIR/rime.squirrel/`（也就是 `$(getconf DARWIN_USER_TEMP_DIR)rime.squirrel`），文件名带 `INFO`、`WARNING`、`ERROR` | 实测 |
| 部署成功的标志：INFO 日志里有 `dictionary 'xxx' is ready.` 和 `finished updating schemas: N success, 0 failure` | 实测（宿主机）。注意：虚拟机里那行“finished”过了一会儿还没写进日志（INFO 日志有缓冲），**不能只靠这一行判断**；也可以检查 `build/xxx.table.bin` 是否生成、修改时间是否更新 |
| 第一次部署时，WARNING 日志里出现 `nonexistent config file '…/build/xxx.schema.yaml'` 是正常的 | 实测 |
| 部署约 90 万条的雾凇词库：宿主机几十秒，虚拟机 20 秒内完成；生成 `pinyin_ext.table.bin` 约 29 MB | 实测 |
| `user.yaml` 里的 `previously_selected_schema` 记录用户上次用的方案，比 `schema_list` 第一位的“默认方案”优先 | 实测 |

### 外观（`squirrel.custom.yaml`）

| 事实 | 验证 |
|---|---|
| 候选字大小由 `font_point` 控制；序号是 `label_font_point`；注释是 `comment_font_point` | 实测 |
| **`candidate_font_point` 无效**（方案文件注释说它管候选字，但鼠须管程序里根本没有这个键名） | 实测（`strings` 查二进制 + 改了不生效） |
| 浅色和深色模式各有一套配色（`color_scheme` / `color_scheme_dark`），字号要分别改 | 实测 |

### 按键（`default.custom.yaml`）

| 事实 | 验证 |
|---|---|
| 翻页键写在 `key_binder/bindings`，例如 `{ when: has_menu, accept: minus, send: Page_Up }` | 实测 |
| `Control + 0`（或 `` Control + ` ``）弹出方案菜单；`schema_list` 第一位是默认方案 | 实测 |

---

## 4. 方案和词库的行为

| 事实 | 验证 |
|---|---|
| 极点五笔的“拼音混输”方案，拼音部分走 `reverse_lookup_translator`，**只能打出词库里现成的整词，不会造句** | 实测 |
| 所以拼音词库的大小直接决定能打出哪些词。极点五笔自带的 `pinyin_simp` 只有约 10 万条旧词；换成雾凇 `cn_dicts`（8105 + base + ext，约 90 万条）后，“区块链、内卷、躺平、元宇宙”等都能打出来 | 实测（librime 模拟） |
| 词库可以用一个“总词库”文件（只写 `import_tables`）把多个词库挂在一起 | 实测 |
| 用户词库只写词、不写编码也行：部署时自动算五笔码（按组词规则）和拼音 | 实测 |
| 多音字自动生成的拼音可能不对，要手动写编码（词、编码、权重之间用 **Tab** 分隔） | 查看 |
| 极点五笔 86 有“四码唯一自动上屏” | 实测 |
| 自定义短语：在方案里加一个 `table_translator@custom_phrase`（`db_class: stabledb`、`initial_quality: 100`），数据来自 `custom_phrase.txt`（格式：`短语<Tab>编码<Tab>权重`），候选排第一位 | 实测 |

---

## 5. macOS「文本替换」导入

| 事实 | 验证 |
|---|---|
| 系统的文本替换只对苹果自己的输入法生效，鼠须管拿不到 | 实测 |
| 数据在 `~/Library/KeyboardServices/TextReplacements.db`（SQLite），表 `ZTEXTREPLACEMENTENTRY`，字段 `ZSHORTCUT`、`ZPHRASE`、`ZWASDELETED` | 实测 |
| 用系统自带的 `/usr/bin/sqlite3`（真程序，不是空壳）就能读，结果和 Python 版脚本**逐字节一致** | 实测 |
| `defaults read -g NSUserDictionaryReplacementItems` 里也有一份，条数一致；但是否每次都和数据库同步 | **待验证** |
| 能直接用的条件：快捷码只有字母（Rime 里打不出数字和符号），内容不含换行和 Tab | 实测 |
| 同一个 Apple 账户的文本替换会通过 iCloud 同步到别的 Mac | 查看（苹果的说明），未实测 |
| 独立的 .app（尤其是开了沙盒的）能不能读这个数据库，会不会被隐私权限拦住 | **待验证** |

可以直接复用的 SQL（已验证）：

```sql
SELECT ZPHRASE || char(9) || lower(ZSHORTCUT) || char(9) || '1'
FROM ZTEXTREPLACEMENTENTRY
WHERE (ZWASDELETED = 0 OR ZWASDELETED IS NULL)
  AND ZSHORTCUT IS NOT NULL AND ZPHRASE IS NOT NULL AND ZSHORTCUT <> ''
  AND ZSHORTCUT NOT GLOB '*[^A-Za-z]*'
  AND instr(ZPHRASE, char(9)) = 0 AND instr(ZPHRASE, char(10)) = 0 AND instr(ZPHRASE, char(13)) = 0
ORDER BY ZSHORTCUT;
```

---

## 6. 新 Mac 上有什么、没有什么（实测，干净虚拟机）

| 工具 | 新 Mac 上 |
|---|---|
| `/usr/bin/sqlite3` | ✅ 有，能直接用 |
| `/usr/bin/rsync`、`osascript`、`pkgutil`、`installer` | ✅ 有 |
| `/usr/bin/python3`、`/usr/bin/git`、`/usr/bin/swift` | ❌ 只是空壳，一运行就弹窗要求安装“命令行开发者工具” |
| Homebrew | ❌ 没有 |

**结论：前端应用不能依赖 python3、git、Homebrew。** 下载、解压、读 SQLite 都要在应用里自己做（Swift 自带 SQLite 库）。

---

## 7. 上游方案和词库

都可以通过 GitHub 直接下载 zip，不需要 git：`https://codeload.github.com/<仓库>/zip/<分支或标签>`（**待验证**：前端里实际下载、解压）。

| 仓库 | 内容 | 许可证 | 最近更新 |
|---|---|---|---|
| `rime/squirrel` | 鼠须管本体 | GPL-3.0 | 1.1.2（2026-01-14 发布） |
| `KyleBing/rime-wubi86-jidian` | 极点五笔 86（含拼音混输、简入繁出等方案；不发 Release，只能下仓库 zip） | Apache-2.0 | 2026-10 |
| `iDvel/rime-ice` | 雾凇拼音：全拼、**7 种双拼**（自然码、小鹤、微软、搜狗、紫光、智能ABC、拼音加加）、大词库、英文词库、Lua 脚本 | GPL-3.0 | 2026-10-05 |
| `rime/rime-double-pinyin` | 官方双拼方案（基于明月拼音词库） | GPL-3.0 | 2025-09 |
| `rime/rime-luna-pinyin` | 明月拼音（鼠须管已自带） | LGPL-3.0 | 2026-07 |
| `rime/rime-pinyin-simp` | 袖珍简化字拼音 | Apache-2.0 | 2024-12 |
| `rime/rime-wubi` | 官方五笔 86 | LGPL-3.0 | 2024-01 |
| `rime/rime-stroke`、`rime-prelude`、`rime-essay` | 笔画、公共配置、八股文语言模型 | LGPL-3.0 | 2026 |
| `gaboolic/rime-shuangpin-fuzhuma` | 双拼 + 辅助码 | MIT | 2026-09 |
| `rime/plum` | 东风破（方案安装器，依赖 git） | LGPL-3.0 | 2026-05 |

雾凇在 `nightly` 这个 Release 里提供打包好的文件（每次更新词库时重新上传，2026-10-05）：
`cn_dicts.zip`（14.7 MB）、`all_dicts.zip`（15.6 MB）、`en_dicts.zip`、`full.zip`（16 MB，完整方案）、`full_compiled.zip`（47 MB，含编译好的文件）、`opencc.zip`。

**许可证提醒**：雾凇和官方双拼是 GPL-3.0。前端如果不是 GPL 开源，最好在运行时下载这些方案，而不是打包进应用。Apache、MIT 的可以打包，但要附上许可声明。

---

## 8. 用 librime 模拟打字（验证配置的方法）

不用真的切换输入法，就能确认“打某个编码会出什么候选”。前端也可以用这个做“试打预览”。

- 库：`/Library/Input Methods/Squirrel.app/Contents/Frameworks/librime.1.dylib`（librime 1.16）。只导出 `rime_get_api`，没有旧版的 `RimeSetup` 等 C 函数。
- `rime_get_api()` 返回函数表。跳过开头的 `int data_size`（加上对齐共 8 字节）后，函数指针下标：setup 0、initialize 2、finalize 3、create_session 13、process_key 18、clear_composition 20、get_commit 21、free_commit 22、get_context 23、free_context 24、select_schema 34。
- `RimeTraits` 字段顺序：data_size, shared_data_dir（`…/Squirrel.app/Contents/SharedSupport`）, user_data_dir, distribution_name, distribution_code_name, distribution_version, app_name, modules, min_log_level, log_dir, prebuilt_data_dir, staging_dir。
- **永远在配置副本上测**：`cp -R ~/Library/Rime` 到临时目录，先用 `rime_deployer --build` 编译副本。
- 按键：小写字母直接 `process_key(session, ord(ch), 0)`；每测一个编码前先 `clear_composition`。
- 先读 commit，再读 context：四码唯一会自动上屏，这时候选为空不代表失败。
- 候选文字本身可能含空格，比对时别按空格拆分。
- 编译后的 `table.bin` 里文字是压缩的，直接 grep 查不到词，不能用来验证。

（当时用 Python ctypes 实现；librime 是 C 接口，Swift 也能直接调用。）

---

## 9. 测试环境本身的事实

| 事实 | 验证 |
|---|---|
| Apple 芯片上的 VMware Fusion **不能运行 macOS 虚拟机** | 查看 |
| Tart 能用：用 `tart create --from-ipsw latest` 建 macOS 虚拟机，镜像约 18 GB，大约 20 分钟 | 实测 |
| 从底板克隆一台测试机并能 SSH 连进去，大约 10 秒 | 实测 |
| 虚拟机里的系统版本不能比宿主机新；苹果规定一台 Mac 最多同时运行 2 台 macOS 虚拟机 | 查看 |
| 宿主机的剪贴板目前粘贴不进虚拟机 | 实测 |
| 用 computer-use 在 Tart 窗口里点击，坐标会偏（误点开了苹果菜单）。界面操作最好让用户自己点，或者改用 SSH 命令 | 实测 |

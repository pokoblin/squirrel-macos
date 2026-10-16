# 试打预览设计

- 日期：2026-10-16
- 状态：**已确认（2026-10-16）**
- 属于：第二版的第 2 个子项目（见 [第二版路线图](../plans/2026-10-15-v2-roadmap.md)）；需求是 [需求草稿](../../requirements-draft.md) 的 F9
- 依据：[verified-facts.md](../../verified-facts.md) 第 8 节「用 librime 模拟打字」和 8.1 节（这次的小试验）

---

## 1. 目标

在应用界面里输入编码，直接看候选，不用切换输入法。用鼠须管自带的 librime，所以看到的结果和真的用鼠须管打字一样（包括 Lua、OpenCC）。

它也是子项目 3（个人词库编辑器）的基础：编辑器要用它检查新加的词能不能用某个编码打出来。

### 用户定下的几件事

| 问题 | 决定 |
|---|---|
| 预览哪份配置 | **两种都要**：默认是「当前生效」的配置；有未应用的改动时，可以切到「应用后的样子」先试打 |
| 能做到哪一步 | **看候选 + 翻页 + 选词上屏**：能连着打一句话，自动上屏（比如五笔四码唯一）也算。不做「尽量像真实打字」那一档（不处理组合键、Shift 切中英文） |
| 带不带输入习惯 | **不带**：候选顺序是词库本来的顺序，和新装的电脑一样，结果稳定；也不用复制鼠须管正在写的输入习惯数据库 |
| 界面放哪 | **侧边栏新增「试打」页**，排在「方案」后面 |
| 怎么加载 librime | **单独的辅助程序**：只有它带 `disable-library-validation`，主应用保持库验证 |

### 不做的事

- 不在宿主机或测试机的真实 `~/Library/Rime` 上跑 librime，永远用副本。
- 不带用户的输入习惯（`*.userdb`）。
- 不处理 Ctrl、Option、Command 组合键，不做 Shift 切中英文、不做中英文状态切换按钮。
- 不联网：「应用后的样子」只用本地已经下载过的方案包。
- 不在这个子项目里发版。

---

## 2. 为什么要辅助程序（小试验的结论）

详细记录见 verified-facts 8.1。要点：

1. 发布版应用用 Developer ID 签名并开了 hardened runtime。这样的进程加载鼠须管的 `librime.1.dylib`（团队 `28HU5A7B46`）会失败：`mapping process and mapped file (non-platform) have different Team IDs`。
2. 加上 `com.apple.security.cs.disable-library-validation` 就能加载，Lua、OpenCC 插件也正常。我们的程序不可能和鼠须管同一个团队，**加载 librime 的进程一定要有这个 entitlement**。
3. 实测「主程序不加 entitlement、它启动的辅助程序加」：主程序自己加载失败，辅助程序正常出候选。

所以两条路的区别只是 entitlement 加在哪。选辅助程序的理由：

- 主应用会用管理员权限安装鼠须管，保持库验证更安全。
- 函数表是按下标硬写的。鼠须管哪天升级改了结构，最多辅助程序崩掉，界面提示出错，主应用不受影响。
- 雾凇的词库映射约 70 MB，加上 librime 的全局状态，离开页面就随进程释放。
- `rimectl` 和测试可以直接用同一个辅助程序。

debug 包（临时签名、没开 hardened runtime）本来就能加载，**所以测试机里装 debug 包试不出签名问题**，必须另外测发布签名的包（见 8.3）。

---

## 3. 组成部分

```
┌──────────── 主应用 / rimectl（库验证照常） ────────────┐
│ AppUI: PreviewPage        AppCore: PreviewModel         │
│ RimeKit: PreviewWorkspace  PreviewSession  PreviewProbe │
└──────────────┬──────────────────────────────────────────┘
               │ stdin / stdout，每行一个 JSON
┌──────────────▼──────────────────────────────┐
│ rime-preview-helper（带 disable-library-validation） │
│   dlopen 鼠须管的 librime.1.dylib，开一个会话           │
└─────────────────────────────────────────────┘
```

### 3.1 新的 target

| target | 类型 | 作用 |
|---|---|---|
| `CRimeAPI` | C（只有头文件） | librime 1.16 的结构体和函数表前缀，只声明用到的下标（verified-facts 第 8、8.1 节） |
| `RimePreviewProtocol` | Swift 库 | 请求和结果的 `Codable` 类型，辅助程序和 RimeKit 共用；不依赖别的 target |
| `rime-preview-helper` | Swift 可执行文件 | 依赖上面两个。不依赖 RimeKit（保持小） |

RimeKit 依赖 `RimePreviewProtocol`。

### 3.2 辅助程序 `rime-preview-helper`

- 启动参数：`--squirrel <Squirrel.app 路径>`，默认 `/Library/Input Methods/Squirrel.app`（测试可以换）。
- 启动后先 `dlopen` librime、取 `rime_get_api`，**还不初始化**；等第一条 `open` 请求。
- 从 stdin 一行读一个请求，往 stdout 一行写一个结果。stdin 关掉就 `finalize` 后退出，所以主应用退出或崩溃时它也跟着结束。
- stderr 只用来写自己的诊断；librime 的 glog INFO 行也会出现在这里（`min_log_level` 管不住，见 8.1），由调用方过滤。
- **第二道保险**：`open` 的目录如果是（或在）真实的 `~/Library/Rime` 里，直接拒绝。判断逻辑和 `RimeDirectoryGuard` 一样（设备号 + inode，家目录看 passwd、`$HOME`、`SUDO_UID`），在辅助程序里单独实现一份（辅助程序不依赖 RimeKit），两边的测试用同一组用例。
- **版本检查**：`get_version` 的主版本是 1、次版本 ≥ 16，并且 `data_size` 够大、包含用到的最大下标（74），才继续；否则回 `unsupportedVersion`。librime 的函数表只往后加，用 `data_size` 表示长度，所以更新的 1.x 一般能用；万一结构变了，崩溃也只在辅助程序里。
- 日志目录（`log_dir`）指向副本目录，不碰鼠须管的日志。`app_name` 用 `rime.squirrel-helper-preview`，`distribution_name` 用 `SquirrelHelper`。

### 3.3 通信协议

请求（一行一个 JSON）：

| `op` | 其他字段 | 做什么 |
|---|---|---|
| `open` | `userDir`、`schema` | 第一次时 `setup` + `initialize`；目录变了就 `finalize` 后用新目录 `initialize`（8.1 实测可以）。然后建会话、选方案 |
| `input` | `text` | 每个字符 `process_key(字符, 0)`，只收可打印 ASCII（`0x20`–`0x7e`），其他字符回 `badRequest` |
| `key` | `name` | 特殊键，见下表 |
| `select` | `index` | `select_candidate_on_current_page(index)`，本页从 0 开始 |
| `clear` | — | `clear_composition`，清掉编码 |

特殊键（X11 键码，传给 `process_key`）：

| `name` | 键码 | 实测 |
|---|---|---|
| `backspace` | `0xff08` | 8.1 已测 |
| `escape` | `0xff1b` | 8.1 已测 |
| `pageUp` | `0xff55` | 8.1 已测 |
| `pageDown` | `0xff56` | 8.1 已测 |
| `return` | `0xff0d` | 实现时用集成测试确认 |
| `up` | `0xff52` | 同上 |
| `down` | `0xff54` | 同上 |

结果：

```json
{"ok": true, "librimeVersion": "1.16.0",
 "state": {"committed": "你好", "preedit": "ni hao", "cursor": 6,
           "candidates": [{"text": "你好", "comment": ""}],
           "labels": null, "pageNo": 0, "isLastPage": false, "highlighted": 0}}
```

- `committed`：这次请求以后 `get_commit` 拿到的上屏文字，没有就是 `null`。**先读上屏再读候选**（四码唯一自动上屏时候选为空，不算失败）。
- `labels`：方案的选择键标签（`select_labels`），没有就是 `null`，界面用 1、2、3……
- `librimeVersion` 只在 `open` 的结果里有。

出错：`{"ok": false, "error": {"kind": "…", "message": "…"}}`，`kind` 是：

| `kind` | 什么时候 |
|---|---|
| `loadFailed` | `dlopen` 失败，`message` 带上 `dlerror()` 原文 |
| `unsupportedVersion` | 版本检查没过 |
| `refusedDirectory` | 目录是真实的 `~/Library/Rime` |
| `schemaMissing` | 副本里没有 `build/<方案>.schema.yaml`，或者选完以后 `get_current_schema` 不是这个方案（`select_schema` 遇到不存在的方案也返回成功，见 8.1） |
| `notOpen` | 还没 `open` 就发了别的请求 |
| `badRequest` | JSON 看不懂、`op` 不认识、字符不合法 |

### 3.4 RimeKit：`PreviewWorkspace`（准备副本）

副本都放在应用数据目录的 `staging/preview-<UUID>/` 下，用完删掉；进程被杀留下的旧副本由现有的 `AppPaths.cleanStaleStaging` 在应用启动时清理。准备副本只读 `~/Library/Rime`，**不拿应用锁**，不影响「应用改动」。

**当前生效**（`current`）：

- 把 `~/Library/Rime`（是符号链接就先解析）复制到副本，用 APFS 克隆（`FileManager.copyItem` 在 APFS 上会克隆；8.1 实测整个目录 0.01 秒）。
- **连 `build/` 一起复制**，不重新编译：看到的就是鼠须管现在用的编译结果，打开只要约 0.1 秒。
- 不复制：`*.userdb/`、`*.userdb.txt`、`sync/`、`user.yaml`、`installation.yaml`、`.git/`。
- `~/Library/Rime/build` 不存在（从没部署过）→ 报 `notDeployed`。

**应用后的样子**（`pending`）：

- 输入是界面上的设置（`draft`，含未应用的改动），生成 `GenerationInput` 的方法和「应用改动」一样，区别：
  - **方案包只用本地缓存，不联网**。缺哪个就报 `packagesNotCached([名字])`，界面提示「这些方案还没下载过，应用改动时会下载」。
  - 打开了文本替换同步时照样读 macOS 文本替换；读不了就不带这些短语，界面加一行说明，不算失败。
- 拼目录、编译：把 `Deployer.apply` 第 3 步（「现有的、应用不管的配置文件 + 新生成的」拼成完整目录，再用 `rime_deployer` 编译）抽成共用函数，`apply` 和预览都调它。编译失败报 `compileFailed`（已翻译的错误），和「应用」时看到的一样。
- 雾凇全拼编译约 10 秒（8.1）。

**方案列表**：从副本的 `build/default.yaml` 里读 `schema_list`，只留下 `build/<方案>.schema.yaml` 存在的，名字取编译后方案文件里的 `schema/name`。

### 3.5 RimeKit：`PreviewSession`（和辅助程序对话）

- 找辅助程序：应用里是 `Contents/Helpers/rime-preview-helper`；`rimectl` 和测试在自己的可执行文件旁边找（`.build/debug/`）。
- 启动时检查副本目录不是真实的 `~/Library/Rime`（`RimeDirectoryGuard`，第一道保险）。
- 每个请求有超时：`open` 15 秒，其他 5 秒。超时就杀掉辅助程序，报 `timedOut`。
- 辅助程序退出、崩溃、回了看不懂的内容 → 报 `helperDied(退出码, stderr 最后几行)`，stderr 先滤掉 glog 的 `I…` 行和 `WARNING: Logging before InitGoogleLogging()`。
- 是 `actor`，一次只发一个请求。

### 3.6 RimeKit：`PreviewProbe`（留给子项目 3）

`func find(_ text: String, code: String, maxPages: Int) async throws -> Match?`：清空、输入编码、在候选里找这个词，找不到就翻页，最多翻 `maxPages` 页。返回页码和本页序号；自动上屏的情况也算找到（序号记为 0）。`rimectl preview --find` 和以后的词库编辑器都用它。

### 3.7 `rimectl preview`

```
rimectl preview [--pending] [--data-dir <目录>] --schema <方案id> <编码>...
rimectl preview [--pending] --list                      列出方案
rimectl preview --schema <方案id> --find <词> <编码>      找这个词在第几页第几个
```

每个编码一行：先上屏文字（如果有），再本页候选。`--pending` 用已保存的设置（`rimectl` 没有草稿）生成。

---

## 4. 界面：「试打」页

侧边栏在「方案」后面加「试打」（图标 `keyboard`）。从上到下：

1. **一行选项**：
   - 「来源」：分段控件「当前生效 / 应用后的样子」。没有未应用的改动时「应用后的样子」是灰的。
   - 「方案」：下拉框，列出副本里的方案，默认第一个。
2. **输入区**：一个能获得焦点的框（不是普通文本框）。显示 librime 给的编码（`preedit`），下面是本页候选，每个是「序号. 文字 注释」；按钮「上一页」「下一页」「清空」。点候选等于选这个词。
3. **已上屏**：选中、自动上屏的文字接在这里，能连着打一句话；按钮「清空」。
4. 准备副本、编译时显示进度（「正在复制配置……」「正在编译……」）；出错时显示说明和「重试」。

### 4.1 按键

焦点在输入区时：

- 可打印 ASCII 字符（字母、数字、标点、空格）原样交给 librime，所以数字选词、空格上屏、`-` `=` 翻页、四码自动上屏都按方案自己的设置来。大写字母（按着 Shift 打）也是原样传字符。
- 退格、Esc、回车、PageUp、PageDown、上、下方向键翻成 3.3 表里的键名。
- 带 Ctrl、Option、Command 的组合键不处理，交给系统（比如 ⌘W 照样关窗口）。

### 4.2 数据流

- **进入页面**：准备「当前生效」副本 → 启动辅助程序 → 读方案列表 → `open` 第一个方案。
- **换方案**：同一个辅助程序再发 `open`（目录不变，只换方案）。
- **换来源**：准备新副本 → 对同一个辅助程序发 `open`（换目录）→ 删掉旧副本。
- **离开页面**：关掉辅助程序的 stdin，删掉副本。
- **配置变了**：在页面上时，如果刚应用了改动（「当前生效」变了），或者 `draft` 又改了（「应用后的样子」变了），显示「配置变了，重新载入」，点一下重建副本。不自动重建，免得打到一半被打断。
- 在副本里选词会让 librime 在副本里记一点输入习惯，只影响这次预览，删副本时一起删掉。

### 4.3 AppCore：`PreviewModel`

界面逻辑放在 AppCore（可测、不含 SwiftUI），和现有的 `MainModel` 一样的做法。状态：来源、方案列表、当前方案、`preedit`、候选、页码、已上屏文字、正在准备/出错、是否需要重新载入。按键对照（键 → `input`/`key` 请求）也放这里。它通过一个协议用 `PreviewSession` 和 `PreviewWorkspace`，测试时换成假的。

---

## 5. 出错处理

| 情况 | 界面上说什么 |
|---|---|
| 没装鼠须管 | 「先安装鼠须管」，带去「诊断」页的按钮 |
| `notDeployed` | 「鼠须管还没部署过配置」；有未应用的改动时提示可以改看「应用后的样子」 |
| `packagesNotCached` | 「这些方案还没下载过：……，应用改动时会下载」 |
| `compileFailed` | 「新配置编译不过」+ 翻译过的错误，和「应用」时一样 |
| `schemaMissing` | 「副本里找不到方案 X」。「当前生效」是在鼠须管部署到一半时复制的就可能这样，提示点「重新载入」 |
| `loadFailed` 且是 Team ID 不同 | 「应用的签名有问题，试打用不了」——这是打包漏了 entitlement，是我们的错，不让用户自己处理 |
| `loadFailed` 其他 | 「加载不了鼠须管的 librime」+ 原文 |
| `unsupportedVersion` | 「这个版本的鼠须管（librime X）还没验证过，暂时不能试打」 |
| `timedOut`、`helperDied` | 「试打出错了」+「重试」；展开能看退出码和 stderr 最后几行 |

主应用在任何情况下都不因为试打出错而退出。

---

## 6. 打包和签名

- `Package.swift`：加 3.1 的三个 target 和 `rime-preview-helper` 产品。
- `tools/app/preview-helper.entitlements`：只有 `com.apple.security.cs.disable-library-validation`。
- `tools/app/build-app.sh`：编译辅助程序，复制到 `Contents/Helpers/rime-preview-helper`。签名顺序：资源包 → 辅助程序（带上面的 entitlement；发布时加 `--options runtime --timestamp`）→ 应用本身（不带 entitlement）。不用 `--deep`（会把辅助程序的 entitlement 覆盖掉）。debug 包用临时签名，同样给辅助程序带上 entitlement 文件，保持一致。
- `tools/release/check-dmg.sh`：加检查：辅助程序有 hardened runtime 和这个 entitlement；主应用没有这个 entitlement。
- 公证：苹果文档把这个 entitlement 列为允许的例外；第一次打带辅助程序的发布包时确认能通过公证，结果记进 verified-facts。

---

## 7. 对现有代码的改动

- `Deployer.apply` 第 3 步抽成共用函数（行为不变，现有测试照常通过）。
- `MainModel` 的侧边栏页面加 `.preview`；应用改动成功后通知 `PreviewModel`「当前生效变了」。
- `AppPaths` 不加新目录（副本放 `staging/`）。
- 测试辅助 `RimeTools.type`（用 `tools/vm/rime-type-probe`）保留不动；新测试用辅助程序。

---

## 8. 测试

### 8.1 单元测试（不需要 librime）

- 协议：每种请求和结果的编解码；看不懂的输入。
- `PreviewWorkspace`：临时目录里放假的 Rime 目录，检查复制时排除了 userdb 等文件、带了 `build/`；拒绝真实目录；没有 `build/` 报 `notDeployed`；`pending` 缺包报 `packagesNotCached`；方案列表只留编译出来的。
- `PreviewSession`：用一个假的辅助程序（测试里生成的小脚本）测正常对话、超时、中途退出、乱码、stderr 过滤。
- 辅助程序的目录保险：和 `RimeDirectoryGuardTests` 用同一组用例。
- `PreviewModel`：按键对照、换来源/方案、上屏文字累加、「配置变了」提示、各种错误的提示文字。

### 8.2 宿主机集成测试（装了鼠须管才跑，只用临时目录）

和现有的 `GeneratedConfigCompileTests` 一样：用测试夹具生成配置、编译，然后启动真的辅助程序（`swift build` 编出来的）：

- 出候选（`nihao` → 你好）、翻页、选本页第 n 个上屏、退格、Esc、回车、上下方向键；
- 方案不存在报 `schemaMissing`；同一个辅助程序换目录、换方案；
- `PreviewProbe.find`：第一页、要翻页才找到、找不到；
- `rimectl preview` 的输出。

### 8.3 测试机（squirrel-dev）

1. debug 包（`./tools/vm/install-app.sh squirrel-dev`）：试界面，两种来源、换方案、选词上屏、翻页、自动上屏、出错提示。
2. **发布签名的包**（`SKIP_NOTARIZE=1 ./tools/release/build-release.sh`，Developer ID + hardened runtime）：放进测试机打开，确认试打能用；`codesign -d --entitlements -` 确认只有辅助程序带 entitlement。
3. 两次都在前后对比真实 `~/Library/Rime` 所有文件的修改时间和大小，确认没变（鼠须管同时在运行）。
4. 测完把结论写进 verified-facts，测试机记录写进 `docs/` 下的测试记录。

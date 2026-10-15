# 阶段 0：待验证项 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在测试机里把设计第 10 节的 6 个待验证项逐一跑出结论，写进 `docs/verified-facts.md`；顺便做出后面阶段要用的两个测试小工具，并记录上游包的真实目录结构。

**Architecture:** 宿主机只负责编译小工具、在**配置副本**上做打字检查；所有会改系统的操作（安装鼠须管、添加输入法、改 `~/Library/Rime`）都在长期测试机 `squirrel-dev` 里做，通过 `tools/vm/vm.sh ssh` 执行。需要桌面会话的命令用 `sudo launchctl asuser $(id -u) sudo -u tester …` 运行。需要用户亲手做的步骤会明确标出。

**Tech Stack:** Tart 测试机、bash、C（clang，打字检查工具）、Swift（swiftc，文本替换检查应用）、鼠须管 1.1.2 自带的 `librime.1.dylib`、`rime_deployer`、`rime_dict_manager`。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 10 节）；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## Global Constraints

- 不碰宿主机的 `~/Library/Rime`、`/Library/Input Methods`、输入法启用状态。宿主机上的打字检查只用 `../squirrel-wubi86/rime/` 的**副本**。
- 宿主机可以只读运行 `/Library/Input Methods/Squirrel.app` 里的程序（`rime_deployer`、`rime_dict_manager`、`librime.1.dylib`），但只能指向临时目录。
- 文本替换、个人词库只统计条数、比对哈希，不打印内容。
- 不要直接启动或修改底板 `macos-base`；测试机一律克隆。
- 测试机里登录桌面、输密码、在系统设置里点选，都由用户亲手做；需要时停下来请用户操作。
- 用 computer-use 点 Tart 窗口坐标会偏，不要用；要看画面就请用户描述。
- 提交：本目录还不是 git 仓库。是否 `git init`、能否按任务提交，由用户在执行前决定；各任务的「提交」步骤只在用户同意后执行。
- 所有测试结果先写进工作记录 `docs/phase0-log.md`（任务 3 创建），任务 10 再整理进 `verified-facts.md`。

## Review Focus

1. 打字检查工具被误指向真实的 `~/Library/Rime` → 应直接拒绝运行（任务 1 有测试）。
2. 文本替换检查应用把内容写进结果文件 → 结果文件只能有固定的几个键（任务 2 有检查）。
3. 通过 SSH + `launchctl asuser` 运行 `osascript` 时，授权框不出现或直接报错 → 记录现象，改为请用户在测试机终端里手动运行同一条命令，区分「方法不行」和「SSH 环境不行」（任务 4 有后备步骤）。
4. 上游 zip 的顶层目录名随分支、版本变化 → 一律用 `find` 定位文件，不写死路径（任务 6、7）。
5. 鼠须管运行时用 `rime_dict_manager` 操作，可能损坏输入习惯数据库 → 操作前先备份测试机里的 `*.userdb`（任务 8）。

---

### Task 1: 打字检查工具 `rime-type-probe`

**Files:**
- Create: `tools/vm/rime-type-probe.c`
- Create: `tools/vm/build-probes.sh`
- Create: `.gitignore`
- Test: 在 `../squirrel-wubi86/rime` 的副本上运行（命令见步骤）

**Interfaces:**
- Produces: 可执行文件 `tools/vm/rime-type-probe`，用法 `rime-type-probe <用户目录> <方案id> <编码>...`。每个编码输出一行：`编码<Tab>[上屏]文字 候选1 | 候选2 | …`（最多 5 个候选）。用户目录必须已经用 `rime_deployer --build` 编译过。用户目录是真实的 `~/Library/Rime` 时，以退出码 3 拒绝运行。阶段 2 的打字检查会复用它。

- [ ] **Step 1: 写 `.gitignore`**

```gitignore
# 编译出来的测试工具
tools/vm/tis-probe
tools/vm/rime-type-probe
tools/vm/TRProbe.app/
# 只给本机用的密钥
tools/vm/tart_vm_ed25519.pub
# Swift / Xcode
.build/
DerivedData/
*.xcuserstate
.DS_Store
```

- [ ] **Step 2: 写 `tools/vm/rime-type-probe.c`**

```c
// 测试工具：在一份 Rime 用户目录（必须是副本）上模拟打字，打印上屏文字和候选。
// 用法：rime-type-probe <用户目录> <方案id> <编码>...
// 用户目录要先用 rime_deployer --build 编译过。拒绝在真实的 ~/Library/Rime 上运行。
#include <dlfcn.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SQUIRREL "/Library/Input Methods/Squirrel.app/Contents"

typedef uintptr_t RimeSessionId;
typedef int Bool;

typedef struct {
  int data_size;
  const char *shared_data_dir;
  const char *user_data_dir;
  const char *distribution_name;
  const char *distribution_code_name;
  const char *distribution_version;
  const char *app_name;
  const char **modules;
  int min_log_level;
  const char *log_dir;
  const char *prebuilt_data_dir;
  const char *staging_dir;
} RimeTraits;

typedef struct { int length, cursor_pos, sel_start, sel_end; char *preedit; } RimeComposition;
typedef struct { char *text; char *comment; void *reserved; } RimeCandidate;
typedef struct {
  int page_size, page_no;
  Bool is_last_page;
  int highlighted_candidate_index;
  int num_candidates;
  RimeCandidate *candidates;
  char *select_keys;
} RimeMenu;
typedef struct { int data_size; char *text; } RimeCommit;
typedef struct {
  int data_size;
  RimeComposition composition;
  RimeMenu menu;
  char *commit_text_preview;
  char **select_labels;
} RimeContext;

// librime 1.16 的函数表，只声明用到的前 35 项（下标见 docs/verified-facts.md 第 8 节）
typedef struct {
  int data_size;
  void (*setup)(RimeTraits *);                          // 0
  void *set_notification_handler;                       // 1
  void (*initialize)(RimeTraits *);                     // 2
  void (*finalize)(void);                               // 3
  void *unused_4_12[9];                                 // 4..12
  RimeSessionId (*create_session)(void);                // 13
  void *unused_14_17[4];                                // 14..17
  Bool (*process_key)(RimeSessionId, int, int);         // 18
  void *commit_composition;                             // 19
  void (*clear_composition)(RimeSessionId);             // 20
  Bool (*get_commit)(RimeSessionId, RimeCommit *);      // 21
  Bool (*free_commit)(RimeCommit *);                    // 22
  Bool (*get_context)(RimeSessionId, RimeContext *);    // 23
  Bool (*free_context)(RimeContext *);                  // 24
  void *unused_25_33[9];                                // 25..33
  Bool (*select_schema)(RimeSessionId, const char *);   // 34
} RimeApiPrefix;

static int is_real_rime_dir(const char *dir) {
  const char *home = getenv("HOME");
  if (!home) return 0;
  char real_rime[PATH_MAX], given[PATH_MAX], path[PATH_MAX];
  snprintf(path, sizeof path, "%s/Library/Rime", home);
  if (!realpath(path, real_rime)) return 0;   // 本机没有 ~/Library/Rime
  if (!realpath(dir, given)) return 0;
  return strcmp(real_rime, given) == 0;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "用法：%s <用户目录> <方案id> <编码>...\n", argv[0]);
    return 2;
  }
  if (is_real_rime_dir(argv[1])) {
    fprintf(stderr, "拒绝运行：这是真实的 ~/Library/Rime，请传一份副本\n");
    return 3;
  }
  void *lib = dlopen(SQUIRREL "/Frameworks/librime.1.dylib", RTLD_NOW);
  if (!lib) { fprintf(stderr, "加载 librime 失败：%s\n", dlerror()); return 1; }
  RimeApiPrefix *(*get_api)(void) = (RimeApiPrefix *(*)(void))dlsym(lib, "rime_get_api");
  if (!get_api) { fprintf(stderr, "找不到 rime_get_api\n"); return 1; }
  RimeApiPrefix *api = get_api();

  RimeTraits traits;
  memset(&traits, 0, sizeof traits);
  traits.data_size = (int)(sizeof(RimeTraits) - sizeof(int));
  traits.shared_data_dir = SQUIRREL "/SharedSupport";
  traits.user_data_dir = argv[1];
  traits.distribution_name = "rime-type-probe";
  traits.distribution_code_name = "rime-type-probe";
  traits.distribution_version = "0.1";
  traits.app_name = "rime.probe";
  traits.min_log_level = 3;           // 只记 FATAL
  traits.log_dir = argv[1];           // 日志写进副本目录，不碰鼠须管的日志
  api->setup(&traits);
  api->initialize(&traits);

  RimeSessionId session = api->create_session();
  if (!session) { fprintf(stderr, "创建会话失败\n"); return 1; }
  if (!api->select_schema(session, argv[2])) {
    fprintf(stderr, "选择方案失败：%s\n", argv[2]);
    return 1;
  }
  for (int i = 3; i < argc; i++) {
    api->clear_composition(session);
    for (const char *p = argv[i]; *p; p++) api->process_key(session, (unsigned char)*p, 0);
    printf("%s\t", argv[i]);
    // 先读上屏：四码唯一会自动上屏，这时候选为空不算失败
    RimeCommit commit = {0};
    commit.data_size = (int)(sizeof(RimeCommit) - sizeof(int));
    if (api->get_commit(session, &commit)) {
      printf("[上屏]%s ", commit.text);
      api->free_commit(&commit);
    }
    RimeContext ctx;
    memset(&ctx, 0, sizeof ctx);
    ctx.data_size = (int)(sizeof(RimeContext) - sizeof(int));
    if (api->get_context(session, &ctx)) {
      for (int k = 0; k < ctx.menu.num_candidates && k < 5; k++)
        printf("%s%s", k ? " | " : "", ctx.menu.candidates[k].text);
      api->free_context(&ctx);
    }
    printf("\n");
  }
  api->finalize();
  return 0;
}
```

- [ ] **Step 3: 写 `tools/vm/build-probes.sh`（任务 2 会往里加一段）**

```bash
#!/bin/bash
# 编译测试小工具，输出到 tools/vm/ 下（测试机里通过共享文件夹 /Volumes/My Shared Files/vm/ 访问）
set -euo pipefail
cd "$(dirname "$0")"

clang -O2 -Wall -o rime-type-probe rime-type-probe.c
echo "已编译 tools/vm/rime-type-probe"
```

运行：`chmod +x tools/vm/build-probes.sh && ./tools/vm/build-probes.sh`
预期：输出 `已编译 tools/vm/rime-type-probe`，没有警告。

- [ ] **Step 4: 测试「拒绝真实目录」（Review Focus 1）**

运行：`./tools/vm/rime-type-probe ~/Library/Rime wubi86_jidian g; echo "exit=$?"`
预期：输出 `拒绝运行：这是真实的 ~/Library/Rime，请传一份副本` 和 `exit=3`。这个测试不会加载 librime，也不会读写这个目录。

- [ ] **Step 5: 在参考配置的副本上测打字**

```bash
T=/private/tmp/claude-501/-Users-kbys-workspace-vibe-coding-squirrel-macos/d2009d83-5a93-4c0a-aade-270800c3ef24/scratchpad/probe-test
rm -rf "$T" && mkdir -p "$T"
rsync -a --exclude '*.userdb' ../squirrel-wubi86/rime/ "$T/rime/"
"/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer" --build "$T/rime" "/Library/Input Methods/Squirrel.app/Contents/SharedSupport" "$T/rime/build"
./tools/vm/rime-type-probe "$T/rime" wubi86_jidian_pinyin g weixin qukuailian neijuan
```

（执行时如果 scratchpad 路径不同，换成当前会话的 scratchpad 目录。）

预期（候选顺序可能有小差别，以第一个候选为准）：

```
g	一 | …
weixin	微信 | …
qukuailian	区块链 | …
neijuan	内卷 | …
```

如果 `select_schema` 失败或候选为空：先确认 `$T/rime/build/wubi86_jidian_pinyin.schema.yaml` 存在；再检查函数表下标是否和 `verified-facts.md` 第 8 节一致。

- [ ] **Step 6: 提交（需用户已同意）**

```bash
git add .gitignore tools/vm/rime-type-probe.c tools/vm/build-probes.sh
git commit -m "tools: 加打字检查工具 rime-type-probe"
```

---

### Task 2: 文本替换检查应用 `TRProbe.app`

**Files:**
- Create: `tools/vm/tr-probe.swift`
- Modify: `tools/vm/build-probes.sh`（末尾追加 TRProbe.app 的编译）

**Interfaces:**
- Produces: `tools/vm/TRProbe.app`（本机临时签名，不开沙盒，不显示 Dock 图标）。用 `open -W` 启动后，把结果写进 `/tmp/tr-probe-result.txt`，每行 `键=值`，键只有 `path_exists`、`readable`、`open_rc`、`prepare_rc`、`step_rc`、`count`、`error`。**不输出任何文本替换内容。**

- [ ] **Step 1: 写 `tools/vm/tr-probe.swift`**

```swift
// 测试工具：验证独立的 .app 能不能读 macOS「文本替换」数据库。
// 只输出条数和错误信息，不输出任何内容。结果写到 /tmp/tr-probe-result.txt。
import Foundation
import SQLite3

let path = NSHomeDirectory() + "/Library/KeyboardServices/TextReplacements.db"
var lines: [String] = []
lines.append("path_exists=\(FileManager.default.fileExists(atPath: path))")
lines.append("readable=\(FileManager.default.isReadableFile(atPath: path))")

var db: OpaquePointer?
let openRC = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
lines.append("open_rc=\(openRC)")
if openRC == SQLITE_OK {
    var stmt: OpaquePointer?
    let sql = "SELECT count(*) FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0 OR ZWASDELETED IS NULL"
    let prepareRC = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    lines.append("prepare_rc=\(prepareRC)")
    if prepareRC == SQLITE_OK {
        let stepRC = sqlite3_step(stmt)
        lines.append("step_rc=\(stepRC)")
        if stepRC == SQLITE_ROW { lines.append("count=\(sqlite3_column_int(stmt, 0))") }
    } else {
        lines.append("error=\(String(cString: sqlite3_errmsg(db)))")
    }
    sqlite3_finalize(stmt)
} else if let db {
    lines.append("error=\(String(cString: sqlite3_errmsg(db)))")
}
sqlite3_close(db)

let result = lines.joined(separator: "\n") + "\n"
try? result.write(toFile: "/tmp/tr-probe-result.txt", atomically: true, encoding: .utf8)
```

- [ ] **Step 2: 在 `tools/vm/build-probes.sh` 末尾追加**

```bash

APP=TRProbe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O tr-probe.swift -o "$APP/Contents/MacOS/TRProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.squirrel-macos.tr-probe</string>
  <key>CFBundleName</key><string>TRProbe</string>
  <key>CFBundleExecutable</key><string>TRProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force -s - "$APP"
echo "已编译 tools/vm/$APP"
```

运行：`./tools/vm/build-probes.sh`
预期：两行「已编译」，`codesign` 没有报错。

- [ ] **Step 3: 在宿主机上跑一次（只读，只看条数），并检查输出没有内容（Review Focus 2）**

```bash
rm -f /tmp/tr-probe-result.txt
open -W tools/vm/TRProbe.app
cat /tmp/tr-probe-result.txt
grep -v -E '^(path_exists|readable|open_rc|prepare_rc|step_rc|count|error)=' /tmp/tr-probe-result.txt && echo "有不该出现的行" || echo "输出只有允许的键"
```

预期：最后一行是 `输出只有允许的键`。把 `open_rc`、`count`（或 `error`）记下来，作为「宿主机上未授权的独立 app」的结果，在任务 3 创建的记录里填进去。如果系统弹出权限对话框，不要点允许，记下对话框的标题后点拒绝，再看结果。

- [ ] **Step 4: 提交（需用户已同意）**

```bash
git add tools/vm/tr-probe.swift tools/vm/build-probes.sh
git commit -m "tools: 加文本替换检查应用 TRProbe"
```

---

### Task 3: 建长期测试机 `squirrel-dev`

**Files:**
- Create: `docs/phase0-log.md`

**Interfaces:**
- Produces: 运行中的测试机 `squirrel-dev`，用户已在窗口里登录桌面；工作记录 `docs/phase0-log.md`。

- [ ] **Step 1: 建工作记录**

```markdown
# 阶段 0 验证记录

日期：（填执行日期）。环境：Tart 测试机 `squirrel-dev`（从 `macos-base` 克隆，macOS 27.0.1），宿主机 macOS 27.0.1。

| # | 验证项 | 结论 | 详情 |
|---|---|---|---|
| 1 | 系统设置键盘页链接 | | |
| 2 | 授权弹窗安装时 postinstall 拿到桌面用户 | | |
| 3 | 独立 .app 读文本替换数据库 | | |
| 4 | `ditto` 解压 GitHub zip | | |
| 5 | 鼠须管运行时 `rime_dict_manager` 导出/合并 | | |
| 6 | 雾凇全拼、小鹤双拼在鼠须管 1.1.2 上部署和打字 | | |

## 宿主机

- TRProbe（未授权的独立 app）：（任务 2 的结果）

## 过程
```

- [ ] **Step 2: 克隆并启动（带窗口）**

运行：`./tools/vm/vm.sh new squirrel-dev`
预期：最后输出 `squirrel-dev 已就绪：<IP>`。

- [ ] **Step 3: 请用户在 Tart 窗口里登录 `tester` 的桌面**

停下来，请用户操作，等用户说「登录好了」。

- [ ] **Step 4: 确认桌面会话可用**

运行：`./tools/vm/vm.sh ssh squirrel-dev 'sudo launchctl asuser $(id -u) sudo -u tester "/Volumes/My Shared Files/vm/tis-probe" current'`
预期：输出一行 `com.apple.keylayout.ABC …`（当前输入源）。如果报错，说明桌面还没登录好。

- [ ] **Step 5: 确认测试机里没有鼠须管、没有 Rime 目录**

运行：`./tools/vm/vm.sh ssh squirrel-dev 'ls "/Library/Input Methods"; ls -d ~/Library/Rime 2>&1'`
预期：没有 `Squirrel.app`；`~/Library/Rime` 不存在。

---

### Task 4: 验证 #2：用授权弹窗安装鼠须管

**Files:**
- Modify: `docs/phase0-log.md`

- [ ] **Step 1: 在测试机里下载安装包并校验签名**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'curl -fsSL -o /tmp/Squirrel-1.1.2.pkg https://github.com/rime/squirrel/releases/download/1.1.2/Squirrel-1.1.2.pkg && pkgutil --check-signature /tmp/Squirrel-1.1.2.pkg && spctl -a -vv -t install /tmp/Squirrel-1.1.2.pkg'
```

预期：签名信息里有 `Developer ID Installer: Yuncao Liu (28HU5A7B46)`；`spctl` 输出 `accepted` 和 `source=Notarized Developer ID`。

- [ ] **Step 2: 用 osascript 带管理员权限安装（模拟应用里的 NSAppleScript）**

先告诉用户：「测试机窗口里马上会弹出授权框，请输入 tester 的密码」。然后运行：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'sudo launchctl asuser $(id -u) sudo -u tester osascript -e "do shell script \"installer -pkg /tmp/Squirrel-1.1.2.pkg -target /\" with administrator privileges"; echo "exit=$?"'
```

预期：用户输入密码后，输出 `installer: The install was successful.` 一类的文字和 `exit=0`。

**后备步骤（Review Focus 3）**：如果授权框没有出现、命令立刻报错，或者返回 `-60007` 等错误：把输出原样记下来，然后请用户在测试机窗口里打开「终端」，手动运行：
`osascript -e 'do shell script "installer -pkg /tmp/Squirrel-1.1.2.pkg -target /" with administrator privileges'`
用来区分「这个方法不行」还是「只是 SSH 环境下不行」。

- [ ] **Step 3: 检查 postinstall 有没有作用到桌面用户**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'sudo launchctl asuser $(id -u) sudo -u tester "/Volumes/My Shared Files/vm/tis-probe" list squirrel; pgrep -lf Squirrel; grep -i -E "squirrel|postinstall" /var/log/install.log | tail -20'
```

预期（和 `install-test-log.md` 里用 `sudo installer` 的结果一致）：`im.rime.inputmethod.Squirrel.Hans` 的 enabled=true，本体 enabled=false。`install.log` 里 postinstall 的输出提到的用户是 `tester`，而不是 `root`。

- [ ] **Step 4: 把结果写进 `docs/phase0-log.md` 的第 2 行和「过程」一节**

结论写「能 / 不能 / 只在终端里能」，详情写 `tis-probe` 的输出和 `install.log` 的关键行。

---

### Task 5: 验证 #1：系统设置键盘页链接，并请用户添加输入法

**Files:**
- Modify: `docs/phase0-log.md`

- [ ] **Step 1: 打开链接**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'sudo launchctl asuser $(id -u) sudo -u tester open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"; echo "exit=$?"'
```

请用户看测试机窗口：系统设置有没有打开？停在哪一页（键盘页，还是别的页）？

- [ ] **Step 2: 如果没停在键盘页，再试一个备选链接**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'sudo launchctl asuser $(id -u) sudo -u tester open "x-apple.systempreferences:com.apple.preference.keyboard"; echo "exit=$?"'
```

请用户描述结果。两个链接的结果都记下来。

- [ ] **Step 3: 请用户手动添加鼠须管**

请用户在键盘页操作：「文字输入 → 输入法 → 编辑… → + → 简体中文 → 鼠须管 → 添加」，完成后告诉我。

- [ ] **Step 4: 确认本体已启用，并切换过去**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'P="/Volumes/My Shared Files/vm/tis-probe"; sudo launchctl asuser $(id -u) sudo -u tester "$P" list squirrel; sudo launchctl asuser $(id -u) sudo -u tester "$P" select "=im.rime.inputmethod.Squirrel.Hans"; sleep 3; pgrep -lf Squirrel; ls -d ~/Library/Rime'
```

预期：本体 enabled=true；`select` 返回 OSStatus 0；鼠须管进程在运行；`~/Library/Rime` 已生成。

- [ ] **Step 5: 把结果写进 `docs/phase0-log.md` 的第 1 行**

---

### Task 6: 验证 #4：下载、用 `ditto` 解压，并记录上游目录结构

**Files:**
- Modify: `docs/phase0-log.md`
- Create: `docs/upstream-layouts.md`

**Interfaces:**
- Produces: 测试机里 `/tmp/up/` 下解压好的三个包（`jidian/`、`full/`、`cn_dicts/`），任务 7 使用；`docs/upstream-layouts.md` 供阶段 1 写 `catalog.json`。

- [ ] **Step 1: 在测试机里下载三个包**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/up && mkdir -p /tmp/up && cd /tmp/up && curl -fsSL -o jidian.zip https://codeload.github.com/KyleBing/rime-wubi86-jidian/zip/refs/heads/master && curl -fsSL -o full.zip https://github.com/iDvel/rime-ice/releases/download/nightly/full.zip && curl -fsSL -o cn_dicts.zip https://github.com/iDvel/rime-ice/releases/download/nightly/cn_dicts.zip && ls -l'
```

预期：三个 zip，`full.zip` 约 16 MB，`cn_dicts.zip` 约 14.7 MB。

- [ ] **Step 2: 用 `ditto` 解压**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'cd /tmp/up && for n in jidian full cn_dicts; do /usr/bin/ditto -x -k $n.zip $n; echo "$n exit=$?"; done'
```

预期：三行 `exit=0`。

- [ ] **Step 3: 记录目录结构（用 find 定位，不写死路径，Review Focus 4）**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'cd /tmp/up && for n in jidian full cn_dicts; do echo "== $n"; find $n -maxdepth 3 | sort | head -80; echo "files: $(find $n -type f | wc -l)"; done; echo "== 关键文件"; find /tmp/up -name "wubi86_jidian.schema.yaml" -o -name "rime_ice.schema.yaml" -o -name "double_pinyin_flypy.schema.yaml" -o -name "8105.dict.yaml" -o -name "default.yaml" -o -name "*.custom.yaml" | sort' > /private/tmp/claude-501/-Users-kbys-workspace-vibe-coding-squirrel-macos/d2009d83-5a93-4c0a-aade-270800c3ef24/scratchpad/upstream-layouts.txt
```

（scratchpad 路径按当前会话调整。）

- [ ] **Step 4: 整理成 `docs/upstream-layouts.md`**

按包写：下载地址、顶层目录名（例如 `rime-wubi86-jidian-master/`）、方案文件在哪、词库在哪、有没有 Lua（`lua/`）和 OpenCC（`opencc/`）目录、有哪些上游自带的 `*.custom.yaml`、文件总数。只写结构，不复制文件内容。

- [ ] **Step 5: 把结果写进 `docs/phase0-log.md` 的第 4 行**

---

### Task 7: 验证 #6：雾凇全拼、小鹤双拼在鼠须管 1.1.2 上部署和打字

**Files:**
- Modify: `docs/phase0-log.md`

- [ ] **Step 1: 把雾凇完整方案放进测试机的 Rime 目录，只启用两个方案**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'SRC=$(dirname "$(find /tmp/up/full -name rime_ice.schema.yaml | head -1)"); echo "SRC=$SRC"; rsync -a "$SRC"/ ~/Library/Rime/ && printf "patch:\n  schema_list:\n    - schema: rime_ice\n    - schema: double_pinyin_flypy\n" > ~/Library/Rime/default.custom.yaml && ls ~/Library/Rime | head -40'
```

预期：`SRC` 指向解压后包含 `rime_ice.schema.yaml` 的目录；Rime 目录里出现 `rime_ice.schema.yaml`、`lua/`、`opencc/`、`cn_dicts/` 等。

- [ ] **Step 2: 通知鼠须管重新部署，等它完成**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'sudo launchctl asuser $(id -u) sudo -u tester "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload; for i in $(seq 1 60); do ls ~/Library/Rime/build/rime_ice.prism.bin ~/Library/Rime/build/double_pinyin_flypy.prism.bin >/dev/null 2>&1 && break; sleep 2; done; echo "waited ${i}x2s"; ls -la ~/Library/Rime/build | grep -E "rime_ice|flypy"'
```

预期：两个方案的 `.prism.bin` 和 `rime_ice.table.bin` 都已生成。记下大概用了多久。

- [ ] **Step 3: 看日志里有没有错误**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'L="$(getconf DARWIN_USER_TEMP_DIR)rime.squirrel"; ls -la "$L"; for f in "$L"/*ERROR*; do [ -e "$f" ] && { echo "== $f"; tail -30 "$f"; }; done; grep -h -i -E "lua|opencc|finished updating" "$L"/*INFO* | tail -20'
```

预期：没有 ERROR 日志，或者 ERROR 里没有和 `rime_ice`、`double_pinyin_flypy`、Lua、OpenCC 相关的内容。

- [ ] **Step 4: 在配置副本上用打字检查工具测**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rimecopy && rsync -a --exclude "*.userdb" ~/Library/Rime/ /tmp/rimecopy/ && P="/Volumes/My Shared Files/vm/rime-type-probe"; "$P" /tmp/rimecopy rime_ice nihao rq sj xiaolian; "$P" /tmp/rimecopy double_pinyin_flypy nihk'
```

预期：
- `nihao` → 第一个候选 `你好`
- `double_pinyin_flypy` 的 `nihk` → 第一个候选 `你好`
- `rq` / `sj`（雾凇用 Lua 输出日期和时间）：如果候选里有今天的日期、现在的时间，说明这个工具加载了 Lua 插件；如果没有，**不代表鼠须管里不行**，以下一步的手动打字为准。把结果记下来，这决定阶段 2 的打字检查能不能测 Lua。
- `xiaolian`：候选里有没有 emoji（OpenCC），记下来。

- [ ] **Step 5: 请用户在测试机里实际打字**

请用户在测试机里打开「文本编辑」，确认当前是鼠须管，依次打：`nihao`、`rq`、`sj`、`xiaolian`；再按 `Control + `` ` `` 切到小鹤双拼，打 `nihk`。请用户告诉我每个的第一个候选，以及 `rq`、`sj` 有没有出日期和时间。

预期：全部正常，日期和时间都有（说明 Lua 在鼠须管里能用）。

- [ ] **Step 6: 把结果写进 `docs/phase0-log.md` 的第 6 行**

---

### Task 8: 验证 #5：鼠须管运行时用 `rime_dict_manager` 导出、合并输入习惯

**Files:**
- Modify: `docs/phase0-log.md`

已知（宿主机实测）：`rime_dict_manager` 把**当前目录**当作用户目录，支持 `--list`、`--sync`、`--backup <词典名>`、`--restore <xxx.userdb.txt>`、`--export <词典名> <文件>`、`--import <词典名> <文件>`。

- [ ] **Step 1: 请用户打几个词，生成输入习惯数据**

请用户在「文本编辑」里用雾凇全拼打几个词，并故意选第二、第三个候选（例如 `shi` 选第三个、`zhongguo` 选第一个、`ceshi` 选第二个），各打两三次。完成后告诉我。

- [ ] **Step 2: 先备份测试机里的输入习惯数据库（Review Focus 5）**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/userdb-backup && mkdir -p /tmp/userdb-backup && cp -R ~/Library/Rime/*.userdb /tmp/userdb-backup/ && ls /tmp/userdb-backup'
```

预期：至少有 `rime_ice.userdb`。

- [ ] **Step 3: 鼠须管运行中，试 list、export、backup**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'M="/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_dict_manager"; pgrep -lf Squirrel; cd ~/Library/Rime && "$M" --list; echo "list exit=$?"; "$M" --export rime_ice /tmp/s1.txt; echo "export exit=$?"; wc -l /tmp/s1.txt; "$M" --backup rime_ice; echo "backup exit=$?"; find ~/Library/Rime/sync -name "*.userdb.txt" 2>/dev/null'
```

预期：记下每条命令的输出和退出码。重点看有没有 `lock`、`IO error`、`Resource temporarily unavailable` 一类的错误（LevelDB 被鼠须管锁住）。

- [ ] **Step 4: 再打一个新词，导出 s2，然后把 s1 导回去，看会不会丢**

请用户再打一个之前没打过的词（例如 `xinci` 选第二个候选）。然后：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'M="/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_dict_manager"; cd ~/Library/Rime && "$M" --export rime_ice /tmp/s2.txt; "$M" --import rime_ice /tmp/s1.txt; echo "import exit=$?"; "$M" --export rime_ice /tmp/s3.txt; cut -f1,2 /tmp/s2.txt | sort -u > /tmp/k2; cut -f1,2 /tmp/s3.txt | sort -u > /tmp/k3; echo "s2 里有、s3 里没有的条数: $(comm -23 /tmp/k2 /tmp/k3 | wc -l)"; wc -l /tmp/s1.txt /tmp/s2.txt /tmp/s3.txt'
```

预期：如果导入是「合并」，`s2 里有、s3 里没有的条数` 是 0。

- [ ] **Step 5: 如果第 3、4 步在鼠须管运行时失败，退出鼠须管后重试**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'killall Squirrel; sleep 1; M="/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_dict_manager"; cd ~/Library/Rime && "$M" --export rime_ice /tmp/s1b.txt; echo "export exit=$?"; "$M" --import rime_ice /tmp/s1b.txt; echo "import exit=$?"; sudo launchctl asuser $(id -u) sudo -u tester open "/Library/Input Methods/Squirrel.app"; sleep 3; pgrep -lf Squirrel'
```

预期：退出后能成功；鼠须管重新启动。再请用户打一个词，确认输入法正常、之前选过的候选顺序还在。

- [ ] **Step 6: 把结果写进 `docs/phase0-log.md` 的第 5 行**

结论要回答三件事：运行时能不能导出；运行时能不能导入；导入是合并还是覆盖。再写下建议的做法：用 `--export/--import`，还是用 `--backup/--restore`，以及导入时要不要先退出鼠须管。

---

### Task 9: 验证 #3：测试机里独立 .app 读文本替换数据库

**Files:**
- Modify: `docs/phase0-log.md`

- [ ] **Step 1: 请用户在测试机里加一条文本替换**

请用户在测试机的「系统设置 → 键盘 → 文本替换… → +」里加一条：输入 `tstx`，替换为 `测试短语`。完成后告诉我。（这样数据库一定存在，而且至少有 1 条。）

- [ ] **Step 2: 把 TRProbe.app 复制到测试机的「应用程序」里，再启动**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'mkdir -p ~/Applications && rm -rf ~/Applications/TRProbe.app && ditto "/Volumes/My Shared Files/vm/TRProbe.app" ~/Applications/TRProbe.app && rm -f /tmp/tr-probe-result.txt && sudo launchctl asuser $(id -u) sudo -u tester open -W ~/Applications/TRProbe.app; cat /tmp/tr-probe-result.txt'
```

同时请用户看测试机窗口里有没有弹出权限对话框。如果有：先把标题记下来，**点「不允许」**，看结果；然后再跑一次，这次点「允许」，再看结果。

预期：理想结果是 `open_rc=0`、`count=` 至少 1，而且没有弹窗。

- [ ] **Step 3: 对照：用系统自带的 sqlite3 读（SSH 环境和桌面会话各一次）**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'DB=~/Library/KeyboardServices/TextReplacements.db; Q="SELECT count(*) FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0 OR ZWASDELETED IS NULL;"; echo "ssh: $(sqlite3 -readonly "$DB" "$Q" 2>&1)"; echo "gui: $(sudo launchctl asuser $(id -u) sudo -u tester sqlite3 -readonly "$DB" "$Q" 2>&1)"'
```

预期：记下两个结果。

- [ ] **Step 4: 把结果写进 `docs/phase0-log.md` 的第 3 行**

结论要回答：独立 .app 不授权能不能读？要不要授权、授权哪一项（例如「完全磁盘访问权限」）？宿主机（任务 2）和测试机的结果一样吗？

---

### Task 10: 整理结论、更新文档

**Files:**
- Modify: `docs/verified-facts.md`
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（只在结论和设计冲突时）
- Modify: `CLAUDE.md`
- Modify: `docs/phase0-log.md`

- [ ] **Step 1: 更新 `verified-facts.md`**

- 第 2 节「打开系统设置键盘页的链接」：把「待验证」改成实测结论，写上能用的那个链接。
- 第 5 节「独立的 .app 能不能读这个数据库」：改成实测结论（宿主机、测试机分别写）。
- 第 7 节：写上 `ditto` 解压的结论，链接到 `upstream-layouts.md`。
- 新增一节「`rime_dict_manager`」：用法（以当前目录为用户目录）、各命令在鼠须管运行时和退出后的行为、导入是合并还是覆盖。
- 新增：用授权弹窗（`osascript … with administrator privileges`）安装时，postinstall 的结果。
- 新增：雾凇全拼、小鹤双拼在 1.1.2 上的部署耗时、打字结果、Lua 和 OpenCC 能不能用；`rime-type-probe` 能不能加载 Lua 插件。
- 每条都标「实测（squirrel-dev，日期）」。

- [ ] **Step 2: 对照设计第 10 节逐项检查**

哪一项结论和设计的假设不一样，就在设计文档里改对应的段落（例如：导入输入习惯必须先退出鼠须管、文本替换需要用户授权某一项），并在第 10 节那一行写上「已验证，见 verified-facts」。全部符合的话，只更新第 10 节的状态。

- [ ] **Step 3: 更新 `CLAUDE.md` 的「测试虚拟机」一节**

加一行：长期测试机 `squirrel-dev`（已装鼠须管 1.1.2、已添加输入法、有雾凇配置），日常开发用；测从零安装、导入时再克隆干净的。

- [ ] **Step 4: 向用户汇报**

用一张表列出 6 项结论，标出哪些改动了设计。问用户：设计改动是否认可，是否可以开始写阶段 1 的计划。

- [ ] **Step 5: 提交（需用户已同意）**

```bash
git add docs/ CLAUDE.md
git commit -m "docs: 阶段 0 待验证项的结论"
```

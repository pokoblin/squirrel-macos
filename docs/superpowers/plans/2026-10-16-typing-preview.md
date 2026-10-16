# 试打预览 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 应用里加「试打」页：选来源（当前生效 / 应用后的样子）和方案，输入编码直接看候选、翻页、选词上屏，不用切换输入法。

**Architecture:**
- 新的辅助程序 `rime-preview-helper`（只有它带 `disable-library-validation`）加载鼠须管的 librime，在副本目录上开会话，stdin/stdout 一行一个 JSON。
- RimeKit 准备副本（`PreviewWorkspace`）、和辅助程序对话（`PreviewSession`，实现 `PreviewEngine` 协议）、找词（`PreviewProbe`，留给子项目 3）。
- AppCore 的 `PreviewModel` 放界面逻辑，AppUI 的 `PreviewPage` 只管显示和按键；`rimectl preview` 用同一套。

**Tech Stack:** Swift 6.4、Swift Testing、SwiftUI（`onKeyPress`）、C 头文件模块、`dlopen`、Yams（读编译后的 YAML）、bash、codesign。

**执行方式：** Subagent-driven（用户 2026-10-16 选定）。

**Spec:** [docs/superpowers/specs/2026-10-16-typing-preview-design.md](../specs/2026-10-16-typing-preview-design.md)（下面写成「设计 x.y」）。实测依据：[verified-facts.md](../../verified-facts.md) 第 8 节和 8.1 节。

## 计划里定下的细节（设计没写死的地方）

| # | 问题 | 计划里的做法 |
|---|---|---|
| 1 | 「真实目录」判断在辅助程序里怎么实现 | 设计 3.2 说单独实现一份。计划改成**只有一份**：把 `RimeDirectoryGuard` 挪进新的小 target `RimeGuard`（只依赖 Foundation），RimeKit 用 `@_exported import RimeGuard`，现有代码和测试不用改；辅助程序也依赖它。比两份实现、两套测试更不容易出错 |
| 2 | Lua 脚本里的 `print` 会写到 stdout，把协议搞乱 | 辅助程序启动时先 `dup` 一份 stdout 留给协议，再把 fd 1 指向 stderr（`dup2(2, 1)`），librime 和插件往 stdout 写的东西都进 stderr |
| 3 | librime 加载失败以后辅助程序怎么办 | 不退出；之后每个请求都回 `loadFailed`（带 `dlerror()` 原文），直到 stdin 关闭。调用方不用区分「启动就退出」和「请求失败」 |
| 4 | 测试怎么找到辅助程序 | 测试 target 依赖 `rime-preview-helper`，`swift test` 会把它编出来；测试里按 `#filePath` 找仓库根目录下的 `.build/debug/rime-preview-helper` |
| 5 | 集成测试用什么配置 | 用 `GenFixtures` 生成 `py`、`wb` 两个方案并编译（和 `GeneratedConfigCompileTests` 一样），在 `py` 词库里加 12 个编码 `yi` 的单字（`page_size` 是 5）测翻页：一 衣 医 依 伊 壹 揖 仪 夷 宜 移 遗，权重从 120 起每个减 10，所以第 7 个「揖」在第 2 页第 2 个 |
| 6 | 「当前生效」变了怎么知道 | `MainModel` 在应用改动、还原、导入成功以后调 `preview.markCurrentChanged()`；不去盯文件 |
| 7 | 「应用后的样子」没有改动了怎么办 | 点「重新载入」时如果已经没有未应用的改动，自动切回「当前生效」 |
| 8 | `check-dmg.sh` 只在公证后运行 | 新增 `tools/release/check-entitlements.sh <应用>`，`build-release.sh` 在签名后立刻跑（不公证也跑），`check-dmg.sh` 对挂载出来的应用也跑一次 |

## Global Constraints

- 宿主机不运行应用，不碰 `~/Library/Rime`、`/Library/Input Methods`、输入法状态。librime 只在副本上跑；单元测试、集成测试只用临时目录。
- librime 路径：`/Library/Input Methods/Squirrel.app/Contents/Frameworks/librime.1.dylib`；共享目录 `…/Contents/SharedSupport`。
- 函数表下标（verified-facts 8、8.1）：setup 0、initialize 2、finalize 3、create_session 13、process_key 18、clear_composition 20、get_commit 21、free_commit 22、get_context 23、free_context 24、get_current_schema 33、select_schema 34、get_version 72、select_candidate_on_current_page 74。只用这些。
- 版本检查（设计 3.2）：`get_version` 主版本 1、次版本 ≥ 16，并且 `data_size` 至少覆盖到下标 74；否则 `unsupportedVersion`。
- 特殊键码（设计 3.3）：backspace `0xff08`、escape `0xff1b`、return `0xff0d`、pageUp `0xff55`、pageDown `0xff56`、up `0xff52`、down `0xff54`。`input` 只收 `0x20`–`0x7e`。
- 超时（设计 3.5）：`open` 15 秒，其他请求 5 秒。
- 「当前生效」副本带 `build/`，不带 `*.userdb/`、`*.userdb.txt`、`sync/`、`user.yaml`、`installation.yaml`、`.git/`（设计 3.4）。
- 「应用后的样子」只用本地缓存的方案包，不联网（设计 3.4）。
- 副本放 `staging/preview-<UUID>/`，用完删掉；不拿应用锁。
- `traits`：`app_name` = `rime.squirrel-helper-preview`，`distribution_name` = `SquirrelHelper`，`log_dir` = 副本目录，`min_log_level` = 3。
- 界面文字用设计第 5 节的原话；简单直白的中文。
- 每个任务：先写测试看它失败，再实现，再跑 `swift test`（全部通过）。视图层没有单元测试，用 `swift build` 编译通过，测试机里检查。
- 提交：按任务提交，提交信息结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；推送 `main` 在全部任务做完、测试机检查过以后。
- 测试机：用长期的 `squirrel-dev`；登录桌面、在界面上操作由用户来做。

## Review Focus

1. **Lua 脚本往 stdout 打印**（用户自己的 `rime.lua` 里有 `print`）：协议不能乱，照常出候选——任务 2 有测试（副本里放一个顶层 `print` 的 `rime.lua`）。
2. **复制时鼠须管正在部署**，副本里缺某个方案的编译结果：报 `schemaMissing`，不是空白——任务 2（辅助程序）、任务 4（方案列表过滤）有测试。
3. **输入框里打了非 ASCII 字符**（系统里另一个中文输入法处于激活状态、Option 组合出来的符号、emoji）：应用里忽略，辅助程序回 `badRequest`，不崩——任务 2、任务 7 有测试。
4. **辅助程序卡住**（很慢的 Lua、死循环）：5 秒后杀掉，页面显示「试打出错了」，点「重试」能重新开始——任务 3、任务 7 有测试。
5. **编译「应用后的样子」时离开页面**（约 10 秒）：结果丢掉、副本删掉、不留下辅助程序——任务 7 有测试。

---

## 文件结构

| 文件 | 做什么 | 任务 |
|---|---|---|
| `Package.swift` | 加 `RimeGuard`、`RimePreviewProtocol`、`CRimeAPI`、`rime-preview-helper` | 1、2 |
| `Sources/RimeGuard/RimeDirectoryGuard.swift`（从 RimeKit 挪过来） | 判断是不是真实的 `~/Library/Rime` | 1 |
| `Sources/RimeKit/RimeKit.swift` | `@_exported import RimeGuard`、`@_exported import RimePreviewProtocol` | 1 |
| `Sources/RimePreviewProtocol/PreviewProtocol.swift`（新） | 请求、结果、键名、一行 JSON 编解码 | 1 |
| `Sources/CRimeAPI/include/rime_api_prefix.h`、`shim.c`（新） | librime 结构体和函数表前缀 | 2 |
| `Sources/rime-preview-helper/main.swift`、`RimeEngine.swift`（新） | 辅助程序：读请求循环；加载、调用 librime | 2 |
| `Sources/RimeKit/Preview/PreviewSession.swift`（新） | `PreviewEngine` 协议、`PreviewSession`、`PreviewError`、找辅助程序 | 3 |
| `Sources/RimeKit/Preview/PreviewWorkspace.swift`（新） | 准备副本、方案列表 | 4 |
| `Sources/RimeKit/Deploy/FullConfig.swift`（新）、`Deployer.swift` | 抽出「拼完整目录」 | 4 |
| `Sources/RimeKit/Preview/PreviewProbe.swift`（新） | 找某个词在第几页第几个 | 5 |
| `Sources/rimectl/Rimectl.swift`、`Sources/rimectl/Preview.swift`（新） | `rimectl preview` | 6 |
| `Sources/AppCore/PreviewModel.swift`、`PreviewProblem.swift`（新）、`AppEnvironment.swift`、`MainModel.swift`、`MainModel+Actions.swift` | 试打页的逻辑、出错说明、接进主窗口 | 7 |
| `Sources/AppUI/PreviewPage.swift`（新）、`MainView.swift` | 试打页 | 8 |
| `tools/app/build-app.sh`、`tools/app/preview-helper.entitlements`（新）、`tools/release/check-entitlements.sh`（新）、`build-release.sh`、`check-dmg.sh` | 打包、签名、检查 | 9 |
| `Tests/RimeKitTests/Support/PreviewFixtures.swift`（新） | 编译好的测试配置、找辅助程序、假辅助程序脚本 | 2、3 |
| `docs/verified-facts.md`、`docs/typing-preview-vm-log.md`（新）、`docs/release.md`、路线图、`CLAUDE.md` | 测试机结论和说明 | 10 |

---

### Task 1: 共用的底层：`RimeGuard` 和 `RimePreviewProtocol`

**Files:**
- Create: `Sources/RimeGuard/RimeDirectoryGuard.swift`（`git mv` 自 `Sources/RimeKit/Config/RimeDirectoryGuard.swift`，内容不变）
- Create: `Sources/RimePreviewProtocol/PreviewProtocol.swift`
- Modify: `Package.swift`、`Sources/RimeKit/RimeKit.swift`
- Test: `Tests/RimeKitTests/PreviewProtocolTests.swift`（新）；现有 `RimeDirectoryGuardTests` 不改、照常通过

**Interfaces:**
- Produces（`RimePreviewProtocol`，全部 `public`、`Sendable`、`Equatable`）：
  - `enum PreviewKey: String, Codable, CaseIterable { case backspace, escape, `return`, pageUp, pageDown, up, down }`，`var keysym: Int32`（值见 Global Constraints）
  - `enum PreviewRequest: Codable { case open(userDir: String, schema: String), input(String), key(PreviewKey), select(Int), clear }`——编码成 `{"op":"open","userDir":…,"schema":…}`、`{"op":"input","text":…}`、`{"op":"key","name":…}`、`{"op":"select","index":…}`、`{"op":"clear"}`
  - `struct PreviewCandidate: Codable { var text: String; var comment: String }`
  - `struct PreviewState: Codable { var committed: String?; var preedit: String; var cursor: Int; var candidates: [PreviewCandidate]; var labels: [String]?; var pageNo: Int; var isLastPage: Bool; var highlighted: Int }`，`static let empty`
  - `enum PreviewFailureKind: String, Codable { case loadFailed, unsupportedVersion, refusedDirectory, schemaMissing, notOpen, badRequest }`
  - `struct PreviewFailure: Codable { var kind: PreviewFailureKind; var message: String }`
  - `struct PreviewResponse: Codable { var ok: Bool; var librimeVersion: String?; var state: PreviewState?; var error: PreviewFailure? }`，`static func success(_ state: PreviewState, librimeVersion: String? = nil)`、`static func failure(_ kind: PreviewFailureKind, _ message: String)`
  - `enum PreviewLine { static func encode<T: Encodable>(_ value: T) throws -> Data` /* 一行 JSON，结尾 `\n`，不转义 `/` */ `; static func decode<T: Decodable>(_ type: T.Type, from line: some StringProtocol) throws -> T }`
- Produces（`RimeGuard`）：`RimeDirectoryGuard`，接口和现在一样。

- [ ] **Step 1: 改 `Package.swift`**：加 `.target(name: "RimeGuard")`、`.target(name: "RimePreviewProtocol")`；RimeKit 的依赖加这两个。`git mv` guard 文件；`RimeKit.swift` 加两行 `@_exported import`。
- [ ] **Step 2: 跑 `swift test --filter RimeDirectoryGuardTests`**，Expected：PASS（纯挪动）。
- [ ] **Step 3: 写失败的测试** `PreviewProtocolTests`：

```swift
@Test func 请求编码成一行带op的JSON() throws {
    let line = String(decoding: try PreviewLine.encode(PreviewRequest.open(userDir: "/tmp/a", schema: "py")), as: UTF8.self)
    #expect(line.hasSuffix("\n") && !line.dropLast().contains("\n"))
    let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    #expect(obj["op"] as? String == "open" && obj["userDir"] as? String == "/tmp/a" && obj["schema"] as? String == "py")
}
@Test(arguments: [PreviewRequest.open(userDir: "/x", schema: "s"), .input("nihao"), .key(.pageDown), .select(2), .clear])
func 请求往返不变(_ r: PreviewRequest) throws {
    #expect(try PreviewLine.decode(PreviewRequest.self, from: String(decoding: PreviewLine.encode(r), as: UTF8.self)) == r)
}
@Test func 键码() { #expect(PreviewKey.backspace.keysym == 0xff08); #expect(PreviewKey.pageDown.keysym == 0xff56); #expect(PreviewKey.return.keysym == 0xff0d) }
@Test func 不认识的op解码失败() { #expect(throws: (any Error).self) { try PreviewLine.decode(PreviewRequest.self, from: #"{"op":"jump"}"#) } }
@Test func 设计里的结果例子能解码() throws {
    let r = try PreviewLine.decode(PreviewResponse.self, from: #"{"ok":true,"librimeVersion":"1.16.0","state":{"committed":"你好","preedit":"ni hao","cursor":6,"candidates":[{"text":"你好","comment":""}],"labels":null,"pageNo":0,"isLastPage":false,"highlighted":0}}"#)
    #expect(r.state?.committed == "你好" && r.state?.candidates.first?.text == "你好" && r.librimeVersion == "1.16.0")
}
@Test func 出错结果() throws {
    let r = try PreviewLine.decode(PreviewResponse.self, from: String(decoding: PreviewLine.encode(PreviewResponse.failure(.schemaMissing, "没有 xx")), as: UTF8.self))
    #expect(!r.ok && r.error == PreviewFailure(kind: .schemaMissing, message: "没有 xx"))
}
```

- [ ] **Step 4: 跑 `swift test --filter PreviewProtocolTests`**，Expected：编译失败（类型不存在）。
- [ ] **Step 5: 实现 `PreviewProtocol.swift`**（`PreviewRequest` 手写 `Codable`，按 `op` 分支）。
- [ ] **Step 6: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 7: 提交** `refactor: RimeDirectoryGuard 挪进 RimeGuard；试打预览的通信协议`

---

### Task 2: 辅助程序 `rime-preview-helper`

**Files:**
- Create: `Sources/CRimeAPI/include/rime_api_prefix.h`、`Sources/CRimeAPI/shim.c`（空文件，SwiftPM 的 C target 要有源文件）
- Create: `Sources/rime-preview-helper/main.swift`、`Sources/rime-preview-helper/RimeEngine.swift`
- Modify: `Package.swift`（`.target(name: "CRimeAPI")`、`.executableTarget(name: "rime-preview-helper", dependencies: ["CRimeAPI", "RimeGuard", "RimePreviewProtocol"])`、`.executable(name: "rime-preview-helper", …)` 产品；测试 target 依赖加 `"rime-preview-helper"`）
- Create: `Tests/RimeKitTests/Support/PreviewFixtures.swift`
- Test: `Tests/RimeKitTests/PreviewHelperTests.swift`（`@Suite(.enabled(if: RimeTools.installed))`）

**Interfaces:**
- Consumes: Task 1 的全部类型；`RimeDirectoryGuard.isInsideRealRimeDirectory(_:)`
- Produces:
  - `rime_api_prefix.h`：`RimeTraits`、`RimeComposition`、`RimeCandidate`、`RimeMenu`、`RimeCommit`、`RimeContext`（字段同 `tools/vm/rime-type-probe.c`），`RimeApiPrefix`：`int data_size` 后面是函数指针，下标 0–74，用到的十四个有类型和名字，其余用 `void *unused_a_b[n]` 占位（下标见 Global Constraints；33 是 `Bool (*get_current_schema)(RimeSessionId, char *, size_t)`，72 是 `const char *(*get_version)(void)`，74 是 `Bool (*select_candidate_on_current_page)(RimeSessionId, size_t)`）
  - 命令行：`rime-preview-helper [--squirrel <Squirrel.app>]`，默认 `/Library/Input Methods/Squirrel.app`
  - 测试支持（`PreviewFixtures`）：`static var helper: URL`（仓库根 `.build/debug/rime-preview-helper`）；`static func compiledConfig(in dir: URL) throws -> URL`（细节 5：`GenFixtures` 生成 `Settings(schemas: ["py", "wb"])`，`makePackages(extra: ["pinyin": ["py.dict.yaml": …原有三行 + 细节 5 的 12 个字…]])`，`RimeTools.build`，返回目录）；`final class HelperProcess`（同步小客户端：`init(helper:arguments:)`、`func send(_ r: PreviewRequest) throws -> PreviewResponse`、`func sendRaw(_ line: String) throws -> PreviewResponse`、`func closeInput() -> Int32`（返回退出码））

- [ ] **Step 1: 写失败的测试** `PreviewHelperTests`（每个测试先 `compiledConfig` 到 `TempDir`）：

```swift
@Test func 出候选() throws {           // open py，input "nihao"
    #expect(open.ok && open.librimeVersion?.hasPrefix("1.") == true)
    #expect(r.state?.candidates.first?.text == "你好" && r.state?.preedit.isEmpty == false)
}
@Test func 翻页和本页选词() throws {    // input "yi" → key pageDown → pageNo == 1；key pageUp → pageNo == 0；select 1 → committed == 本页第 2 个候选的 text，candidates 为空
}
@Test func 特殊键() throws {            // input "nih" + backspace → preedit 变短；escape → preedit 为空、candidates 为空
    // return：input "ni" + return → committed == "ni"（Rime 回车上屏原编码）；up/down：input "yi" + down → highlighted == 1，再 up → 0
}
@Test func 空格上屏() throws {            // open wb，input "g" 再 input " " → committed == "一"，candidates 为空
}
@Test func 方案不存在() throws {          // open "nope" → error.kind == .schemaMissing
    // 删掉 build/py.schema.yaml 再 open py → .schemaMissing（Review Focus 2）
}
@Test func 换方案换目录() throws {        // open py → open wb（同目录）→ input "g" 有「一」；复制一份目录，open 新目录的 py → "nihao" 照样出「你好」
}
@Test func 拒绝真实目录() throws {        // open userDir = NSHomeDirectory()+"/Library/Rime" → .refusedDirectory（不论目录存不存在都不加载）
}
@Test func 先open() throws { /* input "a" → .notOpen */ }
@Test func 非ASCII是坏请求() throws {     // input "你" → .badRequest；sendRaw("not json") → .badRequest；之后 input "nihao" 照常（Review Focus 3）
}
@Test func Lua打印不搞乱协议() throws {   // 副本里写 rime.lua：print("LUA-NOISE")；open py、input "nihao" 照常解码出「你好」（Review Focus 1）
}
@Test func 加载失败() throws {            // --squirrel 指向空临时目录 → open 回 .loadFailed，message 非空；closeInput() == 0
}
@Test func stdin关闭就退出() throws { /* open 后 closeInput() == 0 */ }
```

- [ ] **Step 2: 跑 `swift test --filter PreviewHelperTests`**，Expected：编译失败（辅助程序不存在）。
- [ ] **Step 3: 写 `rime_api_prefix.h`、`shim.c`**，`swift build --product rime-preview-helper` 能编出 `.build/debug/rime-preview-helper`（先放一个只回 `notOpen` 的 `main.swift` 占位）。
- [ ] **Step 4: 实现 `RimeEngine`**（`final class`，单线程用）：
  - `init(squirrelApp: URL)`：`dlopen(…/Contents/Frameworks/librime.1.dylib, RTLD_NOW)` + `dlsym("rime_get_api")`；失败记下 `loadError: String`。成功后做版本检查，不过就记下 `versionError`。
  - `func open(userDir: String, schema: String) -> PreviewResponse`：guard → 加载/版本错误 → 检查 `userDir/build/<schema>.schema.yaml` → 第一次 `setup`+`initialize`；目录变了 `finalize` 再 `initialize`（细节见设计 3.3）→ 没有会话就 `create_session` → `select_schema` → `get_current_schema` 必须等于 `schema` → `clear_composition` → 回状态（带 `librimeVersion`）。
  - `input`、`key`、`select`、`clear`：没 open 回 `.notOpen`；之后都调 `func snapshot() -> PreviewState`：**先** `get_commit` 再 `get_context`（`data_size` 按 `rime-type-probe.c` 的写法设置），`comment` 为空指针时用 `""`，`select_labels` 为空指针时 `labels = nil`，`menu.page_size` 个标签。
  - `func shutdown()`：初始化过就 `finalize`。
- [ ] **Step 5: 实现 `main.swift`**：先 `let protocolOut = dup(1); dup2(2, 1)`（细节 2）；解析 `--squirrel`；`while let line = readLine(strippingNewline: true)`：解码失败回 `.badRequest`，否则分派；结果用 `PreviewLine.encode` 写到 `protocolOut`；循环结束 `shutdown()`、`exit(0)`。
- [ ] **Step 6: 跑 `swift test --filter PreviewHelperTests`**，Expected：PASS。若 `return`/`up`/`down` 的结果和测试里的预期不同，按实测改断言，并把实测结果补进 verified-facts 8.1。
- [ ] **Step 7: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 8: 提交** `feat(preview): 辅助程序 rime-preview-helper，在副本上加载鼠须管的 librime`

---

### Task 3: `PreviewSession`：和辅助程序对话

**Files:**
- Create: `Sources/RimeKit/Preview/PreviewSession.swift`
- Modify: `Tests/RimeKitTests/Support/PreviewFixtures.swift`（加假辅助程序）
- Test: `Tests/RimeKitTests/PreviewSessionTests.swift`

**Interfaces:**
- Consumes: Task 1 的类型；Task 2 的辅助程序
- Produces（RimeKit，`public`）：
  - `protocol PreviewEngine: Sendable { func open(userDir: URL, schema: String) async throws -> PreviewOpened; func input(_ text: String) async throws -> PreviewState; func key(_ key: PreviewKey) async throws -> PreviewState; func select(_ index: Int) async throws -> PreviewState; func clear() async throws -> PreviewState; func close() async }`
  - `struct PreviewOpened: Sendable, Equatable { var librimeVersion: String; var state: PreviewState }`
  - `enum PreviewError: Error, Equatable, CustomStringConvertible { case helperMissing, refusedDirectory, failed(PreviewFailureKind, String), timedOut, helperDied(status: Int32?, stderr: [String]), notDeployed, packagesNotCached([String]), compileFailed([String]), noSchemas }`（后四个给 Task 4、7 用）
  - `actor PreviewSession: PreviewEngine { init(helper: URL, squirrelApp: URL? = nil, openTimeout: Duration = .seconds(15), requestTimeout: Duration = .seconds(5)) }`——第一次请求时才启动进程；`close()` 关 stdin、等进程退出
  - `enum PreviewHelperLocator { static func locate(bundle: Bundle = .main) -> URL? }`：先找 `bundle.bundleURL/Contents/Helpers/rime-preview-helper`，再找 `bundle.executableURL` 旁边的同名文件
  - `static func PreviewSession.filterStderr(_ text: String) -> [String]`：去掉 glog 行（`I`/`W` + 8 位数字开头）和 `WARNING: Logging before InitGoogleLogging()`，留最后 10 行
- 测试支持：`PreviewFixtures.fakeHelper(in: URL, script: String) throws -> URL`（写一个 `#!/bin/sh` 可执行脚本）

- [ ] **Step 1: 写失败的测试**（假辅助程序，不需要 librime）：

```swift
@Test func 正常对话() async throws {   // 脚本：每读一行回一行固定的成功 JSON（state.preedit = "ok"）
    let s = PreviewSession(helper: fake); let o = try await s.open(userDir: tmp, schema: "py")
    #expect(o.state.preedit == "ok"); #expect(try await s.input("a").preedit == "ok"); await s.close()
}
@Test func 辅助程序回的错误() async throws {   // 回 {"ok":false,"error":{"kind":"schemaMissing","message":"m"}}
    await #expect(throws: PreviewError.failed(.schemaMissing, "m")) { try await s.open(userDir: tmp, schema: "x") }
}
@Test func 超时就杀掉() async throws {   // 脚本：read 后 sleep 30；requestTimeout/openTimeout 设 0.3 秒
    await #expect(throws: PreviewError.timedOut) { … }   // 并且耗时 < 5 秒
}
@Test func 中途退出() async throws {   // 脚本：echo "I20261016 11:16:31.6 x] info" >&2; echo "真正的错" >&2; exit 3
    // 抛 .helperDied(status: 3, stderr: ["真正的错"])
}
@Test func 乱码输出() async throws {   // 脚本：echo "garbage" → .helperDied(…)（进程被杀，status 不检查）
}
@Test func 拒绝真实目录不启动进程() async throws {   // userDir = 家目录/Library/Rime → .refusedDirectory；脚本里 touch 一个标记文件，断言标记不存在
}
@Test func 找不到辅助程序() async throws { /* helper 指向不存在的路径 → .helperMissing */ }
@Test func stderr过滤() { #expect(PreviewSession.filterStderr("WARNING: Logging before InitGoogleLogging() is written to STDERR\nI20261016 11:16:31.607891 0x1 modules.cc:96] x\n坏了") == ["坏了"]) }
@Test func 找辅助程序() throws { /* 临时目录里造 X.app/Contents/Helpers/rime-preview-helper，Bundle(url:) → locate 返回它 */ }
```

再加一个宿主机集成测试（`@Suite(.enabled(if: RimeTools.installed))`）：真的辅助程序 + `compiledConfig`，`open` py、`input("nihao")` 第一个候选是「你好」。

- [ ] **Step 2: 跑 `swift test --filter PreviewSessionTests`**，Expected：编译失败。
- [ ] **Step 3: 实现 `PreviewSession`**：`Process` + 三个 `Pipe`；stdout 用 `FileHandle.bytes.lines` 的迭代器逐行读；超时用 `withThrowingTaskGroup` 让读一行和 `Task.sleep` 赛跑，超时就 `terminate()` 并抛 `.timedOut`；读到 EOF 或解码失败时 `terminate()`、等退出，读 stderr，抛 `.helperDied`。进程死了以后的请求都抛 `.helperDied`。
- [ ] **Step 4: 跑 `swift test --filter PreviewSessionTests`**，Expected：PASS。
- [ ] **Step 5: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 6: 提交** `feat(preview): PreviewSession：启动辅助程序、超时和崩溃处理`

---

### Task 4: `PreviewWorkspace`：准备副本

**Files:**
- Create: `Sources/RimeKit/Deploy/FullConfig.swift`、`Sources/RimeKit/Preview/PreviewWorkspace.swift`
- Modify: `Sources/RimeKit/Deploy/Deployer.swift`（第 3 步改调 `FullConfig.assemble`，行为不变）
- Test: `Tests/RimeKitTests/PreviewWorkspaceTests.swift`；现有 `DeployerTests` 等照常通过

**Interfaces:**
- Consumes: `PreviewError`（Task 3）、`RimeFiles`、`Ledger`、`ConfigGenerator`、`RimeCompiler`、`RimeLog.explain`
- Produces（RimeKit，`public`）：
  - `enum FullConfig { static func assemble(rime: URL, ledger: Ledger, generated: URL, newPaths: [String], into full: URL) throws }`（内部函数可以是 `internal`）
  - `struct PreviewSchema: Sendable, Equatable, Identifiable { var id: String; var name: String }`
  - `struct PreviewCopy: Sendable, Equatable { var root: URL /* staging/preview-UUID */; var userDir: URL; var schemas: [PreviewSchema]; func remove() }`
  - `struct PreviewWorkspace: Sendable { init(paths: AppPaths, locations: RimeLocations, compiler: any RimeCompiler); func prepareCurrent() throws -> PreviewCopy; func preparePending(_ input: GenerationInput) throws -> PreviewCopy; static func schemas(in userDir: URL) throws -> [PreviewSchema] }`

- [ ] **Step 1: 写失败的测试**（临时目录里造假的 Rime 目录，`RimeLocations.rimeDirectory` 指向它；编译用 `FakeCompiler`）：

```swift
@Test func 当前生效带build不带输入习惯() throws {
    // 假目录里有：default.custom.yaml、build/py.schema.yaml、build/default.yaml、rime_ice.userdb/LOG、x.userdb.txt、sync/a、user.yaml、installation.yaml、.git/HEAD
    let copy = try ws.prepareCurrent()
    #expect(exists(copy.userDir, "default.custom.yaml") && exists(copy.userDir, "build/py.schema.yaml"))
    for gone in ["rime_ice.userdb", "x.userdb.txt", "sync", "user.yaml", "installation.yaml", ".git"] { #expect(!exists(copy.userDir, gone)) }
    #expect(copy.root.path.hasPrefix(paths.staging.path) && copy.root.lastPathComponent.hasPrefix("preview-"))
    copy.remove(); #expect(!FileManager.default.fileExists(atPath: copy.root.path))
}
@Test func Rime目录是符号链接() throws { /* rimeDirectory 是指向别处的符号链接 → 副本里有真实内容（是目录，不是链接） */ }
@Test func 没部署过() throws { /* 没有 build/ → throws PreviewError.notDeployed，staging 里不留东西 */ }
@Test func 方案列表只留编译出来的() throws {
    // build/default.yaml: schema_list: [{schema: py}, {schema: gone}, {schema: wb}]；build/py.schema.yaml 有 schema/name「测试拼音」；build/wb.schema.yaml 没有 name
    #expect(try PreviewWorkspace.schemas(in: dir) == [PreviewSchema(id: "py", name: "测试拼音"), PreviewSchema(id: "wb", name: "wb")])
}
@Test func 没有方案() throws { /* schema_list 为空或 default.yaml 不存在 → .noSchemas */ }
@Test func 应用后的样子() throws {
    // GenFixtures.input(Settings(schemas: ["py"]), packages:)；FakeCompiler 记下编译的目录并写出 build/default.yaml、build/py.schema.yaml
    // 断言：编译的就是 copy.userDir；userDir 里有生成的 py.schema.yaml，也有 Rime 目录里「应用不管的」配置文件（比如手写的 my.custom.yaml）
}
@Test func 应用后的样子编译失败() throws { /* FakeCompiler 返回失败 → .compileFailed(翻译过的错误)，staging 里不留东西 */ }
```

（`FakeCompiler` 现在的能力不够就在 `DeployFakes.swift` 里加一个可以写文件的变体，不改现有用法。）

- [ ] **Step 2: 跑 `swift test --filter PreviewWorkspaceTests`**，Expected：编译失败。
- [ ] **Step 3: 抽出 `FullConfig.assemble`**（就是 `Deployer.apply` 第 3 步现有的两个循环），`Deployer` 改调它；跑 `swift test --filter Deployer`，Expected：PASS。
- [ ] **Step 4: 实现 `PreviewWorkspace`**：
  - `prepareCurrent`：`rimeDirectory.resolvingSymlinksInPath()`；没有 `build/` 抛 `.notDeployed`；对顶层每一项，`RimeFiles.isRimeOwned(名字) && 名字 != "build"` 就跳过，否则 `FileManager.copyItem`（APFS 上是克隆）；最后算方案列表。
  - `preparePending`：`ConfigGenerator().generate(input, into: root/generated)` → `FullConfig.assemble(… into: root/full)` → `compiler.compile(root/full)`，失败抛 `.compileFailed(RimeLog.explain(errors))` → `userDir = root/full`。
  - 任何一步出错都删掉 `root` 再抛。
  - `schemas(in:)`：Yams 读 `build/default.yaml` 的 `schema_list[].schema`，过滤掉 `build/<id>.schema.yaml` 不存在的，名字取 `schema/name`（没有就用 id）；结果为空抛 `.noSchemas`。
- [ ] **Step 5: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 6: 提交** `feat(preview): PreviewWorkspace：当前生效和应用后的样子两种副本`

---

### Task 5: `PreviewProbe`：找词（留给子项目 3）

**Files:**
- Create: `Sources/RimeKit/Preview/PreviewProbe.swift`
- Test: `Tests/RimeKitTests/PreviewProbeTests.swift`

**Interfaces:**
- Consumes: `PreviewEngine`（Task 3）
- Produces（`public`）：`struct PreviewMatch: Sendable, Equatable { var page: Int; var index: Int; var autoCommitted: Bool }`；`enum PreviewProbe { static func find(_ text: String, code: String, maxPages: Int = 5, in engine: any PreviewEngine) async throws -> PreviewMatch? }`

- [ ] **Step 1: 写失败的测试**（测试里写一个假的 `PreviewEngine`：按编码返回预先排好的几页候选）：

```swift
@Test func 第一页就有() async throws { #expect(try await PreviewProbe.find("你好", code: "nihao", in: fake) == PreviewMatch(page: 0, index: 0, autoCommitted: false)) }
@Test func 翻页才找到() async throws { /* 在第 3 页第 2 个 → PreviewMatch(page: 2, index: 1, autoCommitted: false) */ }
@Test func 自动上屏() async throws { /* input 返回 committed == "一" → PreviewMatch(page: 0, index: 0, autoCommitted: true) */ }
@Test func 找不到() async throws { /* 最后一页也没有 → nil；没到最后一页但超过 maxPages → nil，并且 pageDown 最多调了 maxPages - 1 次 */ }
@Test func 先清空() async throws { /* 第一次调用的是 clear */ }
```

宿主机集成测试一条：真的 `PreviewSession` + `compiledConfig`，`PreviewProbe.find("揖", code: "yi", in: session)` == `PreviewMatch(page: 1, index: 1, autoCommitted: false)`（细节 5）。

- [ ] **Step 2: 跑 `swift test --filter PreviewProbeTests`**，Expected：编译失败。
- [ ] **Step 3: 实现**：`clear` → `input(code)`；`committed == text` 就是自动上屏；之后每页找 `candidates.firstIndex { $0.text == text }`，`isLastPage` 或到了 `maxPages` 就停，否则 `key(.pageDown)`。
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(preview): PreviewProbe：找某个词在第几页第几个`

---

### Task 6: `rimectl preview`

**Files:**
- Create: `Sources/rimectl/Preview.swift`（`extension Rimectl`）
- Modify: `Sources/rimectl/Rimectl.swift`（usage、参数 `--schema`、`--find`、`--pending`，命令 `preview`；`Context` 加 `var previewHelper: URL? = nil`）
- Test: `Tests/RimeKitTests/RimectlPreviewTests.swift`

**Interfaces:**
- Consumes: `PreviewWorkspace`、`PreviewSession`、`PreviewProbe`、`PreviewHelperLocator`；`prepareInput(cacheOnly: true, …)`（`--pending` 用，设计 3.7：已保存的设置、只用缓存）
- Produces：usage 加三行（设计 3.7 原样）；输出格式：
  - 每个编码一行：`编码\t` + （有上屏时 `[上屏]文字 `）+ 本页候选文字用 ` | ` 连起来
  - `--list`：每个方案一行 `id\t名字`
  - `--find`：`找到：第 N 页第 M 个`（从 1 数）/ `自动上屏` / `没找到（最多翻了 5 页）`，没找到退出码 1
  - 出错：`PreviewError` 的 `description`，退出码 1

- [ ] **Step 1: 写失败的测试**（`@Suite(.enabled(if: RimeTools.installed))`；`compiledConfig` 当 `--rime-dir`，`--data-dir` 用临时目录，`Context.previewHelper = PreviewFixtures.helper`）：
  - `preview --schema py nihao yi` → 输出第一行以 `nihao\t你好` 开头，有两行；退出码 0
  - `preview --list` → 有 `py\t` 和 `wb\t` 两行
  - `preview --schema py --find 你好 nihao` → `找到：第 1 页第 1 个`
  - `preview --pending --schema py nihao`：数据目录里用 `SettingsStore` 存 `Settings(schemas: ["py"])`，`GenFixtures.makePackages(in: paths.packages)` 放好缓存，`Context.catalog` 用 `GenFixtures.catalog()` → 第一行以 `nihao\t你好` 开头
  - `preview --schema py --find 不存在 nihao` → 退出码 1
  - `preview --schema nope nihao` → 退出码 1，输出里有「nope」
  - 不带 `--schema` 也不带 `--list` → 退出码 2（usage）
  - 非集成的一条（不需要鼠须管）：`--rime-dir` 指向没有 `build/` 的目录 → 退出码 1，说「还没部署过」
- [ ] **Step 2: 跑 `swift test --filter RimectlPreviewTests`**，Expected：FAIL。
- [ ] **Step 3: 实现**：准备副本（`defer { copy.remove() }`）→ `PreviewSession(helper: context.previewHelper ?? PreviewHelperLocator.locate() …)` → `open` → 逐个编码 `clear` + `input` → 输出 → `close()`。
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(rimectl): preview 命令`

---

### Task 7: AppCore：`PreviewModel`

**Files:**
- Create: `Sources/AppCore/PreviewModel.swift`、`Sources/AppCore/PreviewProblem.swift`
- Modify: `Sources/AppCore/AppEnvironment.swift`（加 `public var previewEngine: @Sendable () throws -> any PreviewEngine = { throw PreviewError.helperMissing }`；`live()` 里用 `PreviewHelperLocator.locate()` 建 `PreviewSession`）
- Modify: `Sources/AppCore/MainModel.swift`（`Page` 在 `.schemas` 后加 `.preview`，标题「试打」，图标 `keyboard`；`public let preview: PreviewModel`）
- Modify: `Sources/AppCore/MainModel+Actions.swift`（应用改动、还原、导入成功后 `preview.markCurrentChanged()`）
- Test: `Tests/RimeKitTests/PreviewModelTests.swift`（假 `PreviewEngine`、`FakeCompiler`、`TransferFixtures.Machine.environment(…)`）

**Interfaces:**
- Consumes: `PreviewWorkspace`、`PreviewEngine`、`PreviewError`、`PreviewSchema`、`PreviewState`、`PreviewKey`；`AppEnvironment` 的 `catalog`、`cachedPackage`、`textReplacements`、`paths`、`locations`、`compiler`
- Produces（AppCore，`@MainActor @Observable public final class PreviewModel`）：
  - `enum Source: Sendable { case current, pending }`；`enum Phase: Equatable { case idle, preparing(String), ready, failed(PreviewProblem) }`
  - 状态：`source`、`schemas: [PreviewSchema]`、`schema: String?`、`state: PreviewState`、`committedText: String`、`phase`、`notes: [String]`、`librimeVersion: String?`
  - `init(env: AppEnvironment)`
  - `func enter(draft: Settings, hasPending: Bool) async`、`func leave() async`、`func switchSource(_ s: Source, draft: Settings, hasPending: Bool) async`、`func selectSchema(_ id: String) async`、`func reload(draft: Settings, hasPending: Bool) async`、`func retry(draft: Settings, hasPending: Bool) async`
  - `func press(_ p: PreviewKeyPress) async`、`func choose(_ index: Int) async`、`func pageUp() async`、`func pageDown() async`、`func clearInput() async`、`func clearCommitted()`
  - `func markCurrentChanged()`；`func needsReload(draft: Settings) -> Bool`
  - `enum PreviewKeyPress: Equatable, Sendable { case text(String), special(PreviewKey), ignored; static func translate(characters: String, special: PreviewKey?, commandLike: Bool) -> PreviewKeyPress }`
  - `struct PreviewProblem: Equatable, Sendable { var title: String; var lines: [String]; var canRetry: Bool }`，`static func describe(_ error: any Error, squirrelInstalled: Bool, hasPending: Bool) -> PreviewProblem`
- `MainModel` 在 `draft` 的设置用 `normalized`（已有）比较；`PreviewModel` 记下准备「应用后的样子」时用的 `Settings`。

- [ ] **Step 1: 写失败的测试**：

```swift
// 按键对照（设计 4.1）
#expect(PreviewKeyPress.translate(characters: "a", special: nil, commandLike: false) == .text("a"))
#expect(PreviewKeyPress.translate(characters: "A", special: nil, commandLike: false) == .text("A"))
#expect(PreviewKeyPress.translate(characters: " ", special: nil, commandLike: false) == .text(" "))
#expect(PreviewKeyPress.translate(characters: "", special: .pageDown, commandLike: false) == .special(.pageDown))
#expect(PreviewKeyPress.translate(characters: "w", special: nil, commandLike: true) == .ignored)
#expect(PreviewKeyPress.translate(characters: "你", special: nil, commandLike: false) == .ignored)   // Review Focus 3
#expect(PreviewKeyPress.translate(characters: "é", special: nil, commandLike: false) == .ignored)
```

`PreviewModel` 的流程测试（假引擎记录收到的调用，返回可配置的状态）：
- `进入页面`：准备了「当前生效」副本，`open` 第一个方案，`phase == .ready`，`schemas` 来自副本
- `打字和上屏累加`：`press(.text("ni"))` 发 `input("ni")`；返回 `committed: "你"` 两次以后 `committedText == "你你"`；`clearCommitted()` 清空
- `点候选`：`choose(2)` 发 `select(2)`；`pageDown()` 发 `key(.pageDown)`
- `换方案`：发 `open(同一目录, 新方案)`，不重新准备副本
- `换来源`：`switchSource(.pending, draft:…)` 准备新副本、`open` 新目录、旧副本目录被删掉；缺包（`cachedPackage` 返回 nil）→ `phase == .failed`，标题「这些方案还没下载过：…，应用改动时会下载」
- `应用后的样子读不了文本替换`：`textReplacements` 抛错且设置里开了同步 → 照样 ready，`notes` 有一行说明
- `离开页面`：`close()` 被调用、副本目录不存在
- `准备时离开`（Review Focus 5）：`FakeCompiler` 编译时等一个信号；`enter`/`switchSource` 进行中调 `leave()`，放行后：没有调用 `open`、没有副本留在 `staging/`、`phase == .idle`
- `超时以后重试`（Review Focus 4）：第一个引擎 `input` 抛 `.timedOut` → `phase == .failed` 且 `canRetry`；`retry` 用 `env.previewEngine()` 建了新引擎并重新 `open`，`phase == .ready`
- `需要重新载入`：`markCurrentChanged()` 后来源是 current 时 `needsReload == true`；来源是 pending 时 draft 改了才是 true；`reload` 时没有未应用的改动就切回 current（细节 7）
- `出错说明`：`PreviewProblem.describe` 对设计第 5 节每一行给出原话标题，例如：`.notDeployed` →「鼠须管还没部署过配置」，`hasPending` 时多一行「可以改看「应用后的样子」」；`.failed(.loadFailed, "…have different Team IDs…")` →「应用的签名有问题，试打用不了」；`.failed(.unsupportedVersion, "1.20.0")` →「这个版本的鼠须管（librime 1.20.0）还没验证过，暂时不能试打」；`.timedOut`/`.helperDied` →「试打出错了」且 `canRetry`；`squirrelInstalled == false` →「先安装鼠须管」
- `MainModel`：`Page.allCases` 里 `.preview` 紧跟 `.schemas`；应用改动成功后 `preview.needsReload` 为 true（来源是 current、页面进入过）

- [ ] **Step 2: 跑 `swift test --filter PreviewModelTests`**，Expected：编译失败。
- [ ] **Step 3: 实现 `PreviewProblem`**（设计第 5 节的文字原样放进去；`helperDied` 的 `lines` 带退出码和 stderr 行）。
- [ ] **Step 4: 实现 `PreviewModel`**：重活（准备副本、编译）放 `Task.detached`；用一个递增的「代号」丢掉过期的结果（离开页面、换来源时代号加一，结果回来时代号对不上就删掉副本、不 `open`）。「应用后的样子」的输入：`draft.validate(catalog)` → 每个 `requiredPackages` 用 `env.cachedPackage`，缺的收集起来抛 `.packagesNotCached` → 开了同步就读文本替换（失败就用空数组并加 note）→ `GenerationInput`。
- [ ] **Step 5: 接进 `MainModel`**（`Page`、`preview` 属性、三处 `markCurrentChanged()`）。
- [ ] **Step 6: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 7: 提交** `feat(app): 试打页的逻辑 PreviewModel`

---

### Task 8: AppUI：「试打」页

**Files:**
- Create: `Sources/AppUI/PreviewPage.swift`
- Modify: `Sources/AppUI/MainView.swift`（`case .preview: PreviewPage(model: model)`；注释里「6 页」改成「7 页」）

**Interfaces:**
- Consumes: `MainModel.preview`、`MainModel.draft`、`MainModel.hasPendingChanges`、`MainModel.page`；Task 7 的全部 `PreviewModel` 接口

- [ ] **Step 1: 写 `PreviewPage`**（设计第 4 节）：
  - 顶部 `Picker("来源", …).pickerStyle(.segmented)`，`hasPendingChanges == false` 时「应用后的样子」不可选；方案 `Picker`。
  - `needsReload(draft:)` 为真时一行提示「配置变了」+「重新载入」按钮。
  - 输入区：`.focusable()` + `.focused(...)`，进入页面后自动获得焦点；`.onKeyPress(phases: .down)` 里把 `KeyEquivalent` 的 `.delete`、`.escape`、`.return`、`.pageUp`、`.pageDown`、`.upArrow`、`.downArrow` 翻成 `PreviewKey`，`commandLike` = 修饰键含 command、control、option；`translate` 结果是 `.ignored` 时返回 `.ignored`（交给系统），否则 `.handled`。
  - 显示 `preedit`；候选每个是按钮「标签. 文字 注释」（标签用 `labels`，没有就 1、2、3……），高亮 `highlighted`；「上一页」「下一页」（最后一页时下一页不可点）、「清空」。
  - 「已上屏」文本（可选中复制）+「清空」。
  - `phase` 是 `.preparing` 显示进度和文字；`.failed` 显示标题、各行、能重试时「重试」按钮；没装鼠须管时带「去诊断页」按钮（`model.page = .diagnostics`）。
  - `.task { await preview.enter(…) }`、`.onDisappear { Task { await preview.leave() } }`。
- [ ] **Step 2: `swift build`**，Expected：编译通过，没有新警告。
- [ ] **Step 3: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 4: 提交** `feat(app): 侧边栏加「试打」页`

---

### Task 9: 打包和签名

**Files:**
- Create: `tools/app/preview-helper.entitlements`（只有 `com.apple.security.cs.disable-library-validation` = true）
- Create: `tools/release/check-entitlements.sh`
- Modify: `tools/app/build-app.sh`、`tools/release/build-release.sh`、`tools/release/check-dmg.sh`

**Interfaces:**
- Produces：`.build/app/SquirrelHelper.app/Contents/Helpers/rime-preview-helper`；`./tools/release/check-entitlements.sh <应用> [--release]`：辅助程序存在、签名有效、有这个 entitlement；主程序没有这个 entitlement；加 `--release` 时还检查两者都有 hardened runtime（`flags=…(runtime)`）。不满足就非零退出并说明哪一条。

- [ ] **Step 1: 写 `check-entitlements.sh`**，先对现在的 `./tools/app/build-app.sh` 产物跑一次，Expected：失败，说「没有辅助程序」。
- [ ] **Step 2: 改 `build-app.sh`**（设计第 6 节）：多编 `--product rime-preview-helper`，复制到 `Contents/Helpers/`；签名顺序：资源包 → 辅助程序（`--entitlements tools/app/preview-helper.entitlements`；正式身份时加 `--options runtime --timestamp`）→ 应用。不用 `--deep`。
- [ ] **Step 3: 跑 `./tools/app/build-app.sh` 再跑 `check-entitlements.sh`**，Expected：`ok`。
- [ ] **Step 4: `build-release.sh`** 在 `codesign --verify` 之后加 `./tools/release/check-entitlements.sh "$APP" --release`；`check-dmg.sh` 对挂载的应用也跑（带 `--release`）。
- [ ] **Step 5: 跑 `ALLOW_DIRTY=1 SKIP_NOTARIZE=1 ./tools/release/build-release.sh`**（会用钥匙串里的 Developer ID 签名），Expected：打出 dmg，`check-entitlements` 输出 `ok`。
- [ ] **Step 6: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 7: 提交** `build: 应用包里带上 rime-preview-helper，只有它带 disable-library-validation`

---

### Task 10: 测试机检查和文档

**Files:**
- Create: `docs/typing-preview-vm-log.md`
- Modify: `docs/verified-facts.md`（8.1 补测试机结论）、`docs/release.md`（辅助程序签名、公证第一次要确认）、`docs/superpowers/plans/2026-10-15-v2-roadmap.md`（子项目 2 状态）、`docs/superpowers/specs/2026-10-16-typing-preview-design.md`（状态：已实现）、`CLAUDE.md`（「先读这些」加设计；子项目 2 完成）

- [ ] **Step 1: 记录真实目录**：`./tools/vm/vm.sh ssh squirrel-dev 'find ~/Library/Rime -type f -exec stat -f "%m %z %N" {} + | sort -k3 > /tmp/rime-before.txt'`。
- [ ] **Step 2: debug 包**：`./tools/vm/install-app.sh squirrel-dev`，请用户在测试机里按设计 8.3 第 1 条试：两种来源、换方案、`nihao` 出候选、数字选词、空格上屏、`-` `=` 翻页、上下键、退格、Esc、已上屏累加、离开再回来、应用改动后出现「配置变了」。记下结果。
- [ ] **Step 3: 发布签名的包**：把 Task 9 打出的 dmg 用 `./tools/vm/vm.sh ssh squirrel-dev "cat > /Users/Shared/SquirrelHelper.dmg" < …` 传进去，挂载后拷到 `~/Applications` 打开，请用户试打一次；`codesign -d --entitlements - …/Contents/Helpers/rime-preview-helper` 有 entitlement，主程序没有。
- [ ] **Step 4: 对比真实目录**：同 Step 1 生成 `/tmp/rime-after.txt`，`diff` 没有输出（鼠须管在运行时它自己写的 userdb 除外——如果有差异，确认只是 `*.userdb` 并在记录里说明）。
- [ ] **Step 5: 写文档**：测试记录写进 `docs/typing-preview-vm-log.md`；`verified-facts` 8.1 补「发布签名的应用里辅助程序能加载、主程序不需要 entitlement」和 Task 2 实测的 return/up/down 行为；其余文件按上面的 Files 改。
- [ ] **Step 6: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 7: 提交** `docs: 试打预览的测试机记录，更新说明和路线图`，然后问用户能不能推送 `main`。

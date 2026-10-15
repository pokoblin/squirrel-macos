# 阶段 6：一键导出、导入 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `rimectl export 文件` 把设置、个人内容（个人词库、手动短语）、输入习惯快照打成一个 zip；`rimectl import 文件` 在另一台 Mac 上下载最新上游包、按 6.1 写入配置、合并输入习惯（设计 6.3、6.4）。

**Architecture:** 新增 `UserDB/`：`RimeDictManager`（包装鼠须管自带的 `rime_dict_manager`，在 Rime 目录里运行）和 `UserDBTransfer`（先退出鼠须管、导出或合并、被占着就重试、做完再启动）。新增 `Transfer/`：
- `ExportManifest`：导出文件的清单
- `Exporter`：在暂存区拼好内容，用 `ditto` 打包
- `ImportArchive`：解压、检查格式、只认需要的文件
- `Importer`：把应用里原来的设置另存一份 → 走 `Deployer.apply` → 合并输入习惯

配套改动：
- `Shell.run` 可以指定当前目录。
- `SquirrelControlling` 加 `quit()`。
- `ApplyOptions` 可以要求这次的备份永久保留。
- 接管和导入共用的「保存设置和个人内容」提成 `AppDataWriter`。

**Tech Stack:** Swift 6.4、Swift Testing、Foundation、系统自带 `/usr/bin/ditto`（打包、解压）、`/usr/bin/killall`、鼠须管自带 `rime_dict_manager`。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 5 节「导出文件」、6.1、6.3、6.4、7）；事实 [docs/verified-facts.md](../../verified-facts.md)「输入习惯：rime_dict_manager」；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## 写计划前的实测（2026-10-15，宿主机临时目录）

| 事实 | 结果 |
|---|---|
| 目录里还没有输入习惯数据库时，`rime_dict_manager --import <名字> <文件>` | 能导入，自动新建 `<名字>.userdb`（新电脑上还没打过字也能合并） |
| 同一个快照导入两次 | 再导出和第一次完全一样（合并，不重复） |
| `--export` 的文件 | 开头 `#` 注释（`# Rime user dictionary export`、`#@/db_name` 等），之后每行「编码<Tab>词<Tab>数字」 |
| `ditto -c -k --sequesterRsrc 目录 文件.zip` | 会多出 `__MACOSX/` 和 `._*` 文件 |
| `ditto -c -k --norsrc --noextattr --noqtn 目录 文件.zip` | 干净：zip 里直接是目录里的内容（`manifest.json`、`personal/…`、`userdb/…`） |
| `ditto -x -k` 解压路径是 `../evil.txt` 的条目 | 去掉 `../`，写在解压目录里面，不会写到外面 |

## 本阶段要定的事（计划里的做法，请确认）

| # | 问题 | 计划里的做法 | 理由 |
|---|---|---|---|
| 1 | 导出文件的格式 | zip：`manifest.json`（格式版本、导出时间、设置、导出时的上游版本、各部分的条数）+ `personal/dicts/*.dict.yaml` + `personal/phrases.txt` + `userdb/<名字>.userdb.txt`。扩展名按设计等应用名定了再定；命令行接受任何路径，先用 `.zip` | 设计第 5 节 |
| 2 | 输入习惯用哪个命令 | `--export` / `--import`（文本快照，文件放进 zip） | 阶段 0 留给本阶段定；`--backup` 写到 `sync/` 目录，还要再去找文件 |
| 3 | 导入会覆盖应用里原来的设置和个人内容，Rime 目录的备份不含这些 | 导入前如果已有设置，先把原来的设置和个人内容另存成一份导出文件（`before-import/<时间>.zip`，不含输入习惯） | 导入一个旧文件就会丢掉个人词库，而且没法撤销 |
| 4 | 导入前的 Rime 目录备份 | 永久保留，说明写「导入前」；每次导入一份 | 设计 6.4：「已有配置，先完整备份（永久保留）再导入」 |
| 5 | 导入时遇到应用外的改动、同名文件 | 都覆盖（先备份），不逐个问 | 导入就是要换成导出文件里的配置；备份在 |
| 6 | 新电脑上的安装和添加输入法 | `rimectl import` 要求先装好鼠须管：没装就提示先运行 `rimectl install`、`rimectl activate`。把这几步串成「一键」放到阶段 8 的应用里 | 命令行各步分开更好排查；应用里再串起来 |
| 7 | 文本替换生成的短语 | 不导出，也不做「包含」选项。导入后设置里同步是开着的，就读新电脑的文本替换生成 | 设计：默认不导出；同一个 Apple 账户会自动同步 |
| 8 | 输入习惯合并不上（鼠须管一直被拉起来占着数据库） | 配置照样导入完成，报告合并失败，提示再运行一次 `rimectl import`（配置不会重复写，输入习惯是合并） | 不让输入习惯拖累整个导入 |
| 9 | 和「输入源补注册」那个会话的关系 | 它改了 `SquirrelControlling`（加了 `registerInputSource()`）和测试替身，已提交（`b8072fb`）。本计划给同一个协议再加 `quit()`，所有测试替身都要实现；执行前先确认那边没有新的未提交改动 | 两边改同一批文件 |

## Global Constraints

- 宿主机**不碰** `~/Library/Rime`、`/Library/Input Methods`、输入法启用状态。宿主机上跑 `rime_dict_manager` 只在临时目录里（它把当前目录当用户目录，已实测）；不在宿主机上退出、启动鼠须管。
- 真实的导出、导入只在测试机里做：`squirrel-dev` 导出；新克隆一台 `squirrel-import` 导入，测完删掉。同时最多两台测试机。登录桌面、添加输入法、打字检查由用户做。
- **真实配置只在 6.1 的第 6 步才改**；导入时设置和个人内容在写入成功后、通知鼠须管前保存（`afterWrite`），编译失败等情况什么都不保存。
- 导出、合并输入习惯前先退出鼠须管，做完再 `open` 启动（实测：它占着数据库时导不出来）。被占着就重试，最多 3 次。
- 导入文件当作不可信数据：只认 `manifest.json`、`personal/dicts/*.dict.yaml`、`personal/phrases.txt`、`userdb/<名字>.userdb.txt` 这些**普通文件**（符号链接、子目录、别的文件跳过并提示）；输入习惯的名字只能是字母、数字、`_`、`-`、`.`。
- 隐私：输出只写条数和文件名，**不写**个人词库、短语、输入习惯的内容。文本替换生成的短语不导出。测试数据全部是编的。
- 第三方依赖只有 Yams。
- 用简单直白的中文写错误信息和命令行输出。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 导出后在一台空的 Mac 上导入：设置、个人词库、手动短语、输入习惯都回来，打字效果一样（任务 7 用假的鼠须管跑通；任务 8 在新克隆的测试机里实测）。
2. 导入一个旧的导出文件，覆盖了应用里现在的设置和个人词库 → 原来的另存了一份，能找回（任务 6、7 有测试）。
3. 导出文件被改过、坏了、来自新版本应用，或者里面有奇怪的文件（符号链接、`../`、不认识的名字）→ 拒绝或跳过并说明，不写到解压目录外面（任务 4 有测试）。
4. 导出、合并输入习惯时鼠须管一直被系统拉起来 → 重试几次后说清楚「先别打字再试」，鼠须管最后要重新启动起来（任务 2 有测试，任务 8 实测）。
5. 导入时编译失败、写入失败 → 真实目录、设置、个人内容都不动（任务 6 有测试）。

---

## 文件结构

```
Sources/RimeKit/
  Support/Shell.swift                   # run 可以指定当前目录
  Deploy/SquirrelControl.swift          # quit()
  Deploy/Deployer.swift                 # ApplyOptions.permanentBackupReason
  AppPaths.swift                        # beforeImport
  Config/AppDataWriter.swift            # 新：保存设置和个人内容（接管、导入共用）
  Takeover/TakeoverApplier.swift        # 改用 AppDataWriter
  Packages/Unzipper.swift               # 加 Zipper
  UserDB/RimeDictManager.swift          # 新：UserDBTool、UserDBError、RimeDictManager
  UserDB/UserDBTransfer.swift           # 新：退出鼠须管、导出/合并、重试、启动
  Transfer/ExportManifest.swift         # 新：ExportManifest、TransferError
  Transfer/Exporter.swift               # 新
  Transfer/ImportArchive.swift          # 新
  Transfer/Importer.swift               # 新
Sources/rimectl/Rimectl.swift           # export、import
Tests/RimeKitTests/
  Support/DeployFakes.swift             # FakeSquirrel.quit
  Support/TransferFakes.swift           # 新：FakeUserDBTool、TransferFixtures
  ShellTests.swift
  RimeDictManagerTests.swift            # 宿主机真实工具，只用临时目录
  UserDBTransferTests.swift
  ExporterTests.swift
  ImportArchiveTests.swift
  DeployerTests.swift（加一个）
  ImporterTests.swift
  RimectlTransferTests.swift
docs/phase6-vm-log.md
```

---

### Task 1: 在 Rime 目录里运行 `rime_dict_manager`；退出鼠须管

**Files:**
- Modify: `Sources/RimeKit/Support/Shell.swift`
- Modify: `Sources/RimeKit/Deploy/SquirrelControl.swift`（协议和实现加 `quit()`）
- Modify: `Tests/RimeKitTests/Support/DeployFakes.swift`（`FakeSquirrel.quit`），以及其它实现 `SquirrelControlling` 的测试替身（`grep -rn "SquirrelControlling" Tests` 找全，例如 `TakeoverApplierTests.WatchingSquirrel`）
- Create: `Sources/RimeKit/UserDB/RimeDictManager.swift`
- Test: `Tests/RimeKitTests/ShellTests.swift`、`Tests/RimeKitTests/RimeDictManagerTests.swift`

**Interfaces:**
- Produces:
  - `Shell.run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> ShellResult`
  - `SquirrelControlling.quit() throws`（`SquirrelControl`：`/usr/bin/killall -u <当前用户> Squirrel`，没在运行也不算错）；`FakeSquirrel.quit()` 记 `"quit"`、`running = false`
  - `public enum UserDBError: Error, Equatable, Sendable, CustomStringConvertible { case locked(String), failed(String, String), stillLocked(String), badName(String) }`
  - `public protocol UserDBTool: Sendable { func list() throws -> [String]; func export(_ name: String, to file: URL) throws; func importSnapshot(_ name: String, from file: URL) throws }`
  - `public struct RimeDictManager: UserDBTool { init(locations: RimeLocations); init(tool: URL, rimeDirectory: URL); static func isValidName(_ name: String) -> Bool }`

- [ ] **Step 0: 确认「输入源补注册」会话的改动已经提交**

Run: `git status --short Sources Tests`
Expected: 没有那个会话留下的未提交改动（`SquirrelControl.swift`、`DeployFakes.swift` 等）。还有的话先停下问用户。

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/ShellTests.swift` 的 suite 里加：

```swift
    @Test func 可以指定当前目录() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let r = try Shell.run("/bin/pwd", [], currentDirectory: dir.url)
        let printed = URL(fileURLWithPath: r.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(printed.resolvingSymlinksInPath() == dir.url.resolvingSymlinksInPath())
    }
```

`Tests/RimeKitTests/RimeDictManagerTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

/// 用宿主机上鼠须管自带的 rime_dict_manager，只在临时目录里运行（它把当前目录当 Rime 用户目录）
@Suite(.enabled(if: RimeTools.installed))
struct RimeDictManagerTests {
    static let snapshot = """
        # Rime user dictionary export
        #@/db_name\ttest
        #@/db_type\tuserdb
        #@/rime_version\t1.16.0
        #@/user_id\tunknown
        ni hao \t你好\t0
        ce shi \t测试\t0

        """

    func manager(_ dir: TempDir) -> RimeDictManager {
        RimeDictManager(tool: URL(fileURLWithPath: RimeTools.squirrel + "/MacOS/rime_dict_manager"),
                        rimeDirectory: dir.url.appending(path: "Rime", directoryHint: .isDirectory))
    }

    @Test func 空目录里没有输入习惯() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try manager(dir).list() == [])
    }

    @Test func 还没有数据库时也能导入_导入两次是合并() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let m = manager(dir)
        let file = dir.url.appending(path: "in.txt")
        try Data(Self.snapshot.utf8).write(to: file)
        try m.importSnapshot("test", from: file)
        #expect(try m.list() == ["test"])
        let first = dir.url.appending(path: "out1.txt")
        try m.export("test", to: first)
        try m.importSnapshot("test", from: file)
        let second = dir.url.appending(path: "out2.txt")
        try m.export("test", to: second)
        let text = try String(contentsOf: first, encoding: .utf8)
        #expect(text.contains("你好"))
        #expect(text.contains("测试"))
        #expect(try String(contentsOf: second, encoding: .utf8) == text)
    }

    @Test func 名字不对就不运行() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(throws: UserDBError.badName("../x")) { try manager(dir).export("../x", to: dir.url.appending(path: "o.txt")) }
        #expect(RimeDictManager.isValidName("rime_ice"))
        #expect(RimeDictManager.isValidName("wubi86_jidian"))
        #expect(!RimeDictManager.isValidName(""))
        #expect(!RimeDictManager.isValidName(".hidden"))
        #expect(!RimeDictManager.isValidName("a b"))
        #expect(!RimeDictManager.isValidName("a/b"))
    }

    @Test func 导出不存在的输入习惯会报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(throws: UserDBError.self) { try manager(dir).export("nothing", to: dir.url.appending(path: "o.txt")) }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "ShellTests|RimeDictManagerTests" 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败（`extra argument 'currentDirectory'` / `cannot find 'RimeDictManager'`）

- [ ] **Step 3: 实现**

`Sources/RimeKit/Support/Shell.swift`：签名改成 `static func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) throws -> ShellResult`，在 `process.arguments = arguments` 后面加一行 `process.currentDirectoryURL = currentDirectory`。

`Sources/RimeKit/Deploy/SquirrelControl.swift`：
1. 协议里加 `func quit() throws`（注释：`/// 退出鼠须管：导出、合并输入习惯前要先退出，不然数据库被它占着`）。
2. `SquirrelControl` 里加：

```swift
    /// 只退出当前用户的鼠须管；没在运行时 killall 返回 1，不算错
    public func quit() throws {
        _ = try Shell.run("/usr/bin/killall", ["-u", NSUserName(), "Squirrel"])
    }
```

`Tests/RimeKitTests/Support/DeployFakes.swift` 的 `FakeSquirrel` 里加：

```swift
    func quit() throws {
        lock.withLock {
            log.append("quit")
            running = false
        }
    }
```

其它实现 `SquirrelControlling` 的测试替身也加上 `func quit() throws {}`（用 `grep -rn ": SquirrelControlling" Tests` 找）。

`Sources/RimeKit/UserDB/RimeDictManager.swift`：

```swift
import Foundation

public enum UserDBError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 数据库正被鼠须管占着
    case locked(String)
    case failed(String, String)
    /// 退出后又被系统马上拉起来，重试几次还是占着
    case stillLocked(String)
    case badName(String)

    public var description: String {
        switch self {
        case .locked(let name):
            return "输入习惯 \(name) 正被鼠须管使用"
        case let .failed(name, message):
            return "处理输入习惯 \(name) 失败：\(message)"
        case .stillLocked(let name):
            return "鼠须管一直占着输入习惯 \(name)（退出后又被系统马上启动了）。请先别打字，再试一次"
        case .badName(let name):
            return "输入习惯的名字不对：\(name)"
        }
    }
}

/// 导出、合并输入习惯的工具（测试时换成假的）
public protocol UserDBTool: Sendable {
    /// Rime 目录里有哪些输入习惯（词典名）
    func list() throws -> [String]
    func export(_ name: String, to file: URL) throws
    /// 合并（不是覆盖）：已有的条目不丢、不重复计数（已实测）
    func importSnapshot(_ name: String, from file: URL) throws
}

/// 鼠须管自带的 rime_dict_manager。它把当前目录当 Rime 用户目录（已实测），所以每次都在 Rime 目录里运行
public struct RimeDictManager: UserDBTool {
    let tool: URL
    let rimeDirectory: URL

    public init(locations: RimeLocations) {
        self.init(tool: locations.squirrelApp.appending(path: "Contents/MacOS/rime_dict_manager"),
                  rimeDirectory: locations.rimeDirectory)
    }

    public init(tool: URL, rimeDirectory: URL) {
        self.tool = tool
        self.rimeDirectory = rimeDirectory
    }

    /// 词典名只能是字母、数字、_ - .，不能以 . 开头（会拼进文件名和命令参数）
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") }
    }

    public func list() throws -> [String] {
        let r = try run(["--list"])
        guard r.status == 0 else { throw UserDBError.failed("--list", r.stderr) }
        // 没有时输出 "No user dictionary is found."（有空格，不是合法名字，自然被滤掉）
        return r.stdout.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter(Self.isValidName)
    }

    public func export(_ name: String, to file: URL) throws {
        guard Self.isValidName(name) else { throw UserDBError.badName(name) }
        try check(name, try run(["--export", name, file.path]))
    }

    public func importSnapshot(_ name: String, from file: URL) throws {
        guard Self.isValidName(name) else { throw UserDBError.badName(name) }
        try check(name, try run(["--import", name, file.path]))
    }

    func check(_ name: String, _ r: ShellResult) throws {
        guard r.status == 0 else {
            let message = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            // 鼠须管占着时：Error opening db 'rime_ice' read-only.（已实测）
            if message.contains("Error opening db") { throw UserDBError.locked(name) }
            throw UserDBError.failed(name, message)
        }
    }

    func run(_ arguments: [String]) throws -> ShellResult {
        try FileManager.default.createDirectory(at: rimeDirectory, withIntermediateDirectories: true)
        return try Shell.run(tool.path, arguments, currentDirectory: rimeDirectory)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "ShellTests|RimeDictManagerTests" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过。

「导出不存在的输入习惯会报错」如果没报错（`rime_dict_manager` 退出码是 0）：看它的输出，在 `check` 里按实际输出判断失败，记一条 Ruling。

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "feat: 包装 rime_dict_manager（在 Rime 目录里运行）；鼠须管可以退出

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 导出、合并输入习惯：先退出鼠须管，被占着就重试

**Files:**
- Create: `Sources/RimeKit/UserDB/UserDBTransfer.swift`
- Create: `Tests/RimeKitTests/Support/TransferFakes.swift`（这一步先放 `FakeUserDBTool`）
- Test: `Tests/RimeKitTests/UserDBTransferTests.swift`

**Interfaces:**
- Consumes: `UserDBTool`、`UserDBError`、`SquirrelControlling.quit`（任务 1）
- Produces:
  - `public struct UserDBTransfer: Sendable { init(tool: any UserDBTool, squirrel: any SquirrelControlling, attempts: Int = 3, sleep: @escaping @Sendable (Duration) async -> Void = …); func exportAll(into dir: URL) async throws -> [String]; func importAll(_ files: [String: URL]) async throws -> [String] }`
    - `exportAll`：写 `dir/<名字>.userdb.txt`，返回名字（排序）；原来在运行的鼠须管做完重新启动，原来没运行就不启动。
    - `importAll`：做完总是启动鼠须管（设计 6.4）。出错时也会先启动再抛出。
  - 测试替身 `FakeUserDBTool(dbs: [String: String] = [:], lockedFailures: Int = 0)`：`dbs` 是名字 → 快照内容；前 `lockedFailures` 次导出或导入报 `.locked`；`calls` 记 `"export 名字"` / `"import 名字"`。

- [ ] **Step 1: 写测试替身和失败的测试**

`Tests/RimeKitTests/Support/TransferFakes.swift`：

```swift
import Foundation
@testable import RimeKit

/// 假的 rime_dict_manager：输入习惯存在内存里；前几次调用可以假装被鼠须管占着
final class FakeUserDBTool: UserDBTool, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String]
    private var failures: Int
    private var log: [String] = []

    init(dbs: [String: String] = [:], lockedFailures: Int = 0) {
        stored = dbs
        failures = lockedFailures
    }

    var dbs: [String: String] { lock.withLock { stored } }
    var calls: [String] { lock.withLock { log } }

    func list() throws -> [String] { lock.withLock { stored.keys.sorted() } }

    func export(_ name: String, to file: URL) throws {
        let text: String? = try lock.withLock {
            if failures > 0 { failures -= 1; throw UserDBError.locked(name) }
            log.append("export \(name)")
            return stored[name]
        }
        guard let text else { throw UserDBError.failed(name, "没有这个输入习惯") }
        try Data(text.utf8).write(to: file)
    }

    func importSnapshot(_ name: String, from file: URL) throws {
        let text = try String(contentsOf: file, encoding: .utf8)
        try lock.withLock {
            if failures > 0 { failures -= 1; throw UserDBError.locked(name) }
            log.append("import \(name)")
            stored[name] = (stored[name] ?? "") + text
        }
    }
}
```

`Tests/RimeKitTests/UserDBTransferTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct UserDBTransferTests {
    func squirrel(_ dir: TempDir, running: Bool) throws -> FakeSquirrel {
        FakeSquirrel(locations: try DeployFixtures.locations(dir), running: running)
    }

    func transfer(_ tool: FakeUserDBTool, _ squirrel: FakeSquirrel) -> UserDBTransfer {
        UserDBTransfer(tool: tool, squirrel: squirrel, sleep: { _ in })
    }

    @Test func 导出前退出鼠须管_导完重新启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tool = FakeUserDBTool(dbs: ["b": "快照b\n", "a": "快照a\n"])
        let s = try squirrel(dir, running: true)
        let out = dir.url.appending(path: "userdb", directoryHint: .isDirectory)
        #expect(try await transfer(tool, s).exportAll(into: out) == ["a", "b"])
        #expect(try String(contentsOf: out.appending(path: "a.userdb.txt"), encoding: .utf8) == "快照a\n")
        #expect(try String(contentsOf: out.appending(path: "b.userdb.txt"), encoding: .utf8) == "快照b\n")
        #expect(s.calls == ["quit", "launch"])
    }

    @Test func 鼠须管原来没运行_导出后也不启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: false)
        _ = try await transfer(FakeUserDBTool(dbs: ["a": "x\n"]), s).exportAll(into: dir.url.appending(path: "u"))
        #expect(s.calls == [])
    }

    @Test func 没有输入习惯时什么都不做() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let s = try squirrel(dir, running: true)
        #expect(try await transfer(FakeUserDBTool(), s).exportAll(into: dir.url.appending(path: "u")) == [])
        #expect(s.calls == [])
    }

    @Test func 被占着时重试() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tool = FakeUserDBTool(dbs: ["a": "x\n"], lockedFailures: 2)
        let s = try squirrel(dir, running: true)
        #expect(try await transfer(tool, s).exportAll(into: dir.url.appending(path: "u")) == ["a"])
        #expect(tool.calls == ["export a"])
        #expect(s.calls.last == "launch")
    }

    @Test func 一直被占着就报错_鼠须管还是会启动() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tool = FakeUserDBTool(dbs: ["a": "x\n"], lockedFailures: 99)
        let s = try squirrel(dir, running: true)
        await #expect(throws: UserDBError.stillLocked("a")) {
            try await transfer(tool, s).exportAll(into: dir.url.appending(path: "u"))
        }
        #expect(s.calls.last == "launch")
    }

    @Test func 合并后启动鼠须管() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "a.userdb.txt")
        try Data("新的\n".utf8).write(to: file)
        let tool = FakeUserDBTool(dbs: ["a": "旧的\n"])
        let s = try squirrel(dir, running: false)
        #expect(try await transfer(tool, s).importAll(["a": file]) == ["a"])
        #expect(tool.dbs["a"] == "旧的\n新的\n")
        #expect(s.calls == ["launch"])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter UserDBTransferTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'UserDBTransfer' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/UserDB/UserDBTransfer.swift`：

```swift
import Foundation

/// 导出、合并输入习惯（设计 6.3、6.4）：鼠须管占着数据库时导不出来（已实测），
/// 所以先退出它；退出后用户一打字系统可能马上又把它拉起来，所以被占着就再退出一次重试
public struct UserDBTransfer: Sendable {
    let tool: any UserDBTool
    let squirrel: any SquirrelControlling
    let attempts: Int
    let sleep: @Sendable (Duration) async -> Void

    public init(tool: any UserDBTool, squirrel: any SquirrelControlling, attempts: Int = 3,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.tool = tool
        self.squirrel = squirrel
        self.attempts = attempts
        self.sleep = sleep
    }

    /// 导出全部输入习惯到 dir/<名字>.userdb.txt，返回名字（排序）。原来在运行的鼠须管做完重新启动
    public func exportAll(into dir: URL) async throws -> [String] {
        let names = try tool.list().sorted()
        guard !names.isEmpty else { return [] }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let wasRunning = squirrel.isRunning()
        do {
            for name in names {
                try await withSquirrelStopped(name) { try tool.export(name, to: dir.appending(path: "\(name).userdb.txt")) }
            }
        } catch {
            if wasRunning { try? squirrel.launch() }
            throw error
        }
        if wasRunning { try squirrel.launch() }
        return names
    }

    /// 把快照合并进输入习惯（名字 → 快照文件），做完启动鼠须管
    public func importAll(_ files: [String: URL]) async throws -> [String] {
        let names = files.keys.sorted()
        guard !names.isEmpty else { return [] }
        do {
            for name in names {
                try await withSquirrelStopped(name) { try tool.importSnapshot(name, from: files[name]!) }
            }
        } catch {
            try? squirrel.launch()
            throw error
        }
        try squirrel.launch()
        return names
    }

    func withSquirrelStopped(_ name: String, _ body: () throws -> Void) async throws {
        for attempt in 1...attempts {
            try await stopSquirrel()
            do {
                try body()
                return
            } catch let error as UserDBError {
                guard case .locked = error else { throw error }
                if attempt == attempts { break }
                await sleep(.seconds(1))
            }
        }
        throw UserDBError.stillLocked(name)
    }

    /// 退出鼠须管，最多等 5 秒让它真的退出
    func stopSquirrel() async throws {
        guard squirrel.isRunning() else { return }
        try squirrel.quit()
        var waited = 0
        while squirrel.isRunning(), waited < 50 {
            await sleep(.milliseconds(100))
            waited += 1
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter UserDBTransferTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 6 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/UserDB/UserDBTransfer.swift Tests/RimeKitTests/Support/TransferFakes.swift Tests/RimeKitTests/UserDBTransferTests.swift
git commit -m "feat: 导出、合并输入习惯前退出鼠须管，被占着就重试，做完再启动

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 导出

**Files:**
- Modify: `Sources/RimeKit/Packages/Unzipper.swift`（加 `Zipper`、`ZipError`）
- Modify: `Sources/RimeKit/AppPaths.swift`（加 `beforeImport`）
- Create: `Sources/RimeKit/Transfer/ExportManifest.swift`
- Create: `Sources/RimeKit/Transfer/Exporter.swift`
- Modify: `Tests/RimeKitTests/Support/TransferFakes.swift`（加 `TransferFixtures`）
- Test: `Tests/RimeKitTests/ExporterTests.swift`

**Interfaces:**
- Consumes: `UserDBTransfer`（任务 2）、`SettingsStore`、`PersonalContent`、`Ledger`、`ApplyLock`、`PhraseFile`
- Produces:
  - `public struct Zipper: Sendable { func zip(_ directory: URL, to file: URL) throws }`（`ditto -c -k --norsrc --noextattr --noqtn`）；`public enum ZipError { case failed(status: Int32, message: String) }`
  - `AppPaths.beforeImport: URL`（`root/before-import`）
  - `public struct ExportManifest: Sendable, Equatable, Codable { static let currentFormatVersion = 1; formatVersion: Int; exportedAt: Date; settings: Settings; packages: [Package]; personalDicts: [String]; phrases: Int; userDB: [String]; struct Package { id, version } }`
  - `public enum TransferError: Error, Equatable, Sendable, CustomStringConvertible { case noSettings, targetExists(String), notAnExport(String), unsupportedFormat(Int), badSettings(String), badContent(String) }`
  - `public struct ExportReport: Sendable, Equatable { file: URL; manifest: ExportManifest; warnings: [String] }`
  - `public struct Exporter: Sendable { init(paths: AppPaths, locations: RimeLocations, userDB: UserDBTransfer?, now: @escaping @Sendable () -> Date = { Date() }); func export(to target: URL, packages: [ExportManifest.Package], overwrite: Bool = false) async throws -> ExportReport }`（`userDB` 为 nil 时不带输入习惯）
  - 测试辅助 `TransferFixtures.Machine`、`machine(withSettings:userDB:running:)`、`settings`、`phrase`、`pyUser`、`snapshot`、`date`

- [ ] **Step 1: 写测试辅助和失败的测试**

`Tests/RimeKitTests/Support/TransferFakes.swift` 末尾加：

```swift
/// 一台假的 Mac：应用数据目录、Rime 目录、假的鼠须管、假的 rime_dict_manager、三个自造包
enum TransferFixtures {
    struct Machine {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let squirrel: FakeSquirrel
        let tool: FakeUserDBTool
        let catalog: Catalog
        let packages: [String: CachedPackage]

        var userDB: UserDBTransfer { UserDBTransfer(tool: tool, squirrel: squirrel, sleep: { _ in }) }

        func deployer(_ compiler: FakeCompiler = FakeCompiler()) -> Deployer {
            Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                     watcher: DeployFixtures.watcher(locations))
        }

        func exporter(userDB: Bool = true) -> Exporter {
            Exporter(paths: paths, locations: locations, userDB: userDB ? self.userDB : nil, now: { TransferFixtures.date })
        }
    }

    static let date = Date(timeIntervalSince1970: 1_800_000_000)
    static let settings = Settings(schemas: ["wb_py", "py"], options: ["wubi": ["pinyinDictionary": "ext"]],
                                   appearance: Appearance(fontPoint: 22))
    static let phrase = Phrase(text: "私人短语", code: "srdy", weight: 1)
    static let pyUser = GenFixtures.dict("py_user", ["私人词条\tsi ren ci tiao\t100"])
    static let snapshot = "# Rime user dictionary export\n#@/db_name\twb_py\n#@/db_type\tuserdb\nni hao \t你好\t0\n"

    static func machine(withSettings: Bool = true, userDB: [String: String] = ["wb_py": snapshot],
                        running: Bool = true) throws -> Machine {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let packages = try GenFixtures.makePackages(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        if withSettings {
            try SettingsStore(paths: paths).save(settings)
            try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
            try Data(pyUser.utf8).write(to: paths.personalDicts.appending(path: "py_user.dict.yaml"))
            try Data((PhraseFile.header + PhraseFile.render([phrase])).utf8).write(to: paths.personalPhrases)
        }
        return Machine(dir: dir, paths: paths, locations: locations,
                       squirrel: FakeSquirrel(locations: locations, running: running),
                       tool: FakeUserDBTool(dbs: userDB), catalog: try GenFixtures.catalog(), packages: packages)
    }

    /// 目录里所有普通文件的相对路径
    static func files(in dir: URL) throws -> Set<String> {
        var result = Set<String>()
        for path in try FileManager.default.subpathsOfDirectory(atPath: dir.path) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dir.appending(path: path).path, isDirectory: &isDir), !isDir.boolValue {
                result.insert(path)
            }
        }
        return result
    }
}
```

`Tests/RimeKitTests/ExporterTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct ExporterTests {
    typealias T = TransferFixtures

    func unzip(_ file: URL, _ m: T.Machine) throws -> URL {
        let out = m.dir.url.appending(path: "unzipped", directoryHint: .isDirectory)
        try Unzipper().unzip(file, into: out)
        return out
    }

    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    @Test func 导出设置个人内容和输入习惯() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let target = m.dir.url.appending(path: "out/e.zip")
        let report = try await m.exporter().export(to: target, packages: [ExportManifest.Package(id: "wubi", version: "v1")])
        let out = try unzip(target, m)
        #expect(try T.files(in: out) == ["manifest.json", "personal/dicts/py_user.dict.yaml", "personal/phrases.txt", "userdb/wb_py.userdb.txt"])
        let manifest = try JSONCoding.decoder.decode(ExportManifest.self, from: Data(contentsOf: out.appending(path: "manifest.json")))
        #expect(manifest == report.manifest)
        #expect(manifest == ExportManifest(formatVersion: 1, exportedAt: T.date, settings: T.settings,
                                           packages: [ExportManifest.Package(id: "wubi", version: "v1")],
                                           personalDicts: ["py_user.dict.yaml"], phrases: 1, userDB: ["wb_py"]))
        #expect(try read(out.appending(path: "personal/dicts/py_user.dict.yaml")) == T.pyUser)
        #expect(PhraseFile.parse(try read(out.appending(path: "personal/phrases.txt"))) == [T.phrase])
        #expect(try read(out.appending(path: "userdb/wb_py.userdb.txt")) == T.snapshot)
        #expect(m.squirrel.calls == ["quit", "launch"])
        #expect(report.warnings.isEmpty)
    }

    @Test func 不带输入习惯() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let target = m.dir.url.appending(path: "e.zip")
        let report = try await m.exporter(userDB: false).export(to: target, packages: [])
        #expect(report.manifest.userDB == [])
        #expect(!(try T.files(in: try unzip(target, m)).contains { $0.hasPrefix("userdb/") }))
        #expect(m.squirrel.calls == [])
    }

    @Test func 没有设置不能导出() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        await #expect(throws: TransferError.noSettings) {
            try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        }
    }

    @Test func 已有文件不覆盖_除非指定() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let target = m.dir.url.appending(path: "e.zip")
        try Data("旧的".utf8).write(to: target)
        await #expect(throws: TransferError.targetExists(target.path)) {
            try await m.exporter().export(to: target, packages: [])
        }
        _ = try await m.exporter().export(to: target, packages: [], overwrite: true)
        #expect(try T.files(in: try unzip(target, m)).contains("manifest.json"))
    }

    @Test func 个人词库在应用外改过时提醒() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["py_user.dict.yaml": LedgerEntry(sha256: "0", origin: "personal")]).save(m.paths)
        try FileManager.default.createDirectory(at: m.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("外面改过的".utf8).write(to: m.locations.rimeDirectory.appending(path: "py_user.dict.yaml"))
        let report = try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        #expect(report.warnings.contains { $0.contains("py_user.dict.yaml") && $0.contains("--adopt-personal") })
    }

    @Test func 暂存区用完就删() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        _ = try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        #expect(try FileManager.default.contentsOfDirectory(atPath: m.paths.staging.path).isEmpty)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ExporterTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'Exporter' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Packages/Unzipper.swift` 末尾加：

```swift
public enum ZipError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(status: Int32, message: String)

    public var description: String {
        switch self {
        case let .failed(status, message):
            return "打包失败（ditto 退出码 \(status)）：\(message)"
        }
    }
}

/// 用系统自带的 ditto 打包：zip 里直接是目录里的内容；不带资源分支和扩展属性（不然会多出 __MACOSX/，已实测）
public struct Zipper: Sendable {
    public init() {}

    public func zip(_ directory: URL, to file: URL) throws {
        let result = try Shell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", directory.path, file.path])
        guard result.status == 0 else {
            throw ZipError.failed(status: result.status, message: result.stderr)
        }
    }
}
```

`Sources/RimeKit/AppPaths.swift`：`lockFile` 前面加：

```swift
    /// 导入前把应用里原来的设置和个人内容另存在这里（Rime 目录的备份不含这些）
    public var beforeImport: URL { root.appending(path: "before-import", directoryHint: .isDirectory) }
```

`Sources/RimeKit/Transfer/ExportManifest.swift`：

```swift
import Foundation

/// 导出文件里的 manifest.json（设计第 5 节「导出文件」）
public struct ExportManifest: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public struct Package: Sendable, Equatable, Codable {
        public let id: String
        public let version: String

        public init(id: String, version: String) {
            self.id = id
            self.version = version
        }
    }

    public var formatVersion: Int
    public var exportedAt: Date
    public var settings: Settings
    /// 导出时用的上游版本：只用来参考和排查问题，导入时总是下载最新版
    public var packages: [Package]
    /// personal/dicts 里的文件名
    public var personalDicts: [String]
    /// personal/phrases.txt 里的条数
    public var phrases: Int
    /// userdb 里的输入习惯（词典名）
    public var userDB: [String]

    public init(formatVersion: Int, exportedAt: Date, settings: Settings, packages: [Package],
                personalDicts: [String], phrases: Int, userDB: [String]) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.packages = packages
        self.personalDicts = personalDicts
        self.phrases = phrases
        self.userDB = userDB
    }
}

public enum TransferError: Error, Equatable, Sendable, CustomStringConvertible {
    case noSettings
    case targetExists(String)
    case notAnExport(String)
    case unsupportedFormat(Int)
    case badSettings(String)
    case badContent(String)

    public var description: String {
        switch self {
        case .noSettings:
            return "还没有设置，没什么可导出的。先 rimectl takeover 接管已有配置，或 rimectl settings init 选一个起步方案"
        case .targetExists(let path):
            return "\(path) 已经有了。要覆盖就加 --force"
        case .notAnExport(let path):
            return "\(path) 不是 squirrel-macos 的导出文件"
        case .unsupportedFormat(let v):
            return "导出文件的格式版本是 \(v)，这个版本的应用只认识 \(ExportManifest.currentFormatVersion)，请更新应用"
        case .badSettings(let message):
            return "导出文件里的设置用不了：\(message)"
        case .badContent(let message):
            return "导出文件坏了：\(message)"
        }
    }
}
```

`Sources/RimeKit/Transfer/Exporter.swift`：

```swift
import Foundation

public struct ExportReport: Sendable, Equatable {
    public let file: URL
    public let manifest: ExportManifest
    public let warnings: [String]
}

/// 一键导出（设计 6.3）：设置 + personal/ + 输入习惯快照（可选）→ 一个 zip。不放任何上游方案文件
public struct Exporter: Sendable {
    public let paths: AppPaths
    let locations: RimeLocations
    /// nil：不带输入习惯
    let userDB: UserDBTransfer?
    let now: @Sendable () -> Date

    public init(paths: AppPaths, locations: RimeLocations, userDB: UserDBTransfer?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.locations = locations
        self.userDB = userDB
        self.now = now
    }

    public func export(to target: URL, packages: [ExportManifest.Package], overwrite: Bool = false) async throws -> ExportReport {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path), !overwrite { throw TransferError.targetExists(target.path) }
        // 和应用改动互斥：导出输入习惯时要退出鼠须管
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        guard let settings = try SettingsStore(paths: paths).load() else { throw TransferError.noSettings }
        let personal = try PersonalContent.load(from: paths)

        let work = paths.staging.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        let content = work.appending(path: "content", directoryHint: .isDirectory)
        let dicts = content.appending(path: "personal/dicts", directoryHint: .isDirectory)
        try fm.createDirectory(at: dicts, withIntermediateDirectories: true)
        for url in personal.dicts {
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: dicts.appending(path: url.lastPathComponent))
        }
        if !personal.phrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(personal.phrases)).utf8)
                .write(to: content.appending(path: "personal/phrases.txt"))
        }

        var warnings: [String] = []
        let ledger = try Ledger.load(paths)
        let edited = ledger.externalChanges(in: locations.rimeDirectory).compactMap { change -> String? in
            guard case .modified(let path) = change, ledger.entries[path]?.origin == FileOrigin.personal.ledgerValue else { return nil }
            return path
        }
        if !edited.isEmpty {
            warnings.append("Rime 目录里的 \(edited.joined(separator: "、")) 在应用外改过，导出的是应用里保存的版本。要带上外面的修改，先运行 rimectl apply --adopt-personal")
        }

        let userDBNames = try await userDB?.exportAll(into: content.appending(path: "userdb", directoryHint: .isDirectory)) ?? []
        let manifest = ExportManifest(formatVersion: ExportManifest.currentFormatVersion, exportedAt: now(), settings: settings,
                                      packages: packages, personalDicts: personal.dicts.map(\.lastPathComponent),
                                      phrases: personal.phrases.count, userDB: userDBNames)
        try JSONCoding.encoder.encode(manifest).write(to: content.appending(path: "manifest.json"))

        let zip = work.appending(path: "export.zip")
        try Zipper().zip(content, to: zip)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: zip, to: target)
        return ExportReport(file: target, manifest: manifest, warnings: warnings)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ExporterTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 6 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 一键导出：设置、个人内容、输入习惯快照打成一个 zip

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 读导出文件，检查格式

**Files:**
- Create: `Sources/RimeKit/Transfer/ImportArchive.swift`
- Test: `Tests/RimeKitTests/ImportArchiveTests.swift`

**Interfaces:**
- Consumes: `ExportManifest`、`TransferError`、`Zipper`（任务 3）、`Unzipper`、`RimeDictManager.isValidName`（任务 1）
- Produces: `public struct ImportArchive: Sendable, Equatable { manifest: ExportManifest; personalDicts: [URL]; phrases: [Phrase]; userDB: [String: URL]; warnings: [String]; static func open(_ file: URL, catalog: Catalog, into dir: URL) throws -> ImportArchive }`
  - 解压到 `dir`，不碰 Rime 目录和应用数据
  - 不是 zip、没有 `manifest.json` → `.notAnExport`；格式版本不对 → `.unsupportedFormat`；manifest 读不懂 → `.badContent`；设置用不了（方案不认识等）→ `.badSettings`
  - 只认普通文件：`personal/dicts/*.dict.yaml`、`personal/phrases.txt`、`userdb/<合法名字>.userdb.txt`；别的跳过并写进 `warnings`（隐藏文件不提示）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/ImportArchiveTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct ImportArchiveTests {
    typealias T = TransferFixtures

    func exported(_ m: T.Machine) async throws -> URL {
        let file = m.dir.url.appending(path: "e.zip")
        _ = try await m.exporter().export(to: file, packages: [])
        return file
    }

    /// 把一个目录打成 zip（造各种有问题的导出文件）
    func zip(_ build: (URL) throws -> Void, _ m: T.Machine) throws -> URL {
        let content = m.dir.url.appending(path: "craft-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try build(content)
        let file = m.dir.url.appending(path: "craft-\(UUID().uuidString).zip")
        try Zipper().zip(content, to: file)
        return file
    }

    func open(_ file: URL, _ m: T.Machine) throws -> ImportArchive {
        try ImportArchive.open(file, catalog: m.catalog, into: m.dir.url.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func 读出导出的内容() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let a = try open(try await exported(m), m)
        #expect(a.manifest.settings == T.settings)
        #expect(a.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(try String(contentsOf: a.personalDicts[0], encoding: .utf8) == T.pyUser)
        #expect(a.phrases == [T.phrase])
        #expect(a.userDB.keys.sorted() == ["wb_py"])
        #expect(a.warnings.isEmpty)
    }

    @Test func 不是导出文件() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let text = m.dir.url.appending(path: "x.zip")
        try Data("不是 zip".utf8).write(to: text)
        #expect(throws: TransferError.notAnExport(text.path)) { try open(text, m) }
        let noManifest = try zip({ try Data("a".utf8).write(to: $0.appending(path: "a.txt")) }, m)
        #expect(throws: TransferError.notAnExport(noManifest.path)) { try open(noManifest, m) }
        let missing = m.dir.url.appending(path: "none.zip")
        #expect(throws: TransferError.notAnExport(missing.path)) { try open(missing, m) }
    }

    @Test func 格式版本太新() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let file = try zip({ try Data(#"{"formatVersion": 2}"#.utf8).write(to: $0.appending(path: "manifest.json")) }, m)
        #expect(throws: TransferError.unsupportedFormat(2)) { try open(file, m) }
    }

    @Test func 设置里的方案不认识() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let manifest = ExportManifest(formatVersion: 1, exportedAt: T.date, settings: Settings(schemas: ["nope"]),
                                      packages: [], personalDicts: [], phrases: 0, userDB: [])
        let file = try zip({ try JSONCoding.encoder.encode(manifest).write(to: $0.appending(path: "manifest.json")) }, m)
        do {
            _ = try open(file, m)
            Issue.record("应该报错")
        } catch let TransferError.badSettings(message) {
            #expect(message.contains("nope"))
        }
    }

    @Test func 奇怪的文件跳过() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let good = m.dir.url.appending(path: "good", directoryHint: .isDirectory)
        try Unzipper().unzip(try await exported(m), into: good)
        let fm = FileManager.default
        try Data("笔记".utf8).write(to: good.appending(path: "personal/dicts/notes.txt"))
        try fm.createSymbolicLink(atPath: good.appending(path: "personal/dicts/link.dict.yaml").path, withDestinationPath: "/etc/hosts")
        try fm.createDirectory(at: good.appending(path: "personal/dicts/sub.dict.yaml"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: good.appending(path: "userdb/a b.userdb.txt"))
        try Data("x".utf8).write(to: good.appending(path: "userdb/.DS_Store"))
        let file = m.dir.url.appending(path: "weird.zip")
        try Zipper().zip(good, to: file)
        let a = try open(file, m)
        #expect(a.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(a.userDB.keys.sorted() == ["wb_py"])
        #expect(a.warnings.count == 4, "\(a.warnings)")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ImportArchiveTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'ImportArchive' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Transfer/ImportArchive.swift`：

```swift
import Foundation

/// 解压、检查导出文件。导出文件当作不可信数据：只认需要的几样普通文件
public struct ImportArchive: Sendable, Equatable {
    public let manifest: ExportManifest
    /// 解压后的个人词库，按文件名排序
    public let personalDicts: [URL]
    public let phrases: [Phrase]
    /// 词典名 → 解压后的快照文件
    public let userDB: [String: URL]
    public let warnings: [String]

    /// 解压到 dir，检查格式。不碰 Rime 目录和应用数据
    public static func open(_ file: URL, catalog: Catalog, into dir: URL) throws -> ImportArchive {
        guard FileManager.default.fileExists(atPath: file.path) else { throw TransferError.notAnExport(file.path) }
        do {
            try Unzipper().unzip(file, into: dir)   // ditto 会去掉 ../，不会写到 dir 外面（已实测）
        } catch {
            throw TransferError.notAnExport(file.path)
        }
        let manifestURL = dir.appending(path: "manifest.json")
        guard isRegular(manifestURL), let data = try? Data(contentsOf: manifestURL) else { throw TransferError.notAnExport(file.path) }
        struct Header: Decodable { let formatVersion: Int }
        guard let header = try? JSONCoding.decoder.decode(Header.self, from: data) else { throw TransferError.notAnExport(file.path) }
        guard header.formatVersion == ExportManifest.currentFormatVersion else { throw TransferError.unsupportedFormat(header.formatVersion) }
        let manifest: ExportManifest
        do {
            manifest = try JSONCoding.decoder.decode(ExportManifest.self, from: data)
        } catch {
            throw TransferError.badContent("manifest.json：\(error)")
        }
        do {
            try manifest.settings.validate(catalog)
        } catch {
            throw TransferError.badSettings(String(describing: error))
        }

        var warnings: [String] = []
        var dicts: [URL] = []
        for (name, url) in entries(dir.appending(path: "personal/dicts", directoryHint: .isDirectory)) {
            if name.hasSuffix(".dict.yaml"), isRegular(url) {
                dicts.append(url)
            } else {
                warnings.append("导出文件里的 personal/dicts/\(name) 不是个人词库，跳过")
            }
        }
        var phrases: [Phrase] = []
        let phrasesURL = dir.appending(path: "personal/phrases.txt")
        if FileManager.default.fileExists(atPath: phrasesURL.path) {
            guard isRegular(phrasesURL), let text = try? String(contentsOf: phrasesURL, encoding: .utf8) else {
                throw TransferError.badContent("personal/phrases.txt 读不了")
            }
            phrases = PhraseFile.parse(text)
        }
        var userDB: [String: URL] = [:]
        for (name, url) in entries(dir.appending(path: "userdb", directoryHint: .isDirectory)) {
            let dict = name.hasSuffix(".userdb.txt") ? String(name.dropLast(".userdb.txt".count)) : ""
            if RimeDictManager.isValidName(dict), isRegular(url) {
                userDB[dict] = url
            } else {
                warnings.append("导出文件里的 userdb/\(name) 不是输入习惯快照，跳过")
            }
        }
        return ImportArchive(manifest: manifest, personalDicts: dicts, phrases: phrases, userDB: userDB, warnings: warnings)
    }

    /// 目录里的条目（不含隐藏文件），按名字排序；目录不存在时为空
    static func entries(_ dir: URL) -> [(String, URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { ($0, dir.appending(path: $0)) }
    }

    /// 普通文件（不是目录、不是符号链接）
    static func isRegular(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeRegular
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ImportArchiveTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 5 个测试通过

如果「奇怪的文件跳过」里 `ditto` 打包时跟随了符号链接（zip 里是 `/etc/hosts` 的内容而不是链接）：那它就是普通文件，会被当成个人词库收进来。这时把测试改成直接检查「解压后是符号链接的会跳过」（先解压再在解压目录里造链接，调用拆出来的检查函数），并记一条 Ruling。

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Transfer/ImportArchive.swift Tests/RimeKitTests/ImportArchiveTests.swift
git commit -m "feat: 读导出文件：检查格式，只认需要的普通文件

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 备份可以要求永久保留；保存设置和个人内容提成共用

**Files:**
- Modify: `Sources/RimeKit/Deploy/Deployer.swift`（`ApplyOptions.permanentBackupReason`）
- Create: `Sources/RimeKit/Config/AppDataWriter.swift`
- Modify: `Sources/RimeKit/Takeover/TakeoverApplier.swift`（`save` 改成调用 `AppDataWriter.replace`）
- Test: `Tests/RimeKitTests/DeployerTests.swift`

**Interfaces:**
- Produces:
  - `ApplyOptions.permanentBackupReason: String?`（`init` 加同名参数，默认 nil）：不为空时这次的备份永久保留，说明写它；Rime 目录里没有配置文件时不用永久保留
  - `public enum AppDataWriter { static func replace(settings: Settings, dicts: [URL], phrases: [Phrase], paths: AppPaths) throws }`：换掉整个 `personal/`（个人词库 + 手动短语），最后保存设置

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/DeployerTests.swift` 的 suite 里加（用这个文件已有的准备方法；如果它没有现成的 env，就照 `TakeoverApplierTests.env()` 的写法用 `TransferFixtures.machine()`）：

```swift
    @Test func 可以要求这次的备份永久保留() async throws {
        let m = try TransferFixtures.machine(); defer { m.dir.remove() }
        try FileManager.default.createDirectory(at: m.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("随手记\n".utf8).write(to: m.locations.rimeDirectory.appending(path: "notes.txt"))
        let input = GenerationInput(settings: TransferFixtures.settings, catalog: m.catalog, packages: m.packages,
                                    personal: .empty, textReplacementPhrases: [])
        guard case .applied(let first) = try await m.deployer().apply(input) else { Issue.record("没有写入"); return }
        #expect(first.backup.permanent)   // 第一次应用前：本来就永久保留
        guard case .applied(let second) = try await m.deployer().apply(input, options: ApplyOptions(permanentBackupReason: "导入前")) else {
            Issue.record("没有写入"); return
        }
        #expect(second.backup.permanent)
        #expect(second.backup.reason == "导入前")
        guard case .applied(let third) = try await m.deployer().apply(input) else { Issue.record("没有写入"); return }
        #expect(!third.backup.permanent)
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DeployerTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`extra argument 'permanentBackupReason'`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Deploy/Deployer.swift`：
1. `ApplyOptions` 加属性和参数：

```swift
    /// 不为空时这次的备份永久保留，说明写这个（例如「导入前」）。Rime 目录里没有配置文件时不用永久保留
    public var permanentBackupReason: String?

    public init(overwriteExternalChanges: Bool = false, adoptPersonalChanges: Bool = false, permanentBackupReason: String? = nil) {
        self.overwriteExternalChanges = overwriteExternalChanges
        self.adoptPersonalChanges = adoptPersonalChanges
        self.permanentBackupReason = permanentBackupReason
    }
```

2. 「4. 备份」那两行（`let keep = …`、`let backup = try backups.create(…)`）改成：

```swift
        let keep: Bool
        let reason: String
        if let permanent = options.permanentBackupReason {
            keep = !existing.isEmpty
            reason = permanent
        } else {
            // 永久保留只要一份：还原到第一次应用前再应用时，不再加新的永久备份
            keep = first && !existing.isEmpty && !backups.list().contains(where: \.permanent)
            reason = first ? "第一次应用前" : "应用改动前"
        }
        let backup = try backups.create(from: rime, reason: reason, permanent: keep, ledger: ledger)
```

（删掉原来那行「永久保留只要一份」的注释，它已经挪进 else 里。）

`Sources/RimeKit/Config/AppDataWriter.swift`：

```swift
import Foundation

/// 换掉应用里保存的设置和个人内容（接管、导入时用）
public enum AppDataWriter {
    /// 换掉整个 personal/（个人词库 + 手动短语），最后保存设置：个人内容没存好就不会有设置
    public static func replace(settings: Settings, dicts: [URL], phrases: [Phrase], paths: AppPaths) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: paths.personal.path) { try fm.removeItem(at: paths.personal) }
        try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        for url in dicts {
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: paths.personalDicts.appending(path: url.lastPathComponent))
        }
        if !phrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(phrases)).utf8).write(to: paths.personalPhrases, options: .atomic)
        }
        try SettingsStore(paths: paths).save(settings)
    }
}
```

`Sources/RimeKit/Takeover/TakeoverApplier.swift`：删掉 `static func save(…)`，`afterWrite` 里改成 `try AppDataWriter.replace(settings: settings, dicts: dictFiles, phrases: phrases, paths: paths)`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "DeployerTests|Takeover" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 应用时可以要求备份永久保留；保存设置和个人内容提成 AppDataWriter

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 导入

**Files:**
- Create: `Sources/RimeKit/Transfer/Importer.swift`
- Test: `Tests/RimeKitTests/ImporterTests.swift`

**Interfaces:**
- Consumes: `ImportArchive`（任务 4）、`Exporter`（任务 3）、`UserDBTransfer`（任务 2）、`ApplyOptions.permanentBackupReason`、`AppDataWriter`（任务 5）、`Deployer.apply(_:options:afterWrite:)`
- Produces:
  - `public struct ImportReport: Sendable, Equatable { outcome: ApplyOutcome; previous: URL?; mergedUserDB: [String]; userDBError: String? }`
  - `public struct Importer: Sendable { init(deployer: Deployer, userDB: UserDBTransfer?, now: @escaping @Sendable () -> Date = { Date() }); func run(_ archive: ImportArchive, catalog: Catalog, packages: [String: CachedPackage], textReplacement: [Phrase]) async throws -> ImportReport }`
  - 流程：
    1. 应用里已有设置 → 把原来的设置和个人内容另存成 `before-import/<时间>.zip`（不含输入习惯）。
    2. 走 6.1：覆盖外部改动；备份永久保留，说明写「导入前」；写入成功后、通知鼠须管前保存设置和个人内容。
    3. 写入成功、`userDB` 不为 nil、导出文件里有输入习惯时，合并输入习惯。合并失败不抛出，记在 `userDBError`。

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/ImporterTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct ImporterTests {
    typealias T = TransferFixtures

    /// 在 A 上导出，在 B 上打开
    func archive(for b: T.Machine) async throws -> ImportArchive {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = b.dir.url.appending(path: "from-a.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        return try ImportArchive.open(file, catalog: b.catalog, into: b.dir.url.appending(path: "import", directoryHint: .isDirectory))
    }

    func importer(_ b: T.Machine, _ compiler: FakeCompiler = FakeCompiler()) -> Importer {
        Importer(deployer: b.deployer(compiler), userDB: b.userDB, now: { T.date })
    }

    @Test func 导入到空的新电脑() async throws {
        let b = try T.machine(withSettings: false, userDB: [:], running: false); defer { b.dir.remove() }
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied = report.outcome else { Issue.record("没有写入：\(report.outcome)"); return }
        #expect(report.previous == nil)
        #expect(report.mergedUserDB == ["wb_py"])
        #expect(report.userDBError == nil)
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        let personal = try PersonalContent.load(from: b.paths)
        #expect(personal.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(personal.phrases == [T.phrase])
        #expect(b.tool.dbs["wb_py"] == T.snapshot)
        #expect(b.squirrel.calls.last == "launch")
        #expect(FileManager.default.fileExists(atPath: b.locations.rimeDirectory.appending(path: "wb_py.schema.yaml").path))
    }

    @Test func 原来有设置时先另存一份() async throws {
        let b = try T.machine(); defer { b.dir.remove() }
        try SettingsStore(paths: b.paths).save(Settings(schemas: ["py"]))
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        let previous = try #require(report.previous)
        #expect(previous.deletingLastPathComponent().standardizedFileURL.path == b.paths.beforeImport.standardizedFileURL.path)
        let old = try ImportArchive.open(previous, catalog: b.catalog, into: b.dir.url.appending(path: "old", directoryHint: .isDirectory))
        #expect(old.manifest.settings.schemas == ["py"])
        #expect(old.manifest.userDB == [])
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
    }

    @Test func Rime目录里原有的配置先备份_永久保留() async throws {
        let b = try T.machine(withSettings: false); defer { b.dir.remove() }
        try FileManager.default.createDirectory(at: b.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("随手记\n".utf8).write(to: b.locations.rimeDirectory.appending(path: "notes.txt"))
        let report = try await importer(b).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied(let applied) = report.outcome else { Issue.record("没有写入"); return }
        #expect(applied.backup.permanent)
        #expect(applied.backup.reason == "导入前")
        #expect(FileManager.default.fileExists(atPath: b.locations.rimeDirectory.appending(path: "notes.txt").path))
    }

    @Test func 输入习惯合并不上时配置照样导入() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let locked = T.Machine(dir: b.dir, paths: b.paths, locations: b.locations, squirrel: b.squirrel,
                               tool: FakeUserDBTool(lockedFailures: 99), catalog: b.catalog, packages: b.packages)
        let report = try await importer(locked).run(try await archive(for: locked), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .applied = report.outcome else { Issue.record("没有写入"); return }
        #expect(report.mergedUserDB == [])
        #expect(report.userDBError?.contains("别打字") == true)
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
    }

    @Test func 编译失败时什么都不保存() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        let report = try await importer(b, failing).run(try await archive(for: b), catalog: b.catalog, packages: b.packages, textReplacement: [])
        guard case .compileFailed = report.outcome else { Issue.record("应该编译失败"); return }
        #expect(!FileManager.default.fileExists(atPath: b.paths.settingsFile.path))
        #expect(!FileManager.default.fileExists(atPath: b.paths.personal.path))
        #expect(b.tool.calls == [])
    }

    @Test func 打开了文本替换同步时带上新电脑的文本替换() async throws {
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        var a = try await archive(for: b)
        var manifest = a.manifest
        manifest.settings.textReplacement.sync = true
        a = ImportArchive(manifest: manifest, personalDicts: a.personalDicts, phrases: a.phrases, userDB: a.userDB, warnings: a.warnings)
        let tr = Phrase(text: "新电脑的替换", code: "xdnd", weight: 1)
        _ = try await importer(b).run(a, catalog: b.catalog, packages: b.packages, textReplacement: [tr])
        let phrases = try String(contentsOf: b.locations.rimeDirectory.appending(path: "custom_phrase.txt"), encoding: .utf8)
        #expect(phrases.contains(tr.line))
    }
}
```

（`ImportArchive` 的成员初始化器在测试里用到了：它是 `internal` 的，`@testable import` 能用。）

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ImporterTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'Importer' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Transfer/Importer.swift`：

```swift
import Foundation

public struct ImportReport: Sendable, Equatable {
    public let outcome: ApplyOutcome
    /// 导入前应用里原来的设置和个人内容另存的文件（原来没有设置时为 nil）
    public let previous: URL?
    /// 合并了哪些输入习惯
    public let mergedUserDB: [String]
    /// 输入习惯没合并上的原因（这时配置已经导入好了）
    public let userDBError: String?
}

/// 一键导入（设计 6.4）：另存原来的设置 → 按 6.1 写入导出文件里的配置 → 合并输入习惯
public struct Importer: Sendable {
    let deployer: Deployer
    /// nil：不合并输入习惯
    let userDB: UserDBTransfer?
    let now: @Sendable () -> Date

    public init(deployer: Deployer, userDB: UserDBTransfer?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.deployer = deployer
        self.userDB = userDB
        self.now = now
    }

    public func run(_ archive: ImportArchive, catalog: Catalog, packages: [String: CachedPackage],
                    textReplacement: [Phrase]) async throws -> ImportReport {
        let paths = deployer.paths

        // 1. Rime 目录的备份不含应用里的设置和个人内容：原来有就先另存一份，导错了文件还能找回
        var previous: URL?
        if FileManager.default.fileExists(atPath: paths.settingsFile.path) {
            let file = paths.beforeImport.appending(path: "\(Self.stamp(now())).zip")
            _ = try await Exporter(paths: paths, locations: deployer.locations, userDB: nil, now: now)
                .export(to: file, packages: [], overwrite: true)
            previous = file
        }

        // 2. 走 6.1。导入就是要换成导出文件里的配置：应用外的改动、同名文件都覆盖（先备份，永久保留）。
        //    写好后、通知鼠须管前保存设置和个人内容
        let settings = archive.manifest.settings
        let dicts = archive.personalDicts
        let phrases = archive.phrases
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: PersonalContent(dicts: dicts, phrases: phrases),
                                    textReplacementPhrases: settings.textReplacement.sync ? textReplacement : [])
        let outcome = try await deployer.apply(
            input, options: ApplyOptions(overwriteExternalChanges: true, permanentBackupReason: "导入前"),
            afterWrite: { try AppDataWriter.replace(settings: settings, dicts: dicts, phrases: phrases, paths: paths) })

        // 3. 合并输入习惯（合并，不是覆盖）；合并不上不影响已经导入的配置
        guard case .applied = outcome, let userDB, !archive.userDB.isEmpty else {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], userDBError: nil)
        }
        do {
            let merged = try await userDB.importAll(archive.userDB)
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: merged, userDBError: nil)
        } catch {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], userDBError: String(describing: error))
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ImporterTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 6 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Transfer/Importer.swift Tests/RimeKitTests/ImporterTests.swift
git commit -m "feat: 一键导入：另存原来的设置，按 6.1 写入，合并输入习惯

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `rimectl export`、`rimectl import`

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`
- Test: `Tests/RimeKitTests/RimectlTransferTests.swift`

**Interfaces:**
- Consumes: `Exporter`、`ImportArchive`、`Importer`、`UserDBTransfer`、`RimeDictManager`（任务 1–6）；`printApplyOutcome`、`obtain`、`deployer`（已有）
- Produces:
  - `Rimectl.Context.userDBTool: (any UserDBTool)?`（空就用 `RimeDictManager(locations:)`）
  - `rimectl export <文件> [--no-userdb] [--force]`：没有设置 → 1；文件已存在没加 `--force` → 1；成功 → 0，输出文件路径和各部分条数
  - `rimectl import <文件> [--no-userdb] [--cache-only]`：
    - 先打印导出文件的内容摘要
    - 没装鼠须管 → 1，提示 `rimectl install`、`rimectl activate`
    - 下载最新上游包；设置里同步开着就读文本替换（读不了时提示，继续）
    - 输出和 `apply` 一样；另存了原来的设置时打印路径；合并了的输入习惯；合并失败 → 1，提示再运行一次

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/RimectlTransferTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTransferTests {
    typealias T = TransferFixtures

    struct CLI {
        let machine: T.Machine
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", machine.locations.rimeDirectory.path], context)
        }
    }

    func cli(_ m: T.Machine) -> CLI {
        let output = Output(echo: false)
        let catalog = m.catalog
        var context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: m.paths, output: output,
            locations: m.locations, compiler: FakeCompiler(), squirrel: m.squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in })
        context.userDBTool = m.tool
        context.textReplacements = { [] }
        return CLI(machine: m, output: output, context: context)
    }

    @Test func 导出再导入到另一台() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let b = try T.machine(withSettings: false, userDB: [:], running: false); defer { b.dir.remove() }
        let file = b.dir.url.appending(path: "e.zip")
        let ca = cli(a)
        #expect(await ca.run(["export", file.path]) == 0)
        #expect(ca.output.text.contains("已导出"))
        #expect(ca.output.text.contains("输入习惯 1 份"))
        let cb = cli(b)
        #expect(await cb.run(["import", file.path, "--cache-only"]) == 0)
        #expect(cb.output.text.contains("部署完成"))
        #expect(cb.output.text.contains("已合并输入习惯：wb_py"))
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
        #expect(try PersonalContent.load(from: b.paths).phrases == [T.phrase])
        #expect(b.tool.dbs["wb_py"] == T.snapshot)
    }

    @Test func 输出里没有个人内容() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        let c = cli(a)
        #expect(await c.run(["export", file.path]) == 0)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 0)
        for secret in ["私人短语", "私人词条", "你好"] {
            #expect(!c.output.text.contains(secret), "输出里有「\(secret)」")
        }
    }

    @Test func 不带输入习惯() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        let c = cli(a)
        #expect(await c.run(["export", file.path, "--no-userdb"]) == 0)
        #expect(a.tool.calls == [])
        #expect(a.squirrel.calls == [])
    }

    @Test func 已有文件要加force() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        try Data("旧".utf8).write(to: file)
        let c = cli(a)
        #expect(await c.run(["export", file.path]) == 1)
        #expect(c.output.text.contains("--force"))
        #expect(await c.run(["export", file.path, "--force"]) == 0)
    }

    @Test func 没有设置不能导出() async throws {
        let a = try T.machine(withSettings: false); defer { a.dir.remove() }
        let c = cli(a)
        #expect(await c.run(["export", a.dir.url.appending(path: "e.zip").path]) == 1)
        #expect(c.output.text.contains("还没有设置"))
    }

    @Test func 不是导出文件() async throws {
        let b = try T.machine(withSettings: false); defer { b.dir.remove() }
        let file = b.dir.url.appending(path: "x.zip")
        try Data("不是".utf8).write(to: file)
        let c = cli(b)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 1)
        #expect(c.output.text.contains("不是 squirrel-macos 的导出文件"))
    }

    @Test func 没装鼠须管时先装() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        #expect(await cli(a).run(["export", file.path]) == 0)
        try FileManager.default.removeItem(at: a.locations.squirrelApp)
        let c = cli(a)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 1)
        #expect(c.output.text.contains("rimectl install"))
    }

    @Test func 输入习惯合并不上时提示再运行一次() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        #expect(await cli(a).run(["export", file.path]) == 0)
        let b = try T.machine(withSettings: false, userDB: [:]); defer { b.dir.remove() }
        let locked = T.Machine(dir: b.dir, paths: b.paths, locations: b.locations, squirrel: b.squirrel,
                               tool: FakeUserDBTool(lockedFailures: 99), catalog: b.catalog, packages: b.packages)
        let c = cli(locked)
        #expect(await c.run(["import", file.path, "--cache-only"]) == 1)
        #expect(c.output.text.contains("再运行一次 rimectl import"))
        #expect(try SettingsStore(paths: b.paths).load() == T.settings)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RimectlTransferTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`value of type 'Rimectl.Context' has no member 'userDBTool'`

- [ ] **Step 3: 实现**

`Sources/rimectl/Rimectl.swift`：

1. `Context` 最后加：

```swift
        /// 空就用鼠须管自带的 rime_dict_manager
        var userDBTool: (any UserDBTool)? = nil
```

2. `usage` 里 `rimectl takeover …` 那一行后面加：

```
      rimectl export <文件> [--no-userdb] [--force]           把设置、个人内容、输入习惯打成一个文件（--force 覆盖已有文件）
      rimectl import <文件> [--no-userdb] [--cache-only]      从导出文件还原：下载最新上游包、写入配置、合并输入习惯
```

3. 参数变量加 `var noUserDB = false`，`switch args[i]` 里加：

```swift
            case "--no-userdb":
                noUserDB = true
                i += 1
```

4. `switch command` 里 `case "takeover":` 后面加：

```swift
            case "export":
                return try await export(Array(positional.dropFirst()), includeUserDB: !noUserDB, force: force,
                                        paths: paths, locations: locations, context)
            case "import":
                return try await importCommand(Array(positional.dropFirst()), includeUserDB: !noUserDB, cacheOnly: cacheOnly,
                                               paths: paths, locations: locations, context)
```

5. 新增（放在 `takeover` 函数后面）：

```swift
    private static func userDB(_ locations: RimeLocations, _ context: Context) -> UserDBTransfer {
        UserDBTransfer(tool: context.userDBTool ?? RimeDictManager(locations: locations),
                       squirrel: context.squirrel ?? SquirrelControl(locations: locations), sleep: context.sleep)
    }

    private static func export(_ args: [String], includeUserDB: Bool, force: Bool, paths: AppPaths, locations: RimeLocations,
                               _ context: Context) async throws -> Int32 {
        let out = context.output
        guard args.count == 1 else { out.error(usage); return 2 }
        let target = URL(fileURLWithPath: args[0])
        guard let settings = try SettingsStore(paths: paths).load() else {
            out.error(TransferError.noSettings.description)
            return 1
        }
        let catalog = try context.catalog()
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        let versions = try settings.requiredPackages(catalog).compactMap { spec in
            store.latestCached(for: spec).map { ExportManifest.Package(id: spec.id, version: $0.info.version) }
        }
        if includeUserDB { out.line("导出输入习惯时会暂时退出鼠须管，几秒后自动启动") }
        let exporter = Exporter(paths: paths, locations: locations, userDB: includeUserDB ? userDB(locations, context) : nil)
        let report = try await exporter.export(to: target, packages: versions, overwrite: force)
        for warning in report.warnings { out.line("注意：\(warning)") }
        let m = report.manifest
        out.line("已导出到 \(report.file.path)")
        out.line("方案 \(m.settings.schemas.count) 个，个人词库 \(m.personalDicts.count) 个，手动短语 \(m.phrases) 条，输入习惯 \(m.userDB.count) 份（文本替换生成的短语不导出）")
        return 0
    }

    private static func importCommand(_ args: [String], includeUserDB: Bool, cacheOnly: Bool, paths: AppPaths,
                                      locations: RimeLocations, _ context: Context) async throws -> Int32 {
        let out = context.output
        guard args.count == 1 else { out.error(usage); return 2 }
        let catalog = try context.catalog()
        let work = paths.staging.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = try ImportArchive.open(URL(fileURLWithPath: args[0]), catalog: catalog, into: work)
        let settings = archive.manifest.settings
        out.line("导出时间：\(archive.manifest.exportedAt.formatted(date: .numeric, time: .standard))")
        out.line("方案 \(settings.schemas.count) 个，个人词库 \(archive.personalDicts.count) 个，手动短语 \(archive.phrases.count) 条，输入习惯 \(archive.userDB.count) 份")
        for warning in archive.warnings { out.line("注意：\(warning)") }
        guard locations.squirrelInstalled else {
            out.error("还没装鼠须管。先运行 rimectl install 安装，再 rimectl activate 添加输入法，然后再导入")
            return 1
        }
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        var textReplacement: [Phrase] = []
        if settings.textReplacement.sync {
            do {
                textReplacement = try context.textReplacements()
            } catch {
                out.line("注意：\(error)。这次先不带文本替换的短语")
            }
        }
        if includeUserDB, !archive.userDB.isEmpty { out.line("合并输入习惯时会暂时退出鼠须管，几秒后自动启动") }
        let importer = Importer(deployer: deployer(paths: paths, locations: locations, context),
                                userDB: includeUserDB ? userDB(locations, context) : nil)
        let report = try await importer.run(archive, catalog: catalog, packages: packages, textReplacement: textReplacement)
        if let previous = report.previous { out.line("应用里原来的设置和个人内容另存在：\(previous.path)") }
        let code = printApplyOutcome(report.outcome, out)
        if !report.mergedUserDB.isEmpty { out.line("已合并输入习惯：\(report.mergedUserDB.joined(separator: "、"))") }
        if let error = report.userDBError {
            out.error("输入习惯没有合并上：\(error)。配置已经导入好了；可以再运行一次 rimectl import（配置不会重复写，输入习惯是合并）")
            return 1
        }
        return code
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "Rimectl" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/rimectl/Rimectl.swift Tests/RimeKitTests/RimectlTransferTests.swift
git commit -m "feat: rimectl export、rimectl import

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 测试机里实测：`squirrel-dev` 导出，新克隆的 Mac 导入

**Files:**
- Create: `docs/phase6-vm-log.md`

**Interfaces:**
- Consumes: `rimectl export`、`rimectl import`（任务 7）；`rimectl install`、`activate`（阶段 4）
- Produces: 实测记录；发现的问题按 TDD 修（先写用假替身的失败测试）

先编译：`swift build 2>&1 | tail -1`。下面 `vmrun 机器 参数…` 在那台测试机的桌面会话里跑 rimectl：

```bash
vmrun() { local vm=$1; shift; ./tools/vm/vm.sh ssh "$vm" "sudo launchctl asuser \$(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' $*"; }
```

- [ ] **Step 1: 在 `squirrel-dev` 里先打几个字，留下输入习惯**

用 AskUserQuestion 请用户在 `squirrel-dev` 里（雾凇全拼）打 `shijian`，选**第三个**候选，重复 3 次；记下选的是哪个词。

- [ ] **Step 2: 导出**

```bash
vmrun squirrel-dev export "'/Volumes/My Shared Files/project/.build/phase6-export.zip'" --force --data-dir /tmp/rk
./tools/vm/vm.sh ssh squirrel-dev 'pgrep -lf Squirrel'
unzip -l .build/phase6-export.zip
```

Expected：
- 输出「已导出到 …」「输入习惯 N 份」（N ≥ 1，至少有 `rime_ice`）。
- 导出后鼠须管又在运行。
- zip 里只有 `manifest.json`、`personal/…`、`userdb/*.userdb.txt`。

测试机写不了共享文件夹时：导出到测试机的 `/tmp/phase6-export.zip`，再用 `./tools/vm/vm.sh ssh squirrel-dev 'cat /tmp/phase6-export.zip' > .build/phase6-export.zip` 拷出来，记一条说明。

- [ ] **Step 3: 新克隆一台，装鼠须管、添加输入法**

```bash
./tools/vm/vm.sh new squirrel-import
```

请用户在窗口里登录桌面，然后：

```bash
vmrun squirrel-import install
vmrun squirrel-import activate
```

`activate` 等待时请用户在系统设置里添加鼠须管。

- [ ] **Step 4: 导入**

```bash
vmrun squirrel-import import "'/Volumes/My Shared Files/project/.build/phase6-export.zip'" --data-dir /tmp/rk
```

Expected：导出文件摘要、「部署完成」、「已合并输入习惯：rime_ice…」，退出码 0；`pgrep -lf Squirrel` 有进程。

- [ ] **Step 5: 用户检查**

用 AskUserQuestion 请用户在 `squirrel-import` 里检查：
- 雾凇全拼能打字：`nihao` → 你好。
- 外观和 `squirrel-dev` 一样：候选字 24 号，每页 7 个。
- `shijian` 的第一个候选是步骤 1 里选的那个词（输入习惯过来了）。

- [ ] **Step 6: 再导入一次（幂等），然后删掉测试机**

```bash
vmrun squirrel-import import "'/Volumes/My Shared Files/project/.build/phase6-export.zip'" --data-dir /tmp/rk
./tools/vm/vm.sh rm squirrel-import
rm -f .build/phase6-export.zip
```

Expected：第二次「写入 0 个文件」，并打印「应用里原来的设置和个人内容另存在：…」。

- [ ] **Step 7: 写记录，提交**

`docs/phase6-vm-log.md`：按步骤写关键输出（不写短语、词库、输入习惯的内容，只写条数和词典名）、用户检查结果、发现的问题和怎么修的。

```bash
git add docs/phase6-vm-log.md
git commit -m "docs: 阶段 6 测试机实测记录（导出、在新电脑上导入）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 更新文档

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（第 5 节「导出文件」、6.3、6.4）
- Modify: `docs/verified-facts.md`（输入习惯一节加实测；加 `ditto` 打包）
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`、`CLAUDE.md`、`README.md`

- [ ] **Step 1: 设计文档**

第 5 节「导出文件」的目录树改成：

```
manifest.json     # 格式版本、导出时间、settings、导出时的上游版本、各部分条数
personal/
  dicts/          # 个人词库 *.dict.yaml
  phrases.txt     # 手动短语
userdb/           # 输入习惯快照 <词典名>.userdb.txt（rime_dict_manager --export，可选，默认带上）
```

6.3 末尾加一段：

```markdown
做法（阶段 6 定下）：zip 用系统自带的 `ditto -c -k --norsrc --noextattr --noqtn` 打包（不会多出 `__MACOSX/`）。输入习惯用 `rime_dict_manager --export`，在 Rime 目录里运行；被占着就再退出一次鼠须管重试，最多 3 次；鼠须管原来在运行的，导完再启动。命令行是 `rimectl export 文件 [--no-userdb]`。
```

6.4 末尾加一段：

```markdown
做法（阶段 6 定下）：
- 导出文件当作不可信数据：只认 `manifest.json`、`personal/dicts/*.dict.yaml`、`personal/phrases.txt`、`userdb/<名字>.userdb.txt` 这些普通文件，别的跳过并提示。
- 应用里原来有设置时，先把原来的设置和个人内容另存成 `before-import/<时间>.zip`（Rime 目录的备份不含这些）。
- 写入时覆盖应用外的改动和同名文件；这次的备份永久保留，说明「导入前」；写好后、通知鼠须管前保存设置和个人内容。
- 输入习惯合并不上时，配置照样导入完成，提示再导入一次（配置不会重复写，输入习惯是合并）。
- 命令行 `rimectl import 文件` 要求先装好鼠须管（`rimectl install`、`rimectl activate`）；应用里把这几步串成一键（阶段 8）。
```

- [ ] **Step 2: 已验证的事实**

`docs/verified-facts.md`「输入习惯：rime_dict_manager」的表格加两行：

```markdown
| 目录里还没有这个输入习惯数据库时，`--import` 能导入，自动新建 `<名字>.userdb`（新电脑上还没打过字也能合并） | 实测（宿主机临时目录，2026-10-15） |
| 同一个快照导入两次，再导出和第一次完全一样 | 实测（宿主机临时目录，2026-10-15） |
```

再在第 6 节（新 Mac 上有什么）表格或合适位置加一行：

```markdown
| `ditto -c -k --norsrc --noextattr --noqtn 目录 文件.zip` 打出的包干净（`--sequesterRsrc` 会多出 `__MACOSX/`）；`ditto -x -k` 解压时去掉条目里的 `../`，不会写到目标目录外面 | 实测（宿主机，2026-10-15） |
```

任务 8 有新发现也写进来。

- [ ] **Step 3: 路线图、CLAUDE.md、README**

- 路线图阶段 6 那一行成果末尾加「（已完成，2026-10-15）」，并写上命令 `rimectl export` / `rimectl import`。
- `CLAUDE.md` 第一段的阶段状态改成「阶段 0–6 已完成（…；接管已有配置；一键导出导入），下一步写阶段 7 的计划」；测试机一节加一句：`rimectl export/import` 也要用桌面会话（要退出、启动鼠须管）。
- `README.md` 里「接管已有配置」那一行后面加：`- 导出导入：rimectl export 文件、rimectl import 文件（会暂时退出鼠须管合并输入习惯，只在测试机里做）`（命令部分用反引号）。

- [ ] **Step 4: 检查，提交**

```bash
grep -n "阶段 6 定下" docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 6 完成：导出导入的做法写进设计，更新事实、路线图和说明

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

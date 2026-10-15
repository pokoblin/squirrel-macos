# 阶段 7：文本替换同步 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户在「系统设置 → 键盘 → 文本替换」里加的条目能变成鼠须管的自定义短语，有变化时能看出来（新增几条、删掉几条），用户同意后同步（设计 6.5）。命令行：`rimectl textreplacement status | sync | off`；`rimectl doctor` 也会提示有没有没同步的变化。

**Architecture:** 读取在阶段 5 已经有了（`TextReplacementReader`）。本阶段补齐三块：
- 读的时候把跳过的条目按原因数出来（只记条数）。
- `TextReplacementSync`：记下「上次同步用了哪些条目」，只存每一条的哈希；拿现在的文本替换和记录比，数出新增、删掉了几条。
- 所有会写入 Rime 目录的流程（应用、接管、导入）在写好后更新这份记录；导出时把记录去掉。

**Tech Stack:** Swift 6.4、Swift Testing、系统自带 SQLite（只读）、CryptoKit（已有的 `Hashing`）。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 5 节 `settings.json`「文本替换」、导出文件；5.1 第 7 条；6.5；7 「文本替换数据库读不了」）；事实 [docs/verified-facts.md](../../verified-facts.md) 第 5 节；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## 本阶段要定的事（计划里的做法，请确认）

| # | 问题 | 计划里的做法 | 理由 |
|---|---|---|---|
| 1 | 「有 N 条变化」怎么数 | 设置里除了整体哈希，再存**每一条的哈希**（短语<Tab>编码 的 SHA-256，排好序）。和现在的比：新增几条、删掉几条；改了内容算一删一增 | 设计说只存哈希；只有整体哈希只能知道「变了」，数不出几条 |
| 2 | 每条的哈希算不算隐私 | 只留在本机的 `settings.json`；**导出时去掉**（整体哈希和每条的哈希都去掉），导入后第一次写入时重新记 | 短短语的哈希可以被猜出来；文本替换本来就不导出 |
| 3 | 改别的设置时要不要带上最新的文本替换 | 同步开着时，**任何一次写入**（`apply`、接管、导入）都带上当前的文本替换，并更新记录；不再单独问 | 不然得把上次的文本替换内容存下来才能「只用旧的」，违反只存哈希；用户打开同步就是要跟着变 |
| 4 | 有些条目用不了 | 读的时候分两类数出来：快捷码里有数字、符号（Rime 里打不出来）；内容是空的、有换行或 Tab、以 `#` 开头（短语文件放不下）。只显示条数 | 让用户知道为什么某几条没出现 |
| 5 | 命令行怎么用 | `rimectl textreplacement status`（只读：能用几条、跳过几条、和上次比有没有变化）；`sync`（打开同步并应用）；`off`（关掉同步并应用，去掉文本替换生成的短语） | 应用界面（阶段 8）里对应「检查」「同步」按钮和开关 |
| 6 | 环境检查 | 同步开着时，`rimectl doctor` 多一项「文本替换」：一样 → 正常；有变化或还没同步过 → 注意，提示 `rimectl textreplacement sync`；读不了 → 注意 | 设计 6.5：打开应用时检查 |
| 7 | 读不了数据库时 | `status`、`sync` 报错退出，说明原因和去哪检查权限；`apply` 同步开着时也报错（不悄悄去掉文本替换的短语） | 设计第 7 节 |

## Global Constraints

- 宿主机**不碰** `~/Library/Rime`、`/Library/Input Methods`、输入法启用状态，**不读宿主机的文本替换数据库**（测试用自造的 SQLite 库或假的读取函数）。
- 真实的同步只在测试机 `squirrel-dev` 里做；在系统设置里加、删文本替换条目，以及打字检查，由用户做。测完把测试机还原（关掉同步）。
- 隐私：文本替换的内容只在生成 `custom_phrase.txt` 时用，**不写进设置、日志、输出、导出文件**；设置里只存哈希；输出只写条数。
- 文本替换生成的短语默认不导出（阶段 6 已做）；本阶段再保证导出文件里也没有它们的哈希。
- 只读打开 `TextReplacements.db`（阶段 5 已做）。
- 用简单直白的中文写错误信息和命令行输出。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 用户在系统设置里加、改、删文本替换后，`status` 和 `doctor` 能看出变化，`sync` 后鼠须管里打得出新的（任务 4、5 有测试，任务 6 实测）。
2. 同步开着时改别的设置（`apply`）、接管、导入以后，再看 `status` 应该是「和上次同步时一样」（任务 3、4 有测试）。
3. 文本替换的内容、哈希都不出现在输出和导出文件里（任务 3、4 有测试）。
4. 关掉同步后，文本替换生成的短语从 Rime 目录里去掉，手动短语还在（任务 4 有测试）。
5. 读不了文本替换数据库时，不会悄悄去掉已经同步的短语（任务 4 有测试）。

---

## 文件结构

```
Sources/RimeKit/
  TextReplacement/TextReplacementReader.swift   # snapshot()：能用的 + 跳过的条数
  TextReplacement/TextReplacementSync.swift     # 新：每条哈希、变化、记录
  Config/Settings.swift                         # TextReplacementSettings.syncedEntries
  Takeover/TakeoverApplier.swift                # 保存时记下文本替换
  Transfer/Importer.swift                       # 同上
  Transfer/Exporter.swift                       # 导出时去掉记录
  Install/Doctor.swift                          # 文本替换一项
Sources/rimectl/Rimectl.swift                   # textreplacement 命令；apply 时更新记录；Context 改用 snapshot
Tests/RimeKitTests/
  TextReplacementReaderTests.swift
  TextReplacementSyncTests.swift
  TakeoverApplierTests.swift、ImporterTests.swift、ExporterTests.swift
  RimectlTextReplacementTests.swift
  RimectlTakeoverTests.swift、RimectlTransferTests.swift（Context 字段改名）
  DoctorTests.swift
docs/phase7-vm-log.md
```

---

### Task 1: 读文本替换时数出跳过的条目

**Files:**
- Modify: `Sources/RimeKit/TextReplacement/TextReplacementReader.swift`
- Test: `Tests/RimeKitTests/TextReplacementReaderTests.swift`

**Interfaces:**
- Produces:
  - `public struct TextReplacementSnapshot: Sendable, Equatable { usable: [Phrase]; badShortcut: Int; badPhrase: Int; init(usable:badShortcut:badPhrase:) }`
  - `TextReplacementReader.snapshot() throws -> TextReplacementSnapshot`；`read()` 改成返回 `snapshot().usable`（行为不变）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/TextReplacementReaderTests.swift` 的 suite 里加：

```swift
    @Test func 数出跳过的条目() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try TextReplacementFixtures.makeDatabase(db, [
            ("ok", "好", 0),
            ("a1", "带数字", 0),        // 快捷码不只是字母
            ("x-y", "带符号", 0),
            ("hh", "换\n行", 0),        // 内容放不进短语文件
            ("jh", "#开头", 0),
            ("kk", "", 0),
            ("sc", "删掉了", 1),        // 删掉的不算
        ])
        let s = try TextReplacementReader(database: db).snapshot()
        #expect(s == TextReplacementSnapshot(usable: [Phrase(text: "好", code: "ok", weight: 1)], badShortcut: 2, badPhrase: 3))
    }

    @Test func 没有数据库时是空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try TextReplacementReader(database: dir.url.appending(path: "none.db")).snapshot()
                == TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0))
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TextReplacementReaderTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'TextReplacementSnapshot'`

- [ ] **Step 3: 实现**

`Sources/RimeKit/TextReplacement/TextReplacementReader.swift`：
1. `TextReplacementError` 后面加：

```swift
/// 一次读到的文本替换：能用的条目，和跳过的条数（只记条数，不记内容）
public struct TextReplacementSnapshot: Sendable, Equatable {
    /// 能在 Rime 里打出来的，按快捷码排序；编码是小写的快捷码，权重都是 1
    public let usable: [Phrase]
    /// 快捷码里有数字、符号等（Rime 里打不出来）
    public let badShortcut: Int
    /// 内容是空的、有换行或 Tab、以 # 开头（短语文件里放不下）
    public let badPhrase: Int

    public init(usable: [Phrase], badShortcut: Int, badPhrase: Int) {
        self.usable = usable
        self.badShortcut = badShortcut
        self.badPhrase = badPhrase
    }
}
```

2. `query` 改成只按删除标记和空值过滤，能不能用在 Swift 里判断（这样能数出跳过的条数）：

```swift
    static let query = """
        SELECT ZPHRASE, ZSHORTCUT
        FROM ZTEXTREPLACEMENTENTRY
        WHERE (ZWASDELETED = 0 OR ZWASDELETED IS NULL)
          AND ZSHORTCUT IS NOT NULL AND ZPHRASE IS NOT NULL AND ZSHORTCUT <> ''
        ORDER BY lower(ZSHORTCUT), ZPHRASE
        """
```

3. 原来的 `public func read() throws -> [Phrase] { … }` 整个换成：

```swift
    /// 能用的条目（没有数据库文件时为空）
    public func read() throws -> [Phrase] {
        try snapshot().usable
    }

    /// 没有数据库文件时为空（当作没有文本替换）
    public func snapshot() throws -> TextReplacementSnapshot {
        guard FileManager.default.fileExists(atPath: database.path) else {
            return TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0)
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "打不开"
            sqlite3_close(db)
            throw TextReplacementError.cannotOpen(message)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, Self.query, -1, &statement, nil) == SQLITE_OK else {
            throw TextReplacementError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        var usable: [Phrase] = []
        var badShortcut = 0
        var badPhrase = 0
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw TextReplacementError.queryFailed(String(cString: sqlite3_errmsg(db))) }
            guard let text = sqlite3_column_text(statement, 0), let code = sqlite3_column_text(statement, 1) else { continue }
            let shortcut = String(cString: code)
            // 快捷码只有字母才能在 Rime 里打出来（verified-facts 第 5 节）
            guard shortcut.allSatisfy({ $0.isASCII && $0.isLetter }) else {
                badShortcut += 1
                continue
            }
            let phrase = Phrase(text: String(cString: text), code: shortcut.lowercased(), weight: 1)
            guard phrase.isValid else {
                badPhrase += 1
                continue
            }
            usable.append(phrase)
        }
        return TextReplacementSnapshot(usable: usable, badShortcut: badShortcut, badPhrase: badPhrase)
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TextReplacementReaderTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 6 个测试通过（原来的 4 个不变）

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/TextReplacement/TextReplacementReader.swift Tests/RimeKitTests/TextReplacementReaderTests.swift
git commit -m "feat: 读文本替换时数出跳过的条目（快捷码打不出、内容放不下）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 同步记录：每条的哈希、数出变化

**Files:**
- Modify: `Sources/RimeKit/Config/Settings.swift`（`TextReplacementSettings.syncedEntries`）
- Create: `Sources/RimeKit/TextReplacement/TextReplacementSync.swift`
- Test: `Tests/RimeKitTests/TextReplacementSyncTests.swift`

**Interfaces:**
- Produces:
  - `TextReplacementSettings.syncedEntries: [String]?`（`init(sync:lastSyncedHash:syncedEntries:)`，新参数默认 nil；旧的 `settings.json` 没有这个键也能读）
  - `public enum TextReplacementSync { static func entryHashes(_ phrases: [Phrase]) -> [String]; static func hash(_ phrases: [Phrase]) -> String; static func changes(_ current: [Phrase], since: TextReplacementSettings) -> Changes?; struct Changes { added: Int; removed: Int; isEmpty: Bool } }`
  - `Settings.recordingTextReplacement(_ phrases: [Phrase]) -> Settings`：同步开着时记下这些条目（整体哈希 + 每条哈希），关着时清掉记录
  - `Settings.withoutTextReplacementRecord: Settings`：去掉记录（导出用）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/TextReplacementSyncTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TextReplacementSyncTests {
    let a = Phrase(text: "替换甲", code: "tha", weight: 1)
    let b = Phrase(text: "替换乙", code: "thb", weight: 1)
    let c = Phrase(text: "替换丙", code: "thc", weight: 1)

    @Test func 每条哈希不看权重和顺序_重复的只算一条() {
        let heavier = Phrase(text: a.text, code: a.code, weight: 9)
        #expect(TextReplacementSync.entryHashes([a, b]) == TextReplacementSync.entryHashes([b, heavier, a]))
        #expect(TextReplacementSync.entryHashes([a, b]).count == 2)
        #expect(TextReplacementSync.hash([a, b]) == TextReplacementSync.hash([b, a]))
        #expect(TextReplacementSync.hash([a]) != TextReplacementSync.hash([a, b]))
    }

    @Test func 哈希里看不出内容() {
        let joined = TextReplacementSync.entryHashes([a]).joined() + TextReplacementSync.hash([a])
        #expect(!joined.contains("替换甲"))
        #expect(!joined.contains("tha"))
    }

    @Test func 数出新增和删掉的条数() {
        var s = Settings(schemas: ["py"])
        s.textReplacement.sync = true
        let synced = s.recordingTextReplacement([a, b]).textReplacement
        #expect(TextReplacementSync.changes([a, b], since: synced) == .init(added: 0, removed: 0))
        #expect(TextReplacementSync.changes([a, b], since: synced)?.isEmpty == true)
        #expect(TextReplacementSync.changes([a, b, c], since: synced) == .init(added: 1, removed: 0))
        #expect(TextReplacementSync.changes([a], since: synced) == .init(added: 0, removed: 1))
        // 改了内容：一删一增
        let edited = Phrase(text: "替换乙改", code: b.code, weight: 1)
        #expect(TextReplacementSync.changes([a, edited], since: synced) == .init(added: 1, removed: 1))
    }

    @Test func 从没同步过时没有变化可比() {
        #expect(TextReplacementSync.changes([a], since: TextReplacementSettings(sync: true)) == nil)
    }

    @Test func 同步关着时清掉记录() {
        var s = Settings(schemas: ["py"])
        s.textReplacement.sync = true
        var recorded = s.recordingTextReplacement([a])
        #expect(recorded.textReplacement.syncedEntries == TextReplacementSync.entryHashes([a]))
        #expect(recorded.textReplacement.lastSyncedHash == TextReplacementSync.hash([a]))
        recorded.textReplacement.sync = false
        let off = recorded.recordingTextReplacement([a])
        #expect(off.textReplacement == TextReplacementSettings(sync: false))
    }

    @Test func 导出用的设置去掉记录() {
        var s = Settings(schemas: ["py"])
        s.textReplacement.sync = true
        let stripped = s.recordingTextReplacement([a]).withoutTextReplacementRecord
        #expect(stripped.textReplacement == TextReplacementSettings(sync: true))
    }

    @Test func 旧的设置文件没有每条哈希也能读() throws {
        let json = #"{"formatVersion":1,"schemas":["py"],"options":{},"appearance":{},"textReplacement":{"sync":true,"lastSyncedHash":"x"},"preservedPatches":{}}"#
        let s = try JSONCoding.decoder.decode(Settings.self, from: Data(json.utf8))
        #expect(s.textReplacement == TextReplacementSettings(sync: true, lastSyncedHash: "x"))
        #expect(s.textReplacement.syncedEntries == nil)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TextReplacementSyncTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'TextReplacementSync'`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Config/Settings.swift`：`TextReplacementSettings` 改成：

```swift
public struct TextReplacementSettings: Sendable, Equatable, Codable {
    public var sync: Bool
    /// 上次同步时文本替换内容的哈希（只存哈希，不存内容）
    public var lastSyncedHash: String?
    /// 上次同步时每一条的哈希（排好序），用来数有几条变化；旧的设置文件里没有
    public var syncedEntries: [String]?

    public init(sync: Bool = false, lastSyncedHash: String? = nil, syncedEntries: [String]? = nil) {
        self.sync = sync
        self.lastSyncedHash = lastSyncedHash
        self.syncedEntries = syncedEntries
    }
}
```

`Sources/RimeKit/TextReplacement/TextReplacementSync.swift`：

```swift
import Foundation

/// 文本替换同步的记录（设计 6.5）：只存哈希，不存内容
public enum TextReplacementSync {
    public struct Changes: Sendable, Equatable {
        public let added: Int
        public let removed: Int

        public init(added: Int, removed: Int) {
            self.added = added
            self.removed = removed
        }

        public var isEmpty: Bool { added == 0 && removed == 0 }
    }

    /// 每一条的哈希（短语<Tab>编码，不看权重），去重、排序
    public static func entryHashes(_ phrases: [Phrase]) -> [String] {
        Array(Set(phrases.map { Hashing.sha256(of: Data(($0.text + "\t" + $0.code).utf8)) })).sorted()
    }

    /// 整体的哈希
    public static func hash(_ phrases: [Phrase]) -> String {
        Hashing.sha256(of: Data(entryHashes(phrases).joined(separator: "\n").utf8))
    }

    /// 现在的文本替换和上次同步时比：新增几条、删掉几条（改了内容算一删一增）。从没同步过时为 nil
    public static func changes(_ current: [Phrase], since settings: TextReplacementSettings) -> Changes? {
        guard let synced = settings.syncedEntries else { return nil }
        let now = Set(entryHashes(current))
        let before = Set(synced)
        return Changes(added: now.subtracting(before).count, removed: before.subtracting(now).count)
    }
}

extension Settings {
    /// 同步开着时，记下这次写入用的文本替换（只存哈希）；关着时清掉记录
    public func recordingTextReplacement(_ phrases: [Phrase]) -> Settings {
        var copy = self
        if textReplacement.sync {
            copy.textReplacement.lastSyncedHash = TextReplacementSync.hash(phrases)
            copy.textReplacement.syncedEntries = TextReplacementSync.entryHashes(phrases)
        } else {
            copy.textReplacement.lastSyncedHash = nil
            copy.textReplacement.syncedEntries = nil
        }
        return copy
    }

    /// 去掉同步记录：哈希也是从文本替换内容算出来的，导出文件里不放
    public var withoutTextReplacementRecord: Settings {
        var copy = self
        copy.textReplacement.lastSyncedHash = nil
        copy.textReplacement.syncedEntries = nil
        return copy
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TextReplacementSyncTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 7 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit Tests/RimeKitTests/TextReplacementSyncTests.swift
git commit -m "feat: 文本替换同步记录：只存每条的哈希，能数出新增、删掉几条

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 接管、导入时记下文本替换；导出时去掉记录

**Files:**
- Modify: `Sources/RimeKit/Takeover/TakeoverApplier.swift`
- Modify: `Sources/RimeKit/Transfer/Importer.swift`
- Modify: `Sources/RimeKit/Transfer/Exporter.swift`
- Test: `Tests/RimeKitTests/TakeoverApplierTests.swift`、`Tests/RimeKitTests/ImporterTests.swift`、`Tests/RimeKitTests/ExporterTests.swift`

**Interfaces:**
- Consumes: `Settings.recordingTextReplacement`、`Settings.withoutTextReplacementRecord`（任务 2）
- Produces:
  - 接管、导入保存的设置 = 识别出 / 导入的设置 `.recordingTextReplacement(这次生成用的文本替换)`
  - 导出文件 `manifest.json` 里的设置 = `.withoutTextReplacementRecord`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/TakeoverApplierTests.swift`：「确认后写入并保存设置和个人内容」里

```swift
        #expect(try SettingsStore(paths: e.paths).load() == expected.settings)
```

改成

```swift
        // 文本替换同步打开了：保存的设置里记下了这次用的文本替换（只有哈希）
        #expect(try SettingsStore(paths: e.paths).load() == expected.settings.recordingTextReplacement([F.fromTR]))
        #expect(try SettingsStore(paths: e.paths).load()?.textReplacement.syncedEntries?.count == 1)
```

`Tests/RimeKitTests/ImporterTests.swift`：「打开了文本替换同步时带上新电脑的文本替换」最后加：

```swift
        let saved = try #require(try SettingsStore(paths: b.paths).load())
        #expect(saved.textReplacement.syncedEntries == TextReplacementSync.entryHashes([tr]))
```

`Tests/RimeKitTests/ExporterTests.swift` 的 suite 里加：

```swift
    @Test func 导出文件里没有文本替换的同步记录() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        var settings = T.settings
        settings.textReplacement.sync = true
        try SettingsStore(paths: m.paths).save(settings.recordingTextReplacement([Phrase(text: "替换", code: "th", weight: 1)]))
        let report = try await m.exporter().export(to: m.dir.url.appending(path: "e.zip"), packages: [])
        #expect(report.manifest.settings.textReplacement == TextReplacementSettings(sync: true))
        let text = try String(contentsOf: try unzip(m.dir.url.appending(path: "e.zip"), m).appending(path: "manifest.json"), encoding: .utf8)
        #expect(!text.contains("syncedEntries"))
        #expect(!text.contains("lastSyncedHash"))
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "TakeoverApplierTests|ImporterTests|ExporterTests" 2>&1 | grep -E "error:|Expectation failed|Test run" | head -6`
Expected: 三处断言失败（保存的设置没有记录；导出文件里有 `lastSyncedHash`）

- [ ] **Step 3: 实现**

`Sources/RimeKit/Takeover/TakeoverApplier.swift`：`let settings = proposal.settings` 和后面的 `deployer.apply(` 改成先算出生成输入，再记录：

```swift
        let input = staged.generationInput(catalog: catalog, packages: packages, textReplacement: textReplacement)
        let settings = proposal.settings.recordingTextReplacement(input.textReplacementPhrases)
        let phrases = proposal.manualPhrases
        return try await deployer.apply(
            input,
            options: ApplyOptions(overwriteExternalChanges: true),
            afterWrite: { try AppDataWriter.replace(settings: settings, dicts: dictFiles, phrases: phrases, paths: paths) })
```

`Sources/RimeKit/Transfer/Importer.swift`：`let settings = archive.manifest.settings` 那一段改成：

```swift
        let imported = archive.manifest.settings
        let dicts = archive.personalDicts
        let phrases = archive.phrases
        let replacements = imported.textReplacement.sync ? textReplacement : []
        // 记下这次用的文本替换（同步关着时清掉记录）
        let settings = imported.recordingTextReplacement(replacements)
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: PersonalContent(dicts: dicts, phrases: phrases),
                                    textReplacementPhrases: replacements)
```

（后面 `afterWrite` 里用的 `settings` 就是记录过的。）

`Sources/RimeKit/Transfer/Exporter.swift`：`let manifest = ExportManifest(…, settings: settings, …)` 里的 `settings: settings` 改成 `settings: settings.withoutTextReplacementRecord`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "Takeover|Importer|Exporter|Rimectl" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 接管、导入时记下用的文本替换；导出文件里不放同步记录

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `rimectl textreplacement`；`apply` 时更新记录

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`
- Modify: `Tests/RimeKitTests/RimectlTakeoverTests.swift`、`Tests/RimeKitTests/RimectlTransferTests.swift`（`Context` 字段改名）
- Test: `Tests/RimeKitTests/RimectlTextReplacementTests.swift`

**Interfaces:**
- Consumes: `TextReplacementSnapshot`（任务 1）、`TextReplacementSync`、`recordingTextReplacement`（任务 2）
- Produces:
  - `Rimectl.Context.textReplacementSnapshot: @Sendable () throws -> TextReplacementSnapshot`（默认读系统数据库），替换原来的 `textReplacements` 字段；`Context.textReplacements() throws -> [Phrase]` 变成方法（`snapshot().usable`），原来调用 `context.textReplacements()` 的地方不用改
  - `rimectl textreplacement status`：只读，退出码 0；没有设置 → 1
  - `rimectl textreplacement sync [--cache-only]`：打开同步并应用，输出和 `apply` 一样
  - `rimectl textreplacement off [--cache-only]`：关掉同步并应用
  - `rimectl apply`：写好后（通知鼠须管前）保存 `settings.recordingTextReplacement(这次用的文本替换)`，设置没变就不写
  - `prepareInput(…, settings:)`：可以传入设置代替读文件

- [ ] **Step 1: 改测试里的 Context 字段**

`Tests/RimeKitTests/RimectlTakeoverTests.swift`：
- `context.textReplacements = { [F.fromTR] }` → `context.textReplacementSnapshot = { TextReplacementSnapshot(usable: [F.fromTR], badShortcut: 0, badPhrase: 0) }`
- `context.textReplacements = { throw Unreadable() }` → `context.textReplacementSnapshot = { throw Unreadable() }`

`Tests/RimeKitTests/RimectlTransferTests.swift`：`context.textReplacements = { [] }` → `context.textReplacementSnapshot = { TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0) }`

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/RimectlTextReplacementTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTextReplacementTests {
    typealias T = TransferFixtures

    /// 用户在系统设置里改文本替换：测试里随时换内容
    final class Replacements: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TextReplacementSnapshot
        var failing = false
        init(_ phrases: [Phrase], badShortcut: Int = 0) {
            value = TextReplacementSnapshot(usable: phrases, badShortcut: badShortcut, badPhrase: 0)
        }
        func set(_ phrases: [Phrase]) { lock.withLock { value = TextReplacementSnapshot(usable: phrases, badShortcut: 0, badPhrase: 0) } }
        func get() throws -> TextReplacementSnapshot {
            struct Unreadable: Error, CustomStringConvertible { var description: String { "数据库打不开" } }
            if failing { throw Unreadable() }
            return lock.withLock { value }
        }
    }

    struct CLI {
        let machine: T.Machine
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", machine.locations.rimeDirectory.path, "--cache-only"], context)
        }

        var phraseFile: String {
            (try? String(contentsOf: machine.locations.rimeDirectory.appending(path: "custom_phrase.txt"), encoding: .utf8)) ?? ""
        }

        var settings: Settings? { try? SettingsStore(paths: machine.paths).load() }
    }

    let a = Phrase(text: "替换甲", code: "tha", weight: 1)
    let b = Phrase(text: "替换乙", code: "thb", weight: 1)

    func cli(_ m: T.Machine, _ r: Replacements) -> CLI {
        let output = Output(echo: false)
        let catalog = m.catalog
        var context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: m.paths, output: output,
            locations: m.locations, compiler: FakeCompiler(), squirrel: m.squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in })
        context.textReplacementSnapshot = { try r.get() }
        context.userDBTool = m.tool
        return CLI(machine: m, output: output, context: context)
    }

    @Test func 看状态_同步没打开() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let c = cli(m, Replacements([a], badShortcut: 2))
        #expect(await c.run(["textreplacement", "status"]) == 0)
        #expect(c.output.text.contains("1 条能用"))
        #expect(c.output.text.contains("2 条快捷码里有数字或符号"))
        #expect(c.output.text.contains("没打开"))
    }

    @Test func 同步后看得出新增_再同步就一样了() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "sync"]) == 0)
        #expect(c.output.text.contains("部署完成"))
        #expect(c.settings?.textReplacement.sync == true)
        #expect(c.settings?.textReplacement.syncedEntries == TextReplacementSync.entryHashes([a]))
        #expect(c.phraseFile.contains(a.line))
        #expect(c.phraseFile.contains(T.phrase.line))   // 手动短语还在

        let c2 = cli(m, r)
        #expect(await c2.run(["textreplacement", "status"]) == 0)
        #expect(c2.output.text.contains("和上次同步时一样"))

        r.set([a, b])   // 用户在系统设置里加了一条
        let c3 = cli(m, r)
        #expect(await c3.run(["textreplacement", "status"]) == 0)
        #expect(c3.output.text.contains("新增 1 条，删掉 0 条"))
        #expect(await c3.run(["textreplacement", "sync"]) == 0)
        #expect(c3.phraseFile.contains(b.line))

        let c4 = cli(m, r)
        #expect(await c4.run(["textreplacement", "status"]) == 0)
        #expect(c4.output.text.contains("和上次同步时一样"))
    }

    @Test func 改别的设置时也带上最新的文本替换并记下() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        r.set([a, b])
        let c = cli(m, r)
        #expect(await c.run(["apply"]) == 0)
        #expect(c.phraseFile.contains(b.line))
        #expect(c.settings?.textReplacement.syncedEntries == TextReplacementSync.entryHashes([a, b]))
    }

    @Test func 关掉同步去掉文本替换的短语_手动短语还在() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "off"]) == 0)
        #expect(c.settings?.textReplacement == TextReplacementSettings(sync: false))
        #expect(!c.phraseFile.contains(a.line))
        #expect(c.phraseFile.contains(T.phrase.line))
    }

    @Test func 读不了时报错_不悄悄去掉已经同步的短语() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        #expect(await cli(m, r).run(["textreplacement", "sync"]) == 0)
        r.failing = true
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "status"]) == 1)
        #expect(await c.run(["apply"]) == 1)
        #expect(c.output.text.contains("数据库打不开"))
        #expect(c.phraseFile.contains(a.line))
    }

    @Test func 输出里没有文本替换的内容() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let r = Replacements([a])
        let c = cli(m, r)
        #expect(await c.run(["textreplacement", "sync"]) == 0)
        r.set([a, b])
        #expect(await c.run(["textreplacement", "status"]) == 0)
        for secret in [a.text, a.code, b.text, b.code] {
            #expect(!c.output.text.contains(secret), "输出里有「\(secret)」")
        }
    }

    @Test func 没有设置时() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let c = cli(m, Replacements([a]))
        #expect(await c.run(["textreplacement", "status"]) == 1)
        #expect(c.output.text.contains("还没有设置"))
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter "Rimectl" 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`value of type 'Rimectl.Context' has no member 'textReplacementSnapshot'`

- [ ] **Step 4: 实现**

`Sources/rimectl/Rimectl.swift`：

1. `Context` 里原来的

```swift
        /// 读 macOS 文本替换；测试时换成假的
        var textReplacements: @Sendable () throws -> [Phrase] = { try TextReplacementReader().read() }
```

换成

```swift
        /// 读 macOS 文本替换；测试时换成假的
        var textReplacementSnapshot: @Sendable () throws -> TextReplacementSnapshot = { try TextReplacementReader().snapshot() }
```

并在 `Context` 里（`struct Context: Sendable {` 的最后，`}` 前面）加：

```swift
        /// 能用的文本替换
        func textReplacements() throws -> [Phrase] {
            try textReplacementSnapshot().usable
        }
```

2. `usage` 里 `rimectl import …` 那一行后面加：

```
      rimectl textreplacement status|sync|off [--cache-only]  文本替换：看状态 / 打开同步并应用 / 关掉同步并应用
```

3. `switch command` 里 `case "export":` 前面加：

```swift
            case "textreplacement":
                return try await textReplacementCommand(Array(positional.dropFirst()), cacheOnly: cacheOnly,
                                                        paths: paths, locations: locations, context)
```

4. `prepareInput` 的签名和第一句改成：

```swift
    private static func prepareInput(cacheOnly: Bool, paths: AppPaths, _ context: Context,
                                     settings override: Settings? = nil) async throws -> GenerationInput? {
        let out = context.output
        guard let settings = try override ?? SettingsStore(paths: paths).load() else {
```

（`guard` 的 else 部分不变。）

5. `apply` 整个换成：

```swift
    private static func apply(cacheOnly: Bool, options: ApplyOptions, paths: AppPaths, locations: RimeLocations,
                              _ context: Context, settings override: Settings? = nil) async throws -> Int32 {
        let out = context.output
        guard let input = try await prepareInput(cacheOnly: cacheOnly, paths: paths, context, settings: override) else { return 1 }
        // 写好后（通知鼠须管前）记下这次用的文本替换；设置没变就不写
        let updated = input.settings.recordingTextReplacement(input.textReplacementPhrases)
        let changed = try updated != SettingsStore(paths: paths).load()
        let outcome = try await deployer(paths: paths, locations: locations, context).apply(
            input, options: options,
            afterWrite: { if changed { try SettingsStore(paths: paths).save(updated) } })
        return printApplyOutcome(outcome, out)
    }
```

6. 新增（放在 `importCommand` 后面）：

```swift
    /// 文本替换：status 只读；sync / off 改开关后走一次应用。只输出条数，不输出内容
    private static func textReplacementCommand(_ args: [String], cacheOnly: Bool, paths: AppPaths, locations: RimeLocations,
                                               _ context: Context) async throws -> Int32 {
        let out = context.output
        guard args.count == 1 else { out.error(usage); return 2 }
        guard var settings = try SettingsStore(paths: paths).load() else {
            out.error("还没有设置。先运行 rimectl takeover 接管已有配置，或 rimectl settings init 选一个起步方案")
            return 1
        }
        switch args[0] {
        case "status":
            let snapshot = try context.textReplacementSnapshot()
            var line = "macOS 文本替换：\(snapshot.usable.count) 条能用"
            if snapshot.badShortcut > 0 { line += "；\(snapshot.badShortcut) 条快捷码里有数字或符号，Rime 里打不出来，跳过" }
            if snapshot.badPhrase > 0 { line += "；\(snapshot.badPhrase) 条内容是空的、有换行或 Tab，跳过" }
            out.line(line)
            guard settings.textReplacement.sync else {
                out.line("同步：没打开。打开并应用：rimectl textreplacement sync")
                return 0
            }
            if let changes = TextReplacementSync.changes(snapshot.usable, since: settings.textReplacement) {
                if changes.isEmpty {
                    out.line("同步：已打开，和上次同步时一样")
                } else {
                    out.line("同步：已打开。和上次同步比：新增 \(changes.added) 条，删掉 \(changes.removed) 条。要同步就运行 rimectl textreplacement sync")
                }
            } else {
                out.line("同步：已打开，还没同步过。要同步就运行 rimectl textreplacement sync")
            }
            return 0
        case "sync":
            settings.textReplacement.sync = true
            return try await apply(cacheOnly: cacheOnly, options: ApplyOptions(), paths: paths, locations: locations,
                                   context, settings: settings)
        case "off":
            settings.textReplacement.sync = false
            return try await apply(cacheOnly: cacheOnly, options: ApplyOptions(), paths: paths, locations: locations,
                                   context, settings: settings)
        default:
            out.error(usage)
            return 2
        }
    }
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter "Rimectl" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过

- [ ] **Step 6: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/rimectl/Rimectl.swift Tests/RimeKitTests
git commit -m "feat: rimectl textreplacement status|sync|off；应用时记下用的文本替换

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 环境检查里看文本替换有没有没同步的变化

**Files:**
- Modify: `Sources/RimeKit/Install/Doctor.swift`
- Modify: `Sources/rimectl/Rimectl.swift`（`doctor` 传入读文本替换的函数）
- Test: `Tests/RimeKitTests/DoctorTests.swift`

**Interfaces:**
- Consumes: `TextReplacementSync.changes`（任务 2）、`Context.textReplacements()`（任务 4）
- Produces: `Doctor.init(…, textReplacements: (@Sendable () throws -> [Phrase])? = nil)`。同步开着、而且传了这个函数时，多一项「文本替换」：
  - 和上次一样 → `.ok`「N 条，和上次同步时一样」
  - 有变化 → `.warning`「有变化没同步：新增 a 条，删掉 r 条」，提示 `运行 rimectl textreplacement sync`
  - 从没同步过 → `.warning`，同样的提示
  - 读不了 → `.warning`「读不了：…」
  - 同步关着、没有设置、没传函数 → 没有这一项

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/DoctorTests.swift` 的 suite 里加：

```swift
    func textReplacementDoctor(_ dir: TempDir, synced: [Phrase]?, current: [Phrase], failing: Bool = false) throws -> Doctor {
        let l = try DeployFixtures.locations(dir)
        try InstallFixtures.writeInfoPlist(app: l.squirrelApp, version: "1.1.2")
        let paths = Fixtures.paths(dir)
        var settings = Settings(schemas: ["py"])
        settings.textReplacement.sync = synced != nil
        if let synced { settings = settings.recordingTextReplacement(synced) }
        try SettingsStore(paths: paths).save(settings)
        struct Unreadable: Error, CustomStringConvertible { var description: String { "数据库打不开" } }
        return Doctor(paths: paths, locations: l,
                      inputSource: FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true)),
                      squirrel: FakeSquirrel(locations: l, running: true), releaseSource: nil,
                      textReplacements: { if failing { throw Unreadable() }; return current })
    }

    let ta = Phrase(text: "替换甲", code: "tha", weight: 1)
    let tb = Phrase(text: "替换乙", code: "thb", weight: 1)

    @Test func 文本替换和上次一样() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let checks = try await textReplacementDoctor(dir, synced: [ta], current: [ta]).run()
        #expect(checks.first { $0.name == "文本替换" } == DoctorCheck(name: "文本替换", level: .ok, message: "1 条，和上次同步时一样"))
    }

    @Test func 文本替换有变化没同步() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let checks = try await textReplacementDoctor(dir, synced: [ta], current: [ta, tb]).run()
        #expect(checks.first { $0.name == "文本替换" } == DoctorCheck(
            name: "文本替换", level: .warning, message: "有变化没同步：新增 1 条，删掉 0 条", hint: "运行 rimectl textreplacement sync"))
    }

    @Test func 文本替换读不了() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let check = try await textReplacementDoctor(dir, synced: [ta], current: [], failing: true).run().first { $0.name == "文本替换" }
        #expect(check?.level == .warning)
        #expect(check?.message.contains("数据库打不开") == true)
    }

    @Test func 同步没打开就不看文本替换() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let checks = try await textReplacementDoctor(dir, synced: nil, current: [ta]).run()
        #expect(!checks.contains { $0.name == "文本替换" })
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DoctorTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`extra argument 'textReplacements' in call`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Install/Doctor.swift`：
1. 属性 `let releaseSource: SquirrelReleaseSource?` 后面加：

```swift
    /// 读 macOS 文本替换；为空就不检查文本替换
    let textReplacements: (@Sendable () throws -> [Phrase])?
```

2. `init` 加参数 `textReplacements: (@Sendable () throws -> [Phrase])? = nil`（放最后），赋值 `self.textReplacements = textReplacements`。
3. `run()` 里 `checks.append(settingsCheck())`（装了鼠须管的那条路径，在 `managedCheck()` 前面）后面加：

```swift
        if let check = textReplacementCheck() { checks.append(check) }
```

4. `managedCheck()` 后面加：

```swift
    /// 同步开着时：文本替换和上次同步时比有没有变化（设计 6.5）
    private func textReplacementCheck() -> DoctorCheck? {
        guard let textReplacements, let settings = try? SettingsStore(paths: paths).load(), settings.textReplacement.sync else {
            return nil
        }
        let name = "文本替换"
        let current: [Phrase]
        do {
            current = try textReplacements()
        } catch {
            return DoctorCheck(name: name, level: .warning, message: "读不了：\(error)")
        }
        guard let changes = TextReplacementSync.changes(current, since: settings.textReplacement) else {
            return DoctorCheck(name: name, level: .warning, message: "打开了同步，但还没同步过", hint: "运行 rimectl textreplacement sync")
        }
        if changes.isEmpty {
            return DoctorCheck(name: name, level: .ok, message: "\(current.count) 条，和上次同步时一样")
        }
        return DoctorCheck(name: name, level: .warning, message: "有变化没同步：新增 \(changes.added) 条，删掉 \(changes.removed) 条",
                           hint: "运行 rimectl textreplacement sync")
    }
```

`Sources/rimectl/Rimectl.swift` 的 `doctor` 里，`Doctor(` 的参数最后加：

```swift
            textReplacements: { try context.textReplacements() }
```

（`releaseSource: …` 那一行末尾加逗号。）

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "DoctorTests|Rimectl" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources Tests
git commit -m "feat: 环境检查里看文本替换有没有没同步的变化

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 测试机里实测

**Files:**
- Create: `docs/phase7-vm-log.md`

**Interfaces:**
- Consumes: `rimectl textreplacement`、`rimectl doctor`（任务 4、5）
- Produces: 实测记录；发现的问题按 TDD 修

先编译：`swift build 2>&1 | tail -1`。`squirrel-dev` 的 `/tmp/rk` 现在同步是关着的。

```bash
vmrun() { ./tools/vm/vm.sh ssh squirrel-dev "sudo launchctl asuser \$(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' $*"; }
```

- [ ] **Step 1: 看状态、打开同步**

```bash
vmrun textreplacement status --data-dir /tmp/rk
vmrun textreplacement sync --cache-only --data-dir /tmp/rk
vmrun textreplacement status --data-dir /tmp/rk
vmrun doctor --offline --data-dir /tmp/rk
```

Expected：
- 第一次 `status`：「N 条能用」（测试机里有系统自带的 1 条和阶段 0 加的 `tstx`），「同步：没打开」。
- `sync`：「部署完成」。
- 再 `status`：「和上次同步时一样」。
- `doctor`：「[正常] 文本替换：N 条，和上次同步时一样」。

- [ ] **Step 2: 用户加一条、改一条**

用 AskUserQuestion 请用户在 `squirrel-dev` 的「系统设置 → 键盘 → 文本替换」里：
- 加一条：快捷码 `tsxj`，内容「测试新加」；
- 再加一条快捷码带数字的：`ts2`，内容「打不出来」。

然后：

```bash
vmrun textreplacement status --data-dir /tmp/rk
vmrun doctor --offline --data-dir /tmp/rk
vmrun textreplacement sync --cache-only --data-dir /tmp/rk
```

Expected：
- `status`：「1 条快捷码里有数字或符号…跳过」「新增 1 条，删掉 0 条」。
- `doctor`：「[注意] 文本替换：有变化没同步：新增 1 条，删掉 0 条」。
- `sync`：「部署完成」。

用 AskUserQuestion 请用户打字检查（雾凇全拼）：`tstx` → 测试短语，`tsxj` → 测试新加。

- [ ] **Step 3: 关掉同步，还原**

```bash
vmrun textreplacement off --cache-only --data-dir /tmp/rk
vmrun status --data-dir /tmp/rk
```

Expected：「部署完成」；`status` 没有外部改动。请用户确认 `tsxj` 不再出「测试新加」，再把刚加的两条文本替换删掉（`tstx` 留着，以后还用）。

- [ ] **Step 4: 写记录，提交**

`docs/phase7-vm-log.md`：按步骤写关键输出（只写条数，不写文本替换内容；测试用的 `tstx`、`tsxj` 是编的，可以写）、用户检查结果、发现的问题和怎么修的。

```bash
git add docs/phase7-vm-log.md
git commit -m "docs: 阶段 7 测试机实测记录（文本替换同步）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 更新文档

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（第 5 节 `settings.json` 表格「文本替换」一行、6.5）
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`、`CLAUDE.md`、`README.md`
- Modify: `docs/verified-facts.md`（任务 6 有新发现时）

- [ ] **Step 1: 设计文档**

第 5 节 `settings.json` 表格里「文本替换」那一行的内容改成：

```markdown
| 文本替换 | 是否同步；上次同步时的整体哈希和每一条的哈希（只存哈希，用来数有几条变化；导出时去掉） |
```

6.5 末尾加一段：

```markdown
做法（阶段 7 定下）：
- 读的时候把用不了的条目数出来：快捷码里有数字、符号（Rime 里打不出来）；内容是空的、有换行或 Tab、以 `#` 开头。只显示条数。
- 记录：每一条按「短语<Tab>编码」算 SHA-256，排好序存进设置；和现在的比，数出新增、删掉几条（改了内容算一删一增）。
- 同步开着时，任何一次写入（应用改动、接管、导入）都带上当前的文本替换，并更新记录；关掉同步会去掉文本替换生成的短语，手动短语不受影响。
- 读不了数据库时报错，不悄悄去掉已经同步的短语。
- 命令行：`rimectl textreplacement status | sync | off`；`rimectl doctor` 在同步开着时多一项「文本替换」。应用界面的「检查」「同步」按钮和开关在阶段 8。
```

- [ ] **Step 2: 路线图、CLAUDE.md、README**

- 路线图阶段 7 那一行成果改成：`rimectl textreplacement status|sync|off`：数出能用、跳过的条目，看出新增、删掉了几条，同步、关掉；`doctor` 提示没同步的变化（读取在阶段 5 做好；已完成，2026-10-15）。
- `CLAUDE.md` 第一段的阶段状态改成「阶段 0–7 已完成（…；一键导出导入；文本替换同步），下一步写阶段 8（SwiftUI 应用）的计划」。
- `README.md` 里「导出导入」那一行后面加：`- 文本替换：rimectl textreplacement status 看状态，sync 打开同步并应用，off 关掉（只在测试机里同步）`（命令部分用反引号）。

- [ ] **Step 3: 检查，提交**

```bash
grep -n "阶段 7 定下" docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 7 完成：文本替换同步的做法写进设计，更新路线图和说明

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

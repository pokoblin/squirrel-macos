# 阶段 3：写入真实配置、部署、备份还原 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把阶段 2 生成的配置安全地写进 `~/Library/Rime`：先在暂存区编译校验，发现外部改动先问，写入前备份，只写应用管理的文件，写失败自动还原，然后通知鼠须管部署并判断成没成功。命令行加 `rimectl apply`、`status`、`restore`、`settings set`。

**Architecture:** 新增 `Deploy/` 目录下几个小模块：`RimeLocations`（鼠须管和 Rime 目录在哪）、`RimeFiles`（哪些是 Rime 自己的运行文件）、`Ledger`（应用写过哪些文件和哈希）、`BackupStore`（备份、清理、还原）、`RimeCompiler`（`rime_deployer` 编译 + 错误翻译）、`SquirrelControl`（`--reload` / 启动）、`DeployWatcher`（等部署完、收集新错误）、`ApplyLock`（锁文件）、`Deployer`（把上面串成设计 6.1 的流程）。所有会碰系统的部分都通过协议注入，宿主机测试用假的鼠须管和临时目录；真实流程在测试机 `squirrel-dev` 里跑。

**Tech Stack:** Swift 6.4、Swift Testing、Yams、Darwin（`flock`、`rename`、`getpwuid`）、鼠须管自带的 `rime_deployer` 和 `Squirrel --reload`。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 5、6.1、7、8 节）；事实 [docs/verified-facts.md](../../verified-facts.md)；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## Global Constraints

- 宿主机测试**只用临时目录**当 Rime 目录，绝不碰宿主机的 `~/Library/Rime`、`/Library/Input Methods`、输入法状态；真实写入只在测试机里做。宿主机测试可以只读调用鼠须管的 `rime_deployer` 编译临时目录。
- 真实流程测试在 `squirrel-dev` 里，命令通过 `sudo launchctl asuser $(id -u) sudo -u tester …` 在桌面会话里运行（`open` 和 `--reload` 需要）。测试机远程 shell 是 zsh：别把命令放进变量再展开，用函数。
- 写进 Rime 目录的每个文件都先写同目录下的临时文件再 `rename`，不会出现写了一半的文件。
- 「Rime 自己的运行文件」不备份、不写、不算外部文件：`build/`、`sync/`、`installation.yaml`、`user.yaml`、`*.userdb`（目录）、`*.userdb.txt`、`.DS_Store`。
- 编译成功 = `rime_deployer --build` 退出码 0 **并且**输出里没有 `E` 开头的日志行（补丁 YAML 写坏时退出码是 0，只有一行 `E… Error parsing YAML`，已实测）。
- 部署完成 = `user.yaml` 的 `var/last_build_time` 和通知前不一样（每次 `--reload` 都会更新，已实测）；之后收集这次新增的 ERROR 日志行。默认最多等 120 秒。不用 `build/` 文件的修改时间判断（只改外观时方案文件不会重编译）。
- 备份保留最近 10 份；「第一次应用前」那份（当时 Rime 目录里已有配置时）永久保留。还原前先给当前状态做一份「还原前」备份。
- 个人内容只统计条数、比对哈希；错误信息、命令行输出用简单直白的中文，不打印个人词库和短语内容。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 用户在应用外改了、删了应用管理的文件，或者 Rime 目录里有应用不管但这次要覆盖的文件 → 绝不悄悄覆盖，先列出来（任务 6 有测试，任务 9 测试机实测）。
2. 写到一半失败（磁盘满、目标是个目录）→ Rime 目录恢复成写之前的样子，ledger 也不变（任务 6 有测试）。
3. 应用和 `rimectl` 同时在改 → 后来的被挡住，什么都不做（任务 5、6 有测试）。
4. 鼠须管没在运行 → 启动它；只改了外观、方案文件没重编译 → 仍然能判断部署完成（任务 5 有测试，任务 9 测试机实测）。
5. 补丁写坏（`rime_deployer` 退出码 0 但有 `E` 行）→ 当作编译失败，什么都不写（任务 4、6 有测试，任务 9 测试机实测）。

---

## 文件结构

```
Sources/RimeKit/
  AppPaths.swift                 # 加 ledgerFile、backups、lockFile
  Deploy/RimeLocations.swift     # 鼠须管、Rime 目录、日志目录在哪
  Deploy/RimeFiles.swift         # Rime 自己的运行文件；列出配置文件
  Deploy/Ledger.swift            # 应用写过的文件和哈希；外部改动
  Deploy/BackupStore.swift       # 备份、列出、清理、还原
  Deploy/RimeCompiler.swift      # 编译检查；Rime 错误日志的翻译
  Deploy/SquirrelControl.swift   # 是否在运行、--reload、启动
  Deploy/DeployWatcher.swift     # 等部署完、收集新错误
  Deploy/ApplyLock.swift         # 锁文件
  Deploy/Deployer.swift          # 应用改动、还原、状态
Sources/rimectl/Rimectl.swift    # apply、status、restore、settings set
Tests/RimeKitTests/
  Support/DeployFakes.swift      # 假的鼠须管、假的编译器、临时的鼠须管位置
  RimeFilesTests.swift
  LedgerTests.swift
  BackupStoreTests.swift
  RimeLogTests.swift
  DeployWatcherTests.swift
  ApplyLockTests.swift
  DeployerTests.swift
  DeployerRestoreTests.swift
  RimectlApplyTests.swift
```

---

### Task 1: 位置和文件分类：`RimeLocations`、`RimeFiles`

**Files:**
- Modify: `Sources/RimeKit/AppPaths.swift`
- Modify: `Tests/RimeKitTests/AppPathsTests.swift`
- Create: `Sources/RimeKit/Deploy/RimeLocations.swift`
- Create: `Sources/RimeKit/Deploy/RimeFiles.swift`
- Test: `Tests/RimeKitTests/RimeFilesTests.swift`

**Interfaces:**
- Produces:
  - `AppPaths.ledgerFile`（`root/ledger.json`）、`AppPaths.backups`（`root/backups`）、`AppPaths.lockFile`（`root/lock`）
  - `public struct RimeLocations: Sendable, Equatable { var rimeDirectory, squirrelApp, logDirectory: URL; init(rimeDirectory:squirrelApp:logDirectory:); static var default; var squirrelBinary, deployerBinary, sharedSupport: URL; var squirrelInstalled: Bool }`
  - `public enum RimeFiles { static func isRimeOwned(_ path: String) -> Bool; static func configFiles(in dir: URL) throws -> [String] }`（`configFiles`：相对路径、排序；普通文件和符号链接；跳过 Rime 自己的运行文件；目录不存在时返回空）

- [ ] **Step 1: 改 `AppPaths.swift`，在 `personalPhrases` 后面加**

```swift
    /// 应用写进 ~/Library/Rime 的文件和哈希
    public var ledgerFile: URL { root.appending(path: "ledger.json") }

    /// 每次写入前对 ~/Library/Rime 的备份
    public var backups: URL { root.appending(path: "backups", directoryHint: .isDirectory) }

    /// 防止应用和 rimectl 同时改
    public var lockFile: URL { root.appending(path: "lock") }
```

`AppPathsTests.子目录都在根目录下` 里加：

```swift
        #expect(paths.ledgerFile.path == "/tmp/x/ledger.json")
        #expect(paths.backups.path == "/tmp/x/backups")
        #expect(paths.lockFile.path == "/tmp/x/lock")
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/RimeFilesTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct RimeFilesTests {
    @Test func 认出Rime自己的运行文件() {
        for path in ["build/default.yaml", "build", "sync/abc/rime_ice.userdb.txt", "installation.yaml", "user.yaml",
                     "rime_ice.userdb", "rime_ice.userdb/LOCK", "x.userdb.txt", ".DS_Store", "cn_dicts/.DS_Store"] {
            #expect(RimeFiles.isRimeOwned(path), "\(path)")
        }
        for path in ["default.custom.yaml", "rime_ice.schema.yaml", "cn_dicts/8105.dict.yaml", "custom_phrase.txt", "lua/x.lua"] {
            #expect(!RimeFiles.isRimeOwned(path), "\(path)")
        }
    }

    @Test func 列出配置文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let fm = FileManager.default
        for path in ["default.custom.yaml", "cn_dicts/8105.dict.yaml", "build/default.yaml", "user.yaml",
                     "rime_ice.userdb/LOCK", "sync/x/a.userdb.txt", ".DS_Store"] {
            let url = dir.url.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        try fm.createSymbolicLink(at: dir.url.appending(path: "link.yaml"), withDestinationURL: dir.url.appending(path: "default.custom.yaml"))
        try fm.createDirectory(at: dir.url.appending(path: "empty"), withIntermediateDirectories: true)
        #expect(try RimeFiles.configFiles(in: dir.url) == ["cn_dicts/8105.dict.yaml", "default.custom.yaml", "link.yaml"])
    }

    @Test func 目录不存在时是空的() throws {
        #expect(try RimeFiles.configFiles(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == [])
    }

    @Test func 默认位置() {
        let l = RimeLocations.default
        #expect(l.rimeDirectory.path.hasSuffix("/Library/Rime"))
        #expect(l.deployerBinary.path == "/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer")
        #expect(l.squirrelBinary.path == "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel")
        #expect(l.sharedSupport.path == "/Library/Input Methods/Squirrel.app/Contents/SharedSupport")
        #expect(l.logDirectory.path.hasSuffix("/rime.squirrel"))
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter RimeFilesTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'RimeFiles' in scope`。

- [ ] **Step 4: 写 `Sources/RimeKit/Deploy/RimeLocations.swift`**

```swift
import Darwin
import Foundation

/// 鼠须管、Rime 用户目录、Rime 日志目录在哪。测试时换成临时目录。
public struct RimeLocations: Sendable, Equatable {
    public var rimeDirectory: URL
    public var squirrelApp: URL
    public var logDirectory: URL

    public init(rimeDirectory: URL, squirrelApp: URL, logDirectory: URL) {
        self.rimeDirectory = rimeDirectory
        self.squirrelApp = squirrelApp
        self.logDirectory = logDirectory
    }

    /// 当前用户的 ~/Library/Rime、系统里的鼠须管、$TMPDIR/rime.squirrel
    public static var `default`: RimeLocations {
        RimeLocations(
            rimeDirectory: homeDirectory().appending(path: "Library/Rime", directoryHint: .isDirectory),
            squirrelApp: URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app", isDirectory: true),
            logDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appending(path: "rime.squirrel", directoryHint: .isDirectory))
    }

    public var squirrelBinary: URL { squirrelApp.appending(path: "Contents/MacOS/Squirrel") }
    public var deployerBinary: URL { squirrelApp.appending(path: "Contents/MacOS/rime_deployer") }
    public var sharedSupport: URL { squirrelApp.appending(path: "Contents/SharedSupport", directoryHint: .isDirectory) }

    public var squirrelInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: deployerBinary.path)
    }

    /// 用 passwd 里的家目录（sudo -u 运行时 $HOME 可能还是原来的用户）
    static func homeDirectory() -> URL {
        if let pw = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Deploy/RimeFiles.swift`**

```swift
import Foundation

/// Rime 用户目录里的文件分类
public enum RimeFiles {
    /// Rime 自己的运行文件：不备份、不由应用写、也不算外部文件
    public static func isRimeOwned(_ path: String) -> Bool {
        let first = path.split(separator: "/").first.map(String.init) ?? path
        let name = (path as NSString).lastPathComponent
        if first == "build" || first == "sync" { return true }
        if path == "installation.yaml" || path == "user.yaml" { return true }
        if first.hasSuffix(".userdb") || name.hasSuffix(".userdb.txt") { return true }
        if name == ".DS_Store" { return true }
        return false
    }

    /// 目录里的配置文件（相对路径，排好序）：普通文件和符号链接，跳过 Rime 自己的运行文件。目录不存在时返回空。
    public static func configFiles(in dir: URL) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        return try fm.subpathsOfDirectory(atPath: dir.path).filter { sub in
            guard !isRimeOwned(sub) else { return false }
            let type = (try? fm.attributesOfItem(atPath: dir.appending(path: sub).path))?[.type] as? FileAttributeType
            return type == .typeRegular || type == .typeSymbolicLink
        }.sorted()
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 4 个）。

- [ ] **Step 7: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 鼠须管和 Rime 目录的位置；Rime 自己的运行文件分类

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `Ledger`（应用写过的文件）和外部改动

**Files:**
- Create: `Sources/RimeKit/Deploy/Ledger.swift`
- Test: `Tests/RimeKitTests/LedgerTests.swift`

**Interfaces:**
- Consumes: `AppPaths.ledgerFile`（任务 1）、`FileOrigin`（阶段 2）、`Hashing`、`JSONCoding`。
- Produces:
  - `public struct LedgerEntry: Sendable, Equatable, Codable { sha256: String; origin: String }`
  - `public struct Ledger: Sendable, Equatable, Codable { static let currentFormatVersion = 1; var formatVersion: Int; var appliedAt: Date?; var entries: [String: LedgerEntry]; init(entries:appliedAt:); static func load(_ paths: AppPaths) throws -> Ledger /* 没有文件时是空的 */; func save(_ paths: AppPaths) throws; func externalChanges(in rimeDirectory: URL) -> [ExternalChange] /* 已管理的文件：改过或删了，按路径排序 */; func unmanagedOverwrites(_ newPaths: [String], in rimeDirectory: URL) -> [ExternalChange] /* 这次要写、ledger 里没有、目录里已经有的 */ }`
  - `public enum ExternalChange: Sendable, Equatable, CustomStringConvertible { case modified(String), deleted(String), unmanaged(String); var path: String }`
  - `extension FileOrigin { var ledgerValue: String }`（`package:<id>`、`generated`、`personal`）
  - `public enum LedgerError: Error, Equatable { case unsupportedFormat(Int) }`

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct LedgerTests {
    func write(_ dir: URL, _ path: String, _ text: String) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func sha(_ text: String) -> String { Hashing.sha256(of: Data(text.utf8)) }

    @Test func 没有文件时是空的存了再读不变() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        #expect(try Ledger.load(paths) == Ledger())
        let ledger = Ledger(entries: ["a.yaml": LedgerEntry(sha256: sha("a"), origin: "generated")],
                            appliedAt: Date(timeIntervalSince1970: 1_000))
        try ledger.save(paths)
        #expect(try Ledger.load(paths) == ledger)
    }

    @Test func 发现改过和删了的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "same.yaml", "same")
        try write(rime, "changed.yaml", "new")
        let ledger = Ledger(entries: [
            "same.yaml": LedgerEntry(sha256: sha("same"), origin: "generated"),
            "changed.yaml": LedgerEntry(sha256: sha("old"), origin: "package:x"),
            "gone.yaml": LedgerEntry(sha256: sha("gone"), origin: "personal"),
        ])
        #expect(ledger.externalChanges(in: rime) == [.modified("changed.yaml"), .deleted("gone.yaml")])
    }

    @Test func 要覆盖应用不管的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "managed.yaml", "m")
        try write(rime, "theirs.yaml", "t")
        let ledger = Ledger(entries: ["managed.yaml": LedgerEntry(sha256: sha("m"), origin: "generated")])
        #expect(ledger.unmanagedOverwrites(["managed.yaml", "theirs.yaml", "new.yaml"], in: rime) == [.unmanaged("theirs.yaml")])
    }

    @Test func 来源的写法() {
        #expect(FileOrigin.package("rime-ice").ledgerValue == "package:rime-ice")
        #expect(FileOrigin.generated.ledgerValue == "generated")
        #expect(FileOrigin.personal.ledgerValue == "personal")
    }

    @Test func 说明是中文() {
        #expect(ExternalChange.modified("a.yaml").description == "a.yaml：在应用外被改过")
        #expect(ExternalChange.deleted("a.yaml").description == "a.yaml：在应用外被删了")
        #expect(ExternalChange.unmanaged("a.yaml").description == "a.yaml：不是应用写的，这次会被覆盖")
    }

    @Test func 不认识的格式版本() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":9,"entries":{}}"#.utf8).write(to: paths.ledgerFile)
        #expect(throws: LedgerError.unsupportedFormat(9)) { try Ledger.load(paths) }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter LedgerTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'Ledger' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Deploy/Ledger.swift`**

```swift
import Foundation

public struct LedgerEntry: Sendable, Equatable, Codable {
    public let sha256: String
    /// package:<包 id>、generated、personal
    public let origin: String

    public init(sha256: String, origin: String) {
        self.sha256 = sha256
        self.origin = origin
    }
}

public enum LedgerError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormat(Int)

    public var description: String {
        switch self {
        case .unsupportedFormat(let v):
            return "ledger.json 的格式版本是 \(v)，这个版本的应用只认识 \(Ledger.currentFormatVersion)，请更新应用"
        }
    }
}

/// 应用写进 ~/Library/Rime 的文件：相对路径 → 哈希、来源。用来发现外部改动、删掉不再需要的文件（设计第 5 节）。
public struct Ledger: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var appliedAt: Date?
    public var entries: [String: LedgerEntry]

    public init(entries: [String: LedgerEntry] = [:], appliedAt: Date? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.entries = entries
        self.appliedAt = appliedAt
    }

    public static func load(_ paths: AppPaths) throws -> Ledger {
        guard FileManager.default.fileExists(atPath: paths.ledgerFile.path) else { return Ledger() }
        let data = try Data(contentsOf: paths.ledgerFile)
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONCoding.decoder.decode(Header.self, from: data)
        guard header.formatVersion == currentFormatVersion else { throw LedgerError.unsupportedFormat(header.formatVersion) }
        return try JSONCoding.decoder.decode(Ledger.self, from: data)
    }

    public func save(_ paths: AppPaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(self).write(to: paths.ledgerFile, options: .atomic)
    }

    /// 应用写过的文件里，在应用外被改过或删掉的（按路径排序）
    public func externalChanges(in rimeDirectory: URL) -> [ExternalChange] {
        entries.keys.sorted().compactMap { path in
            let url = rimeDirectory.appending(path: path)
            guard Self.exists(url) else { return .deleted(path) }
            let current = try? Hashing.sha256(of: url)
            return current == entries[path]?.sha256 ? nil : .modified(path)
        }
    }

    /// 这次要写的文件里，应用之前没写过、但目录里已经有的（按路径排序）
    public func unmanagedOverwrites(_ newPaths: [String], in rimeDirectory: URL) -> [ExternalChange] {
        newPaths.sorted().compactMap { path in
            guard entries[path] == nil, Self.exists(rimeDirectory.appending(path: path)) else { return nil }
            return .unmanaged(path)
        }
    }

    /// 文件、目录、符号链接（包括指向不存在的链接）都算存在
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

public enum ExternalChange: Sendable, Equatable, CustomStringConvertible {
    case modified(String)
    case deleted(String)
    case unmanaged(String)

    public var path: String {
        switch self {
        case .modified(let p), .deleted(let p), .unmanaged(let p): return p
        }
    }

    public var description: String {
        switch self {
        case .modified(let p): return "\(p)：在应用外被改过"
        case .deleted(let p): return "\(p)：在应用外被删了"
        case .unmanaged(let p): return "\(p)：不是应用写的，这次会被覆盖"
        }
    }
}

extension FileOrigin {
    /// 写进 ledger 的来源
    public var ledgerValue: String {
        switch self {
        case .package(let id): return "package:\(id)"
        case .generated: return "generated"
        case .personal: return "personal"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 6 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Deploy/Ledger.swift Tests/RimeKitTests/LedgerTests.swift
git commit -m "feat: Ledger 记录应用写过的文件，发现外部改动

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 备份、清理、还原 `BackupStore`

**Files:**
- Create: `Sources/RimeKit/Deploy/BackupStore.swift`
- Test: `Tests/RimeKitTests/BackupStoreTests.swift`

**Interfaces:**
- Consumes: `AppPaths.backups`、`RimeFiles.configFiles`（任务 1）、`Ledger`（任务 2）。
- Produces:
  - `public struct BackupInfo: Sendable, Equatable, Codable { id: String; createdAt: Date; reason: String; permanent: Bool; files: [String]; ledger: Ledger }`（存成 `backups/<id>/meta.json`，文件在 `backups/<id>/files/…`）
  - `public enum BackupError: Error, Equatable { case notFound(String) }`
  - `public struct BackupStore: Sendable { let paths: AppPaths; init(paths:now:); func create(from rimeDirectory: URL, reason: String, permanent: Bool, ledger: Ledger) throws -> BackupInfo; func list() -> [BackupInfo] /* 新的在前 */; func info(_ id: String) -> BackupInfo?; func prune(keep: Int = 10) throws -> [String] /* 删掉的 id */; func restore(_ id: String, to rimeDirectory: URL) throws -> BackupInfo }`
  - 只备份配置文件（`RimeFiles.configFiles`）；先写到 `backups/<id>.partial`，`meta.json` 写完再改名，带 `.partial` 的不算备份。
  - `restore`：删掉目录里现有的配置文件，再复制备份里的；Rime 自己的运行文件不动。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct BackupStoreTests {
    func write(_ dir: URL, _ path: String, _ text: String) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ dir: URL, _ path: String) throws -> String {
        try String(contentsOf: dir.appending(path: path), encoding: .utf8)
    }

    @Test func 只备份配置文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "default.custom.yaml", "d")
        try write(rime, "cn_dicts/a.dict.yaml", "a")
        try write(rime, "build/default.yaml", "b")
        try write(rime, "user.yaml", "u")
        let store = BackupStore(paths: Fixtures.paths(dir))
        let ledger = Ledger(entries: ["default.custom.yaml": LedgerEntry(sha256: "x", origin: "generated")])
        let info = try store.create(from: rime, reason: "测试", permanent: true, ledger: ledger)
        #expect(info.files == ["cn_dicts/a.dict.yaml", "default.custom.yaml"])
        #expect(info.permanent)
        #expect(info.ledger == ledger)
        #expect(store.list() == [info])
        #expect(store.info(info.id) == info)
    }

    @Test func 新的在前带partial的不算() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "a.yaml", "a")
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let store = BackupStore(paths: Fixtures.paths(dir), now: clock.next)
        let first = try store.create(from: rime, reason: "1", permanent: false, ledger: Ledger())
        let second = try store.create(from: rime, reason: "2", permanent: false, ledger: Ledger())
        try FileManager.default.createDirectory(at: Fixtures.paths(dir).backups.appending(path: "x.partial"), withIntermediateDirectories: true)
        #expect(store.list().map(\.id) == [second.id, first.id])
    }

    @Test func 清理时保留最近的和永久的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "a.yaml", "a")
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let store = BackupStore(paths: Fixtures.paths(dir), now: clock.next)
        let keeper = try store.create(from: rime, reason: "第一次应用前", permanent: true, ledger: Ledger())
        var normal: [BackupInfo] = []
        for i in 0..<5 { normal.append(try store.create(from: rime, reason: "\(i)", permanent: false, ledger: Ledger())) }
        let removed = try store.prune(keep: 3)
        #expect(removed == [normal[1].id, normal[0].id])
        #expect(store.list().map(\.id) == [normal[4].id, normal[3].id, normal[2].id, keeper.id])
    }

    @Test func 还原成备份时的样子而且不动Rime自己的文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime")
        try write(rime, "a.yaml", "old")
        try write(rime, "keep/b.yaml", "b")
        let store = BackupStore(paths: Fixtures.paths(dir))
        let info = try store.create(from: rime, reason: "前", permanent: false, ledger: Ledger())
        try write(rime, "a.yaml", "new")
        try write(rime, "added.yaml", "x")
        try FileManager.default.removeItem(at: rime.appending(path: "keep/b.yaml"))
        try write(rime, "user.yaml", "runtime")
        _ = try store.restore(info.id, to: rime)
        #expect(try RimeFiles.configFiles(in: rime) == ["a.yaml", "keep/b.yaml"])
        #expect(try read(rime, "a.yaml") == "old")
        #expect(try read(rime, "user.yaml") == "runtime")
    }

    @Test func 还原不存在的备份() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(throws: BackupError.notFound("nope")) {
            try BackupStore(paths: Fixtures.paths(dir)).restore("nope", to: dir.url)
        }
    }
}
```

（`Clock` 是阶段 1 写在 `PackageStoreTests.swift` 里的测试辅助，可以直接用。）

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter BackupStoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'BackupStore' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Deploy/BackupStore.swift`**

```swift
import Foundation

public struct BackupInfo: Sendable, Equatable, Codable {
    public let id: String
    public let createdAt: Date
    public let reason: String
    /// 永久保留，清理时不删（第一次应用前的那份）
    public let permanent: Bool
    public let files: [String]
    /// 备份时的 ledger，还原时一起恢复
    public let ledger: Ledger
}

public enum BackupError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound(String)

    public var description: String {
        switch self {
        case .notFound(let id): return "找不到备份 \(id)"
        }
    }
}

/// ~/Library/Rime 配置文件的备份（设计第 7 节）。只备份配置文件，不备份 Rime 自己的运行文件。
public struct BackupStore: Sendable {
    public let paths: AppPaths
    let now: @Sendable () -> Date

    public init(paths: AppPaths, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.now = now
    }

    public func create(from rimeDirectory: URL, reason: String, permanent: Bool, ledger: Ledger) throws -> BackupInfo {
        let fm = FileManager.default
        let date = now()
        let id = Self.idFormatter.string(from: date) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
        let partial = paths.backups.appending(path: "\(id).partial", directoryHint: .isDirectory)
        let filesDir = partial.appending(path: "files", directoryHint: .isDirectory)
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let files = try RimeFiles.configFiles(in: rimeDirectory)
        for path in files {
            let target = filesDir.appending(path: path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: rimeDirectory.appending(path: path), to: target)
        }
        let info = BackupInfo(id: id, createdAt: date, reason: reason, permanent: permanent, files: files, ledger: ledger)
        try JSONCoding.encoder.encode(info).write(to: partial.appending(path: "meta.json"))
        try fm.moveItem(at: partial, to: paths.backups.appending(path: id, directoryHint: .isDirectory))
        return info
    }

    /// 所有备份，新的在前
    public func list() -> [BackupInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.backups.path)) ?? []
        return names.filter { !$0.hasSuffix(".partial") }
            .compactMap(info)
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func info(_ id: String) -> BackupInfo? {
        let meta = paths.backups.appending(path: id, directoryHint: .isDirectory).appending(path: "meta.json")
        guard let data = try? Data(contentsOf: meta) else { return nil }
        return try? JSONCoding.decoder.decode(BackupInfo.self, from: data)
    }

    /// 普通备份只留最近 keep 份；永久的都留。返回删掉的 id。
    public func prune(keep: Int = 10) throws -> [String] {
        let removable = list().filter { !$0.permanent }.dropFirst(keep).map(\.id)
        for id in removable {
            try FileManager.default.removeItem(at: paths.backups.appending(path: id, directoryHint: .isDirectory))
        }
        return removable
    }

    /// 把 Rime 目录的配置文件恢复成备份时的样子；Rime 自己的运行文件不动
    public func restore(_ id: String, to rimeDirectory: URL) throws -> BackupInfo {
        guard let info = info(id) else { throw BackupError.notFound(id) }
        let fm = FileManager.default
        for path in try RimeFiles.configFiles(in: rimeDirectory) {
            try fm.removeItem(at: rimeDirectory.appending(path: path))
        }
        let filesDir = paths.backups.appending(path: id, directoryHint: .isDirectory).appending(path: "files", directoryHint: .isDirectory)
        for path in info.files {
            let target = rimeDirectory.appending(path: path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: filesDir.appending(path: path), to: target)
        }
        return info
    }

    /// DateFormatter 不是 Sendable，每次用时新建一个
    static var idFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 5 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Deploy/BackupStore.swift Tests/RimeKitTests/BackupStoreTests.swift
git commit -m "feat: BackupStore 备份、清理、还原 Rime 配置文件

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 编译检查和错误翻译

**Files:**
- Create: `Sources/RimeKit/Deploy/RimeCompiler.swift`
- Test: `Tests/RimeKitTests/RimeLogTests.swift`

**Interfaces:**
- Consumes: `RimeLocations`（任务 1）、`Shell`。
- Produces:
  - `public struct CompileReport: Sendable, Equatable { succeeded: Bool; errors: [String] /* 原始的 E 行 */ }`
  - `public protocol RimeCompiler: Sendable { func compile(_ directory: URL) throws -> CompileReport }`
  - `public struct DeployerCompiler: RimeCompiler { init(locations: RimeLocations) }`：成功 = 退出码 0 且没有 E 行
  - `public enum RimeLog { static func errorLines(_ text: String) -> [String]; static func explain(_ lines: [String]) -> [String] }`

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct RimeLogTests {
    let sample = """
    WARNING: Logging before InitGoogleLogging() is written to STDERR
    I20261015 14:07:26.214000 0x1 deployer.cc:1] start
    W20261015 14:07:26.214100 0x1 config.cc:1] nonexistent config file 'x'.
    E20261015 14:07:26.215025 0x1f65a7f80 dict_compiler.cc:115] neither nope.dict.yaml nor nope.table.bin exists.
    E20261015 14:07:26.215036 0x1f65a7f80 deployment_tasks.cc:376] dictionary 'nope' failed to compile.
    E20261015 14:07:26.230461 0x1f65a7f80 config_data.cc:78] Error parsing YAML "/tmp/x/demo.custom.yaml": something
    E20261015 14:07:26.231144 0x1f65a7f80 deployment_tasks.cc:338] invalid schema definition in '/tmp/x/demo.schema.yaml'.
    E20261015 14:07:26.231200 0x1f65a7f80 lua.cc:1] something odd
    E20261015 14:07:26.231300 0x1f65a7f80 deployment_tasks.cc:376] dictionary 'nope' failed to compile.
    """

    @Test func 只挑出E开头的日志行() {
        let lines = RimeLog.errorLines(sample)
        #expect(lines.count == 6)
        #expect(lines.allSatisfy { $0.hasPrefix("E2026") })
    }

    @Test func 翻译成白话去重保持顺序() {
        #expect(RimeLog.explain(RimeLog.errorLines(sample)) == [
            "找不到词库 nope（缺少 nope.dict.yaml）",
            "词库 nope 编译失败",
            "demo.custom.yaml 的格式不对（不是合法的 YAML）",
            "方案文件 demo.schema.yaml 的内容不对",
            "Rime 报错：something odd",
        ])
    }
}

/// 用宿主机鼠须管的 rime_deployer 编译临时目录（只读使用）
@Suite(.enabled(if: RimeTools.installed))
struct DeployerCompilerTests {
    func make(_ dir: TempDir, schemaDictionary: String = "demo", badPatch: Bool = false) throws -> URL {
        let d = dir.url.appending(path: "rime")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data("patch:\n  schema_list:\n    - schema: demo\n".utf8).write(to: d.appending(path: "default.custom.yaml"))
        let schema = "schema:\n  schema_id: demo\n  name: demo\nengine:\n  processors: [speller, express_editor]\n  segmentors: [abc_segmentor]\n  translators: [table_translator]\nspeller:\n  alphabet: abc\ntranslator:\n  dictionary: \(schemaDictionary)\n"
        try Data(schema.utf8).write(to: d.appending(path: "demo.schema.yaml"))
        try Data("---\nname: demo\nversion: \"1\"\n...\n你\ta\n".utf8).write(to: d.appending(path: "demo.dict.yaml"))
        if badPatch {
            try Data("patch:\n  \"translator/dictionary\": [1, 2\n".utf8).write(to: d.appending(path: "demo.custom.yaml"))
        }
        return d
    }

    @Test func 正常的能编译() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let report = try DeployerCompiler(locations: .default).compile(try make(dir))
        #expect(report == CompileReport(succeeded: true, errors: []))
    }

    @Test func 缺词库时失败() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let report = try DeployerCompiler(locations: .default).compile(try make(dir, schemaDictionary: "nope"))
        #expect(!report.succeeded)
        #expect(RimeLog.explain(report.errors).contains("找不到词库 nope（缺少 nope.dict.yaml）"))
    }

    @Test func 补丁写坏时退出码是0也算失败() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let report = try DeployerCompiler(locations: .default).compile(try make(dir, badPatch: true))
        #expect(!report.succeeded)
        #expect(RimeLog.explain(report.errors) == ["demo.custom.yaml 的格式不对（不是合法的 YAML）"])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "RimeLogTests|DeployerCompilerTests" 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'RimeLog' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Deploy/RimeCompiler.swift`**

```swift
import Foundation

public struct CompileReport: Sendable, Equatable {
    public let succeeded: Bool
    /// 原始的 E 开头的日志行
    public let errors: [String]

    public init(succeeded: Bool, errors: [String]) {
        self.succeeded = succeeded
        self.errors = errors
    }
}

/// 在一个目录上编译 Rime 配置，判断能不能用
public protocol RimeCompiler: Sendable {
    func compile(_ directory: URL) throws -> CompileReport
}

/// 用鼠须管自带的 rime_deployer 编译。补丁 YAML 写坏时退出码仍是 0，只有 E 行，所以两样都要看。
public struct DeployerCompiler: RimeCompiler {
    let locations: RimeLocations

    public init(locations: RimeLocations) {
        self.locations = locations
    }

    public func compile(_ directory: URL) throws -> CompileReport {
        let r = try Shell.run(locations.deployerBinary.path, [
            "--build", directory.path, locations.sharedSupport.path,
            directory.appending(path: "build", directoryHint: .isDirectory).path,
        ])
        let errors = RimeLog.errorLines(r.stdout + "\n" + r.stderr)
        return CompileReport(succeeded: r.status == 0 && errors.isEmpty, errors: errors)
    }
}

/// Rime（glog）日志的处理
public enum RimeLog {
    /// E 开头的错误行：E20261015 14:07:26.214222 0x… file.cc:86] 内容
    public static func errorLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { line in
            line.first == "E" && line.dropFirst().prefix(8).count == 8 && line.dropFirst().prefix(8).allSatisfy(\.isNumber)
        }
    }

    /// 把错误行翻译成白话，去重，保持顺序
    public static func explain(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let message = line.range(of: "] ").map { String(line[$0.upperBound...]) } ?? line
            let text = translate(message)
            if !result.contains(text) { result.append(text) }
        }
        return result
    }

    static func translate(_ message: String) -> String {
        if let m = message.firstMatch(of: /neither (.+)\.dict\.yaml nor/) {
            return "找不到词库 \(m.1)（缺少 \(m.1).dict.yaml）"
        }
        if let m = message.firstMatch(of: /dictionary '([^']+)' failed to compile/) {
            return "词库 \(m.1) 编译失败"
        }
        if let m = message.firstMatch(of: /Error parsing YAML "([^"]+)"/) {
            return "\((String(m.1) as NSString).lastPathComponent) 的格式不对（不是合法的 YAML）"
        }
        if let m = message.firstMatch(of: /invalid schema definition in '([^']+)'/) {
            return "方案文件 \((String(m.1) as NSString).lastPathComponent) 的内容不对"
        }
        return "Rime 报错：\(message)"
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 5 个；宿主机没装鼠须管时编译的 3 个跳过）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Deploy/RimeCompiler.swift Tests/RimeKitTests/RimeLogTests.swift
git commit -m "feat: 编译检查（退出码和 E 行都看）和 Rime 错误的白话翻译

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 通知鼠须管、等部署完、锁文件

**Files:**
- Create: `Sources/RimeKit/Deploy/SquirrelControl.swift`
- Create: `Sources/RimeKit/Deploy/DeployWatcher.swift`
- Create: `Sources/RimeKit/Deploy/ApplyLock.swift`
- Create: `Tests/RimeKitTests/Support/DeployFakes.swift`
- Test: `Tests/RimeKitTests/DeployWatcherTests.swift`
- Test: `Tests/RimeKitTests/ApplyLockTests.swift`

**Interfaces:**
- Consumes: `RimeLocations`（任务 1）、`RimeLog`（任务 4）、`Shell`、`YAMLNode`。
- Produces:
  - `public protocol SquirrelControlling: Sendable { func isRunning() -> Bool; func reload() throws; func launch() throws }`；`public struct SquirrelControl: SquirrelControlling { init(locations:) }`（`pgrep -x -U <uid> Squirrel`、`Squirrel --reload`、`open <Squirrel.app>`）；`public enum SquirrelError: Error, Equatable { case commandFailed(String, String) }`
  - `public struct LogSnapshot: Sendable, Equatable`；`public struct DeployOutcome: Sendable, Equatable { finished: Bool; errors: [String] /* 已翻译 */ }`
  - `public struct DeployWatcher: Sendable { init(locations:pollInterval:timeout:sleep:); func lastBuildTime() -> Int?; func snapshot() -> LogSnapshot; func newErrorLines(since: LogSnapshot) -> [String]; func wait(previousBuildTime: Int?, since: LogSnapshot) async -> DeployOutcome }`
  - `public final class ApplyLock { static func acquire(_ paths: AppPaths) throws -> ApplyLock }`（`flock` 非阻塞；拿不到时抛 `ApplyError.busy`；对象释放时解锁）
  - `public enum ApplyError: Error, Equatable, CustomStringConvertible { case busy, squirrelNotInstalled, writeFailed(String, restored: Bool) }`（放在 `ApplyLock.swift`，任务 6 继续用）
  - 测试辅助（`DeployFakes.swift`）：`FakeCompiler`、`FakeSquirrel`（`reload`/`launch` 时往 Rime 目录写新的 `user.yaml` 模拟部署，可选往日志目录写一行错误）、`DeployFixtures.locations(_ dir:)`（临时的「鼠须管」：带可执行的 `rime_deployer` 空文件；Rime 目录 `dir/Rime`；日志目录 `dir/logs`）、`DeployFixtures.watcher(_ locations:)`（不等待、很快超时）

- [ ] **Step 1: 写测试辅助 `Tests/RimeKitTests/Support/DeployFakes.swift`**

```swift
import Foundation
@testable import RimeKit

/// 假的编译器：返回事先设置好的结果
struct FakeCompiler: RimeCompiler {
    var report = CompileReport(succeeded: true, errors: [])
    func compile(_ directory: URL) throws -> CompileReport { report }
}

/// 假的鼠须管：reload / launch 时往 Rime 目录写一个新的 user.yaml（模拟部署完成），
/// errorLine 不为空时同时往日志目录的 ERROR 文件追加一行
final class FakeSquirrel: SquirrelControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let locations: RimeLocations
    private var running: Bool
    private var buildTime = 1_000
    private var log: [String] = []
    var errorLine: String?

    init(locations: RimeLocations, running: Bool) {
        self.locations = locations
        self.running = running
    }

    var calls: [String] { lock.withLock { log } }

    func isRunning() -> Bool { lock.withLock { running } }

    func reload() throws {
        lock.withLock { log.append("reload") }
        try simulateDeploy()
    }

    func launch() throws {
        lock.withLock {
            log.append("launch")
            running = true
        }
        try simulateDeploy()
    }

    private func simulateDeploy() throws {
        let time = lock.withLock { () -> Int in
            buildTime += 1
            return buildTime
        }
        let fm = FileManager.default
        try fm.createDirectory(at: locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("var:\n  last_build_time: \(time)\n".utf8).write(to: locations.rimeDirectory.appending(path: "user.yaml"))
        if let errorLine {
            try fm.createDirectory(at: locations.logDirectory, withIntermediateDirectories: true)
            let file = locations.logDirectory.appending(path: "rime.squirrel.host.user.log.ERROR.20261015-000000.1")
            let old = (try? Data(contentsOf: file)) ?? Data()
            try (old + Data((errorLine + "\n").utf8)).write(to: file)
        }
    }
}

enum DeployFixtures {
    /// 临时的「鼠须管」（只有一个可执行的空 rime_deployer，让 squirrelInstalled 为真）、Rime 目录、日志目录
    static func locations(_ dir: TempDir) throws -> RimeLocations {
        let fm = FileManager.default
        let app = dir.url.appending(path: "Squirrel.app", directoryHint: .isDirectory)
        let deployer = app.appending(path: "Contents/MacOS/rime_deployer")
        try fm.createDirectory(at: deployer.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: deployer)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deployer.path)
        return RimeLocations(
            rimeDirectory: dir.url.appending(path: "Rime", directoryHint: .isDirectory),
            squirrelApp: app,
            logDirectory: dir.url.appending(path: "logs", directoryHint: .isDirectory))
    }

    /// 不真的等待、很快超时的观察器
    static func watcher(_ locations: RimeLocations) -> DeployWatcher {
        DeployWatcher(locations: locations, pollInterval: .milliseconds(1), timeout: .milliseconds(20), sleep: { _ in })
    }
}
```

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/DeployWatcherTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployWatcherTests {
    @Test func 读部署时间() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let w = DeployFixtures.watcher(l)
        #expect(w.lastBuildTime() == nil)
        try FileManager.default.createDirectory(at: l.rimeDirectory, withIntermediateDirectories: true)
        try Data("var:\n  last_build_time: 1792040893\n  previously_selected_schema: x\n".utf8)
            .write(to: l.rimeDirectory.appending(path: "user.yaml"))
        #expect(w.lastBuildTime() == 1_792_040_893)
    }

    @Test func 部署时间变了就算完成并带上新的错误() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let squirrel = FakeSquirrel(locations: l, running: true)
        try squirrel.reload()   // 先部署一次，留下旧的部署时间和一行旧错误
        squirrel.errorLine = "E20261015 14:00:00.000000 0x1 a.cc:1] old"
        try squirrel.reload()
        let w = DeployFixtures.watcher(l)
        let previous = w.lastBuildTime()
        let snapshot = w.snapshot()
        squirrel.errorLine = "E20261015 14:00:01.000000 0x1 a.cc:1] dictionary 'nope' failed to compile."
        try squirrel.reload()
        let outcome = await w.wait(previousBuildTime: previous, since: snapshot)
        #expect(outcome == DeployOutcome(finished: true, errors: ["词库 nope 编译失败"]))
    }

    @Test func 一直没部署就超时() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let w = DeployFixtures.watcher(l)
        let outcome = await w.wait(previousBuildTime: nil, since: w.snapshot())
        #expect(outcome == DeployOutcome(finished: false, errors: []))
    }

    @Test func 原来没有user_yaml部署后出现了也算完成() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let l = try DeployFixtures.locations(dir)
        let w = DeployFixtures.watcher(l)
        let snapshot = w.snapshot()
        try FakeSquirrel(locations: l, running: false).launch()
        #expect(await w.wait(previousBuildTime: nil, since: snapshot).finished)
    }
}
```

`Tests/RimeKitTests/ApplyLockTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct ApplyLockTests {
    @Test func 同时只能有一个() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        var first: ApplyLock? = try ApplyLock.acquire(paths)
        #expect(throws: ApplyError.busy) { try ApplyLock.acquire(paths) }
        _ = first
        first = nil
        _ = try ApplyLock.acquire(paths)
    }

    @Test func 错误信息是中文() {
        #expect(ApplyError.busy.description == "正在应用改动，请稍等再试")
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter "DeployWatcherTests|ApplyLockTests" 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find type 'SquirrelControlling' in scope`（或 `DeployWatcher`）。

- [ ] **Step 4: 写 `Sources/RimeKit/Deploy/SquirrelControl.swift`**

```swift
import Darwin
import Foundation

/// 控制鼠须管：看在不在运行、通知重新部署、启动
public protocol SquirrelControlling: Sendable {
    func isRunning() -> Bool
    func reload() throws
    func launch() throws
}

public enum SquirrelError: Error, Equatable, Sendable, CustomStringConvertible {
    case commandFailed(String, String)

    public var description: String {
        switch self {
        case let .commandFailed(command, message): return "\(command) 失败：\(message)"
        }
    }
}

/// 真正的鼠须管。--reload 只对正在运行的鼠须管有效；没运行时要 open 启动它（实测）。
/// 需要在用户的桌面会话里运行（测试机里用 launchctl asuser）。
public struct SquirrelControl: SquirrelControlling {
    let locations: RimeLocations

    public init(locations: RimeLocations) {
        self.locations = locations
    }

    public func isRunning() -> Bool {
        (try? Shell.run("/usr/bin/pgrep", ["-x", "-U", String(getuid()), "Squirrel"]))?.status == 0
    }

    public func reload() throws {
        let r = try Shell.run(locations.squirrelBinary.path, ["--reload"])
        guard r.status == 0 else { throw SquirrelError.commandFailed("Squirrel --reload", r.stderr) }
    }

    public func launch() throws {
        let r = try Shell.run("/usr/bin/open", [locations.squirrelApp.path])
        guard r.status == 0 else { throw SquirrelError.commandFailed("open 鼠须管", r.stderr) }
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Deploy/DeployWatcher.swift`**

```swift
import Foundation

public struct DeployOutcome: Sendable, Equatable {
    /// 在超时前看到了部署完成
    public let finished: Bool
    /// 这次部署新出现的错误（已翻译成白话）
    public let errors: [String]

    public init(finished: Bool, errors: [String]) {
        self.finished = finished
        self.errors = errors
    }
}

/// 日志目录里各个 ERROR 文件当时的大小
public struct LogSnapshot: Sendable, Equatable {
    let sizes: [String: Int]
}

/// 等鼠须管部署完：user.yaml 的 var/last_build_time 每次部署都会更新（实测，配置没变也会），
/// 所以看它变没变；不看 build/ 里文件的修改时间（只改外观时方案不会重编译）。
public struct DeployWatcher: Sendable {
    let locations: RimeLocations
    let pollInterval: Duration
    let timeout: Duration
    let sleep: @Sendable (Duration) async -> Void

    public init(
        locations: RimeLocations,
        pollInterval: Duration = .seconds(1),
        timeout: Duration = .seconds(120),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.locations = locations
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.sleep = sleep
    }

    public func lastBuildTime() -> Int? {
        let url = locations.rimeDirectory.appending(path: "user.yaml")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let root = try? YAMLNode.parse(text) else { return nil }
        return root["var"]?["last_build_time"]?.int
    }

    public func snapshot() -> LogSnapshot {
        LogSnapshot(sizes: Dictionary(uniqueKeysWithValues: errorFiles().map { ($0, size(of: $0)) }))
    }

    /// 从快照之后新写进 ERROR 日志的错误行
    public func newErrorLines(since snapshot: LogSnapshot) -> [String] {
        var lines: [String] = []
        for name in errorFiles() {
            let url = locations.logDirectory.appending(path: name)
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: UInt64(snapshot.sizes[name] ?? 0))
            let data = (try? handle.readToEnd()) ?? Data()
            lines += RimeLog.errorLines(String(decoding: data, as: UTF8.self))
        }
        return lines
    }

    public func wait(previousBuildTime: Int?, since snapshot: LogSnapshot) async -> DeployOutcome {
        var waited = Duration.zero
        while waited < timeout {
            if let time = lastBuildTime(), time != previousBuildTime {
                await sleep(pollInterval)   // 让错误日志写完（glog 有缓冲）
                return DeployOutcome(finished: true, errors: RimeLog.explain(newErrorLines(since: snapshot)))
            }
            await sleep(pollInterval)
            waited += pollInterval
        }
        return DeployOutcome(finished: false, errors: RimeLog.explain(newErrorLines(since: snapshot)))
    }

    /// 日志目录里的 ERROR 文件名（rime.squirrel.<主机>.<用户>.log.ERROR.<时间>.<进程号>）
    private func errorFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: locations.logDirectory.path)) ?? []
        return names.filter { $0.contains(".log.ERROR.") }.sorted()
    }

    private func size(of name: String) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: locations.logDirectory.appending(path: name).path)
        return (attributes?[.size] as? Int) ?? 0
    }
}
```

- [ ] **Step 6: 写 `Sources/RimeKit/Deploy/ApplyLock.swift`**

```swift
import Darwin
import Foundation

public enum ApplyError: Error, Equatable, Sendable, CustomStringConvertible {
    case busy
    case squirrelNotInstalled
    case writeFailed(String, restored: Bool)

    public var description: String {
        switch self {
        case .busy:
            return "正在应用改动，请稍等再试"
        case .squirrelNotInstalled:
            return "还没有安装鼠须管"
        case let .writeFailed(message, restored):
            return restored
                ? "写入配置时出错，已经自动还原成写入前的样子：\(message)"
                : "写入配置时出错，自动还原也失败了，请用 rimectl restore 手动还原：\(message)"
        }
    }
}

/// 锁文件：同一时间只允许一个应用改动（应用和 rimectl 共用）。对象释放时解锁。
public final class ApplyLock {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public static func acquire(_ paths: AppPaths) throws -> ApplyLock {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let fd = open(paths.lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw ApplyError.busy }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw ApplyError.busy
        }
        return ApplyLock(descriptor: fd)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
```

- [ ] **Step 7: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 6 个）。

- [ ] **Step 8: 提交**

```bash
git add Sources/RimeKit/Deploy Tests/RimeKitTests
git commit -m "feat: 通知鼠须管、按 last_build_time 等部署完、锁文件

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `Deployer.apply`：应用改动（设计 6.1）

**Files:**
- Create: `Sources/RimeKit/Deploy/Deployer.swift`
- Test: `Tests/RimeKitTests/DeployerTests.swift`

**Interfaces:**
- Consumes: 任务 1–5 的全部；`ConfigGenerator`、`GenerationInput`、`PersonalContent`（阶段 2）；`GenFixtures`（阶段 2 测试辅助）。
- Produces:
  - `public struct ApplyOptions: Sendable, Equatable { var overwriteExternalChanges: Bool; var adoptPersonalChanges: Bool; init(overwriteExternalChanges: = false, adoptPersonalChanges: = false) }`
  - `public struct ApplyReport: Sendable, Equatable { backup: BackupInfo; written: [String]; unchanged: Int; removed: [String]; launched: Bool; deploy: DeployOutcome; warnings: [String] }`
  - `public enum ApplyOutcome: Sendable, Equatable { case applied(ApplyReport); case externalChanges([ExternalChange]); case compileFailed([String]) }`
  - `public struct Deployer: Sendable { let paths: AppPaths; let locations: RimeLocations; init(paths:locations:compiler:squirrel:watcher:now:); func apply(_ input: GenerationInput, options: ApplyOptions = ApplyOptions()) async throws -> ApplyOutcome }`
  - 流程：锁 → 检查已管理文件的外部改动（`adoptPersonalChanges` 时把被改过的个人词库收回 `personal/dicts/`，重读个人内容）→ 在 `staging/apply-<uuid>/generated` 生成 → 加上「要覆盖应用不管的文件」→ 有外部改动且没让覆盖就返回 `.externalChanges`（什么都不写）→ 在 `staging/apply-<uuid>/full` 拼出完整目录（现有的、应用不管也不会覆盖的配置文件 + 新生成的）→ 编译，失败返回 `.compileFailed`（已翻译，什么都不写）→ 备份（ledger 为空且目录里已有配置时永久保留）→ 逐个文件「临时文件 + rename」写入，哈希没变的跳过；删掉 ledger 里有、这次不再需要的文件；写新 ledger；出错就用刚才的备份还原并抛 `ApplyError.writeFailed` → 清理旧备份 → 通知鼠须管（在运行就 `reload`，否则 `launch`）→ 等部署完 → 返回 `.applied`。
  - 暂存目录用完就删。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployerTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let squirrel: FakeSquirrel
        let packages: [String: CachedPackage]
        var rime: URL { locations.rimeDirectory }

        func deployer(compiler: FakeCompiler = FakeCompiler()) -> Deployer {
            Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                     watcher: DeployFixtures.watcher(locations), now: { Date(timeIntervalSince1970: 1_000) })
        }

        func input(_ settings: Settings) throws -> GenerationInput {
            try GenFixtures.input(settings, packages: packages, personal: try PersonalContent.load(from: paths))
        }

        func write(_ path: String, _ text: String) throws {
            let url = rime.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func read(_ path: String) throws -> String {
            try String(contentsOf: rime.appending(path: path), encoding: .utf8)
        }
    }

    func env(running: Bool = false) throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let locations = try DeployFixtures.locations(dir)
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        return Env(dir: dir, paths: paths, locations: locations,
                   squirrel: FakeSquirrel(locations: locations, running: running), packages: packages)
    }

    func applied(_ outcome: ApplyOutcome) throws -> ApplyReport {
        guard case .applied(let report) = outcome else {
            Issue.record("应该写入成功，实际是 \(outcome)")
            throw CancellationError()
        }
        return report
    }

    @Test func 第一次应用到空目录() async throws {
        let e = try env(); defer { e.dir.remove() }
        let report = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"]))))
        #expect(report.written.contains("default.custom.yaml"))
        #expect(report.written.contains("wb.schema.yaml"))
        #expect(report.removed.isEmpty)
        #expect(report.launched)
        #expect(e.squirrel.calls == ["launch"])
        #expect(report.deploy == DeployOutcome(finished: true, errors: []))
        #expect(report.backup.reason == "第一次应用前")
        #expect(!report.backup.permanent)   // 原来是空的，不用永久保留
        let ledger = try Ledger.load(e.paths)
        #expect(Set(ledger.entries.keys) == Set(report.written))
        #expect(ledger.entries["wb.dict.yaml"]?.origin == "package:wubi")
        #expect(ledger.appliedAt == Date(timeIntervalSince1970: 1_000))
        #expect(try e.read("default.custom.yaml").hasPrefix(Patch.header))
        let staging = (try? FileManager.default.contentsOfDirectory(atPath: e.paths.staging.path)) ?? []
        #expect(staging.isEmpty)
    }

    @Test func 要覆盖应用不管的文件时先列出来什么都不写() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "mine")
        try e.write("my_notes.txt", "notes")
        let outcome = try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])))
        #expect(outcome == .externalChanges([.unmanaged("default.custom.yaml")]))
        #expect(try RimeFiles.configFiles(in: e.rime) == ["default.custom.yaml", "my_notes.txt"])
        #expect(try e.read("default.custom.yaml") == "mine")
        #expect(BackupStore(paths: e.paths).list().isEmpty)
        #expect(e.squirrel.calls.isEmpty)
    }

    @Test func 让覆盖时先永久备份再写不认识的文件不动() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "mine")
        try e.write("my_notes.txt", "notes")
        let report = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])),
                                                              options: ApplyOptions(overwriteExternalChanges: true)))
        #expect(report.backup.permanent)
        #expect(report.backup.files == ["default.custom.yaml", "my_notes.txt"])
        #expect(try e.read("my_notes.txt") == "notes")
        #expect(try e.read("default.custom.yaml").hasPrefix(Patch.header))
    }

    @Test func 应用管理的文件被外部改过或删了() async throws {
        let e = try env(); defer { e.dir.remove() }
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"]))))
        try e.write("default.custom.yaml", "hand edited")
        try FileManager.default.removeItem(at: e.rime.appending(path: "py.dict.yaml"))
        let outcome = try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"])))
        #expect(outcome == .externalChanges([.modified("default.custom.yaml"), .deleted("py.dict.yaml")]))
        #expect(try e.read("default.custom.yaml") == "hand edited")
    }

    @Test func 采用个人词库的外部修改() async throws {
        let e = try env(); defer { e.dir.remove() }
        try FileManager.default.createDirectory(at: e.paths.personalDicts, withIntermediateDirectories: true)
        try Data(GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"]).utf8).write(to: e.paths.personalDicts.appending(path: "py_user.dict.yaml"))
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"]))))
        let edited = GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1", "海豚\thai tun\t1"])
        try e.write("py_user.dict.yaml", edited)
        #expect(try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"])))
                == .externalChanges([.modified("py_user.dict.yaml")]))
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wpy"])),
                                                     options: ApplyOptions(adoptPersonalChanges: true)))
        #expect(try String(contentsOf: e.paths.personalDicts.appending(path: "py_user.dict.yaml"), encoding: .utf8) == edited)
        #expect(try e.read("py_user.dict.yaml") == edited)
        #expect(try Ledger.load(e.paths).externalChanges(in: e.rime).isEmpty)
    }

    @Test func 编译失败时什么都不写() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("my_notes.txt", "notes")
        let compiler = FakeCompiler(report: CompileReport(succeeded: false, errors: [
            "E20261015 14:07:26.215025 0x1 dict_compiler.cc:115] neither nope.dict.yaml nor nope.table.bin exists.",
        ]))
        let outcome = try await e.deployer(compiler: compiler).apply(try e.input(Settings(schemas: ["wb"])))
        #expect(outcome == .compileFailed(["找不到词库 nope（缺少 nope.dict.yaml）"]))
        #expect(try RimeFiles.configFiles(in: e.rime) == ["my_notes.txt"])
        #expect(BackupStore(paths: e.paths).list().isEmpty)
        #expect(try Ledger.load(e.paths) == Ledger())
    }

    @Test func 第二次只写变了的删掉不再需要的() async throws {
        let e = try env(running: true); defer { e.dir.remove() }
        _ = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb", "py"]))))
        var settings = Settings(schemas: ["wb"])
        settings.appearance.fontPoint = 24
        let report = try applied(try await e.deployer().apply(try e.input(settings)))
        #expect(report.removed.contains("py.schema.yaml"))
        #expect(!FileManager.default.fileExists(atPath: e.rime.appending(path: "py.schema.yaml").path))
        #expect(report.written.contains("squirrel.custom.yaml"))
        #expect(!report.written.contains("wb.dict.yaml"))
        #expect(report.unchanged > 0)
        #expect(report.backup.reason == "应用改动前")
        #expect(e.squirrel.calls == ["reload", "reload"])
        #expect(!report.launched)
    }

    @Test func 写到一半失败自动还原() async throws {
        let e = try env(); defer { e.dir.remove() }
        try e.write("keep.txt", "keep")
        // 有一个和要写的文件同名的空目录，rename 会失败
        try FileManager.default.createDirectory(at: e.rime.appending(path: "wb.dict.yaml"), withIntermediateDirectories: true)
        let error = await #expect(throws: ApplyError.self) {
            try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])), options: ApplyOptions(overwriteExternalChanges: true))
        }
        guard case .writeFailed(_, let restored) = error else {
            Issue.record("应该是 writeFailed，实际是 \(String(describing: error))")
            return
        }
        #expect(restored)
        #expect(try RimeFiles.configFiles(in: e.rime) == ["keep.txt"])
        #expect(try Ledger.load(e.paths) == Ledger())
        #expect(e.squirrel.calls.isEmpty)
    }

    @Test func 部署日志有错误时报告出来() async throws {
        let e = try env(running: true); defer { e.dir.remove() }
        e.squirrel.errorLine = "E20261015 14:07:26.231144 0x1 deployment_tasks.cc:338] invalid schema definition in '/x/wb.schema.yaml'."
        let report = try applied(try await e.deployer().apply(try e.input(Settings(schemas: ["wb"]))))
        #expect(report.deploy == DeployOutcome(finished: true, errors: ["方案文件 wb.schema.yaml 的内容不对"]))
    }

    @Test func 同时应用时后来的被挡住() async throws {
        let e = try env(); defer { e.dir.remove() }
        let held = try ApplyLock.acquire(e.paths)
        await #expect(throws: ApplyError.busy) {
            try await e.deployer().apply(try e.input(Settings(schemas: ["wb"])))
        }
        _ = held
    }

    @Test func 没装鼠须管() async throws {
        let e = try env(); defer { e.dir.remove() }
        var locations = e.locations
        locations.squirrelApp = e.dir.url.appending(path: "NoSuch.app")
        let deployer = Deployer(paths: e.paths, locations: locations, compiler: FakeCompiler(), squirrel: e.squirrel,
                                watcher: DeployFixtures.watcher(locations))
        await #expect(throws: ApplyError.squirrelNotInstalled) {
            try await deployer.apply(try e.input(Settings(schemas: ["wb"])))
        }
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DeployerTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'Deployer' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Deploy/Deployer.swift`**

```swift
import Darwin
import Foundation

public struct ApplyOptions: Sendable, Equatable {
    /// 外部改动、应用不管的文件也照样覆盖（先备份）
    public var overwriteExternalChanges: Bool
    /// 在应用外改过的个人词库，收回到 personal/ 当正本
    public var adoptPersonalChanges: Bool

    public init(overwriteExternalChanges: Bool = false, adoptPersonalChanges: Bool = false) {
        self.overwriteExternalChanges = overwriteExternalChanges
        self.adoptPersonalChanges = adoptPersonalChanges
    }
}

public struct ApplyReport: Sendable, Equatable {
    public let backup: BackupInfo
    public let written: [String]
    public let unchanged: Int
    public let removed: [String]
    /// 鼠须管原来没运行，这次启动了它
    public let launched: Bool
    public let deploy: DeployOutcome
    public let warnings: [String]
}

public enum ApplyOutcome: Sendable, Equatable {
    case applied(ApplyReport)
    /// 有外部改动，没让覆盖，什么都没写
    case externalChanges([ExternalChange])
    /// 暂存区编译失败（已翻译），什么都没写
    case compileFailed([String])
}

/// 把设置应用到真实的 ~/Library/Rime（设计 6.1）
public struct Deployer: Sendable {
    public let paths: AppPaths
    public let locations: RimeLocations
    let compiler: any RimeCompiler
    let squirrel: any SquirrelControlling
    let watcher: DeployWatcher
    let now: @Sendable () -> Date

    public init(
        paths: AppPaths,
        locations: RimeLocations,
        compiler: any RimeCompiler,
        squirrel: any SquirrelControlling,
        watcher: DeployWatcher,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.locations = locations
        self.compiler = compiler
        self.squirrel = squirrel
        self.watcher = watcher
        self.now = now
    }

    public func apply(_ input: GenerationInput, options: ApplyOptions = ApplyOptions()) async throws -> ApplyOutcome {
        guard locations.squirrelInstalled else { throw ApplyError.squirrelNotInstalled }
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let fm = FileManager.default
        let rime = locations.rimeDirectory
        let ledger = try Ledger.load(paths)
        var input = input

        // 1. 已管理的文件有没有在应用外被改过；需要的话把个人词库的修改收回来
        var changes = ledger.externalChanges(in: rime)
        if options.adoptPersonalChanges {
            let adopted = try adoptPersonal(changes, ledger: ledger)
            if !adopted.isEmpty {
                input.personal = try PersonalContent.load(from: paths)
                changes.removeAll { adopted.contains($0.path) }
            }
        }

        // 2. 在暂存区生成
        let work = paths.staging.appending(path: "apply-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        let generated = work.appending(path: "generated", directoryHint: .isDirectory)
        let result = try ConfigGenerator().generate(input, into: generated)
        let newPaths = result.files.map(\.path)
        changes += ledger.unmanagedOverwrites(newPaths, in: rime)
        if !changes.isEmpty, !options.overwriteExternalChanges {
            return .externalChanges(changes)
        }

        // 3. 拼出完整的目录编译：现有的、应用不管也不会覆盖的配置文件 + 新生成的
        let full = work.appending(path: "full", directoryHint: .isDirectory)
        let existing = try RimeFiles.configFiles(in: rime)
        let newSet = Set(newPaths)
        for path in existing where ledger.entries[path] == nil && !newSet.contains(path) {
            try Self.copy(rime.appending(path: path), to: full.appending(path: path))
        }
        for path in newPaths {
            try Self.copy(generated.appending(path: path), to: full.appending(path: path))
        }
        let compiled = try compiler.compile(full)
        guard compiled.succeeded else { return .compileFailed(RimeLog.explain(compiled.errors)) }

        // 4. 备份
        let backups = BackupStore(paths: paths, now: now)
        let first = ledger.entries.isEmpty
        let backup = try backups.create(from: rime, reason: first ? "第一次应用前" : "应用改动前",
                                        permanent: first && !existing.isEmpty, ledger: ledger)

        // 5. 写入；出错就用刚才的备份还原
        var written: [String] = []
        var unchanged = 0
        var removed: [String] = []
        do {
            try fm.createDirectory(at: rime, withIntermediateDirectories: true)
            var newLedger = Ledger(appliedAt: now())
            for file in result.files {
                let source = generated.appending(path: file.path)
                let sha = try Hashing.sha256(of: source)
                newLedger.entries[file.path] = LedgerEntry(sha256: sha, origin: file.origin.ledgerValue)
                let target = rime.appending(path: file.path)
                if ledger.entries[file.path]?.sha256 == sha, (try? Hashing.sha256(of: target)) == sha {
                    unchanged += 1
                    continue
                }
                try Self.replace(target, with: source)
                written.append(file.path)
            }
            for path in ledger.entries.keys.sorted() where newLedger.entries[path] == nil {
                let url = rime.appending(path: path)
                if Ledger.exists(url) {
                    try fm.removeItem(at: url)
                    removed.append(path)
                }
            }
            try newLedger.save(paths)
        } catch {
            let restored = (try? backups.restore(backup.id, to: rime)) != nil
            if restored { try? ledger.save(paths) }
            throw ApplyError.writeFailed(String(describing: error), restored: restored)
        }
        _ = try? backups.prune()

        // 6. 通知鼠须管，等部署完
        let (launched, deploy, notifyWarnings) = await notifySquirrel()
        return .applied(ApplyReport(backup: backup, written: written, unchanged: unchanged, removed: removed,
                                    launched: launched, deploy: deploy, warnings: result.warnings + notifyWarnings))
    }

    // MARK: 内部

    /// 在运行就 --reload，没运行就启动；然后等部署完
    func notifySquirrel() async -> (launched: Bool, deploy: DeployOutcome, warnings: [String]) {
        let previous = watcher.lastBuildTime()
        let snapshot = watcher.snapshot()
        var launched = false
        var warnings: [String] = []
        do {
            if squirrel.isRunning() {
                try squirrel.reload()
            } else {
                try squirrel.launch()
                launched = true
            }
        } catch {
            warnings.append("通知鼠须管失败：\(error)")
        }
        let deploy = await watcher.wait(previousBuildTime: previous, since: snapshot)
        return (launched, deploy, warnings)
    }

    /// 把在应用外改过的个人词库复制回 personal/dicts/，返回收回的路径
    private func adoptPersonal(_ changes: [ExternalChange], ledger: Ledger) throws -> [String] {
        var adopted: [String] = []
        for case .modified(let path) in changes where ledger.entries[path]?.origin == FileOrigin.personal.ledgerValue {
            let target = paths.personalDicts.appending(path: (path as NSString).lastPathComponent)
            try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
            try Self.replace(target, with: locations.rimeDirectory.appending(path: path))
            adopted.append(path)
        }
        return adopted
    }

    static func copy(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
    }

    /// 先复制成同目录下的临时文件，再 rename 过去：不会出现写了一半的文件
    static func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temp = parent.appending(path: ".\(target.lastPathComponent).squirrel-macos-tmp")
        try? fm.removeItem(at: temp)
        try fm.copyItem(at: source, to: temp)
        guard rename(temp.path, target.path) == 0 else {
            let code = errno
            try? fm.removeItem(at: temp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
```

`RimeFiles.isRimeOwned` 里再加一条，让写到一半残留的临时文件不被当成配置文件：

```swift
        if name.hasPrefix(".") && name.hasSuffix(".squirrel-macos-tmp") { return true }
```

（加在 `if name == ".DS_Store" { return true }` 后面。）

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test|Expectation failed" | head -8`
Expected: 全部通过（新增 11 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Deploy Tests/RimeKitTests/DeployerTests.swift
git commit -m "feat: Deployer 应用改动：外部改动先问、编译校验、备份、原子写入、失败还原、通知部署

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 还原和状态

**Files:**
- Modify: `Sources/RimeKit/Deploy/Deployer.swift`
- Test: `Tests/RimeKitTests/DeployerRestoreTests.swift`

**Interfaces:**
- Consumes: `Deployer`（任务 6）、`BackupStore`、`Ledger`。
- Produces:
  - `public struct RestoreReport: Sendable, Equatable { restored: BackupInfo; safetyBackup: BackupInfo; launched: Bool; deploy: DeployOutcome; warnings: [String] }`
  - `public struct DeployStatus: Sendable, Equatable { squirrelInstalled: Bool; squirrelRunning: Bool; rimeDirectory: URL; managedFiles: Int; appliedAt: Date?; externalChanges: [ExternalChange]; backups: [BackupInfo] }`
  - `Deployer.restore(_ id: String) async throws -> RestoreReport`：锁 → 找不到抛 `BackupError.notFound` → 先给当前状态做「还原前」备份 → 还原文件 → ledger 换成备份里的 → 通知鼠须管、等部署。
  - `Deployer.status() throws -> DeployStatus`

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct DeployerRestoreTests {
    func setup() async throws -> (DeployerTests.Env, Deployer) {
        let e = try DeployerTests().env(running: true)
        let deployer = e.deployer()
        guard case .applied = try await deployer.apply(try e.input(Settings(schemas: ["wb", "py"]))) else {
            throw CancellationError()
        }
        var settings = Settings(schemas: ["wb"])
        settings.appearance.fontPoint = 24
        guard case .applied = try await deployer.apply(try e.input(settings)) else { throw CancellationError() }
        return (e, deployer)
    }

    @Test func 还原到上一次应用前() async throws {
        let (e, deployer) = try await setup(); defer { e.dir.remove() }
        let backups = BackupStore(paths: e.paths).list()
        let beforeSecond = try #require(backups.first { $0.reason == "应用改动前" })
        let report = try await deployer.restore(beforeSecond.id)
        #expect(report.restored == beforeSecond)
        #expect(report.safetyBackup.reason == "还原前")
        #expect(FileManager.default.fileExists(atPath: e.rime.appending(path: "py.schema.yaml").path))
        #expect(!(try e.read("squirrel.custom.yaml")).contains("24"))
        #expect(try Ledger.load(e.paths) == beforeSecond.ledger)
        #expect(try Ledger.load(e.paths).externalChanges(in: e.rime).isEmpty)
        #expect(report.deploy.finished)
        #expect(e.squirrel.calls.last == "reload")
    }

    @Test func 还原不存在的备份() async throws {
        let (e, deployer) = try await setup(); defer { e.dir.remove() }
        await #expect(throws: BackupError.notFound("nope")) { try await deployer.restore("nope") }
    }

    @Test func 状态() async throws {
        let (e, deployer) = try await setup(); defer { e.dir.remove() }
        try e.write("default.custom.yaml", "hand edited")
        let s = try deployer.status()
        #expect(s.squirrelInstalled)
        #expect(s.squirrelRunning)
        #expect(s.rimeDirectory == e.rime)
        #expect(s.managedFiles == (try Ledger.load(e.paths)).entries.count)
        #expect(s.externalChanges == [.modified("default.custom.yaml")])
        #expect(s.backups.count == 2)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter DeployerRestoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `value of type 'Deployer' has no member 'restore'`。

- [ ] **Step 3: 在 `Deployer.swift` 加**

在文件里 `public enum ApplyOutcome` 后面加：

```swift
public struct RestoreReport: Sendable, Equatable {
    public let restored: BackupInfo
    /// 还原前给当时的状态做的备份，还原也能撤销
    public let safetyBackup: BackupInfo
    public let launched: Bool
    public let deploy: DeployOutcome
    public let warnings: [String]
}

public struct DeployStatus: Sendable, Equatable {
    public let squirrelInstalled: Bool
    public let squirrelRunning: Bool
    public let rimeDirectory: URL
    public let managedFiles: Int
    public let appliedAt: Date?
    public let externalChanges: [ExternalChange]
    public let backups: [BackupInfo]
}
```

在 `Deployer` 里 `// MARK: 内部` 前面加：

```swift
    /// 还原到某个备份：先备份当前状态（「还原前」），再还原文件和 ledger，然后通知鼠须管
    public func restore(_ id: String) async throws -> RestoreReport {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let backups = BackupStore(paths: paths, now: now)
        guard let target = backups.info(id) else { throw BackupError.notFound(id) }
        let safety = try backups.create(from: locations.rimeDirectory, reason: "还原前", permanent: false,
                                        ledger: try Ledger.load(paths))
        let restored = try backups.restore(target.id, to: locations.rimeDirectory)
        try restored.ledger.save(paths)
        _ = try? backups.prune()
        let (launched, deploy, warnings) = await notifySquirrel()
        return RestoreReport(restored: restored, safetyBackup: safety, launched: launched, deploy: deploy, warnings: warnings)
    }

    public func status() throws -> DeployStatus {
        let ledger = try Ledger.load(paths)
        return DeployStatus(
            squirrelInstalled: locations.squirrelInstalled,
            squirrelRunning: squirrel.isRunning(),
            rimeDirectory: locations.rimeDirectory,
            managedFiles: ledger.entries.count,
            appliedAt: ledger.appliedAt,
            externalChanges: ledger.externalChanges(in: locations.rimeDirectory),
            backups: BackupStore(paths: paths).list())
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test|Expectation failed" | head -6`
Expected: 全部通过（新增 3 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Deploy/Deployer.swift Tests/RimeKitTests/DeployerRestoreTests.swift
git commit -m "feat: 还原到备份（先做还原前备份）和部署状态

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `rimectl apply`、`status`、`restore`、`settings set`

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`
- Test: `Tests/RimeKitTests/RimectlApplyTests.swift`

**Interfaces:**
- Consumes: `Deployer`、`ApplyOptions`、`ApplyOutcome`、`DeployStatus`、`RestoreReport`、`BackupStore`、`RimeLocations`、`DeployWatcher`、`SquirrelControl`、`DeployerCompiler`。
- Produces:
  - `Rimectl.Context` 加字段（带默认值，原来的测试不用改）：`var locations: RimeLocations = .default`、`var compiler: (any RimeCompiler)? = nil`（空就用 `DeployerCompiler`）、`var squirrel: (any SquirrelControlling)? = nil`（空就用 `SquirrelControl`）、`var deployTimeout: Duration = .seconds(120)`、`var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }`
  - 新参数：`--rime-dir 目录`（覆盖 Rime 目录）、`--overwrite`、`--adopt-personal`、`--list`
  - 命令：
    - `rimectl apply [--data-dir] [--rime-dir] [--cache-only] [--overwrite] [--adopt-personal]`：退出码 0 = 写入并部署成功；1 = 有外部改动 / 编译失败 / 部署有错误或超时 / 其它错误
    - `rimectl status [--data-dir] [--rime-dir]`
    - `rimectl restore --list` / `rimectl restore <备份 id>`
    - `rimectl settings set <键> <值>`：键 `schemas`（逗号分隔）、`font-point`、`label-font-point`、`comment-font-point`、`page-size`、`layout`（`stacked`/`linear`）、`orientation`（`horizontal`/`vertical`）、`color-scheme`、`color-scheme-dark`（值写 `-` 表示清空，恢复上游默认）、`option`（值写 `包.选项=选择`）

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlApplyTests {
    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let squirrel: FakeSquirrel
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", locations.rimeDirectory.path], context)
        }
    }

    func env() throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb", "py"]))
        let locations = try DeployFixtures.locations(dir)
        let squirrel = FakeSquirrel(locations: locations, running: true)
        let output = Output(echo: false)
        let catalog = try GenFixtures.catalog()
        let context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: paths, output: output,
            locations: locations, compiler: FakeCompiler(), squirrel: squirrel,
            deployTimeout: .milliseconds(20), sleep: { _ in })
        return Env(dir: dir, paths: paths, locations: locations, squirrel: squirrel, output: output, context: context)
    }

    @Test func apply成功() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["apply", "--cache-only"]) == 0)
        #expect(e.output.text.contains("已备份"))
        #expect(e.output.text.contains("部署完成"))
        #expect(FileManager.default.fileExists(atPath: e.locations.rimeDirectory.appending(path: "default.custom.yaml").path))
    }

    @Test func apply遇到外部改动() async throws {
        let e = try env(); defer { e.dir.remove() }
        try FileManager.default.createDirectory(at: e.locations.rimeDirectory, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: e.locations.rimeDirectory.appending(path: "default.custom.yaml"))
        #expect(await e.run(["apply", "--cache-only"]) == 1)
        #expect(e.output.text.contains("default.custom.yaml：不是应用写的，这次会被覆盖"))
        #expect(e.output.text.contains("--overwrite"))
        #expect(await e.run(["apply", "--cache-only", "--overwrite"]) == 0)
    }

    @Test func apply部署有错误时退出码是1() async throws {
        let e = try env(); defer { e.dir.remove() }
        e.squirrel.errorLine = "E20261015 14:07:26.215036 0x1 deployment_tasks.cc:376] dictionary 'wb' failed to compile."
        #expect(await e.run(["apply", "--cache-only"]) == 1)
        #expect(e.output.text.contains("词库 wb 编译失败"))
        #expect(e.output.text.contains("rimectl restore"))
    }

    @Test func status和restore() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["apply", "--cache-only"]) == 0)
        #expect(await e.run(["status"]) == 0)
        #expect(e.output.text.contains("鼠须管：已安装，正在运行"))
        #expect(e.output.text.contains("应用管理的文件："))
        #expect(await e.run(["restore", "--list"]) == 0)
        let id = try #require(BackupStore(paths: e.paths).list().first?.id)
        #expect(e.output.text.contains(id))
        #expect(await e.run(["restore", id]) == 0)
        #expect(e.output.text.contains("已还原到 \(id)"))
        #expect(await e.run(["restore", "nope"]) == 1)
        #expect(await e.run(["restore"]) == 2)
    }

    @Test func settings_set改设置() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["settings", "set", "font-point", "24"]) == 0)
        #expect(await e.run(["settings", "set", "layout", "linear"]) == 0)
        #expect(await e.run(["settings", "set", "schemas", "py,wb"]) == 0)
        #expect(await e.run(["settings", "set", "option", "wubi.pinyinDictionary=builtin"]) == 0)
        var s = try #require(try SettingsStore(paths: e.paths).load())
        #expect(s.appearance.fontPoint == 24)
        #expect(s.appearance.candidateListLayout == .linear)
        #expect(s.schemas == ["py", "wb"])
        #expect(s.options["wubi"]?["pinyinDictionary"] == "builtin")
        #expect(await e.run(["settings", "set", "font-point", "-"]) == 0)
        s = try #require(try SettingsStore(paths: e.paths).load())
        #expect(s.appearance.fontPoint == nil)
        #expect(await e.run(["settings", "set", "font-point", "999"]) == 1)
        #expect(e.output.text.contains("候选字字号是 999"))
        #expect(await e.run(["settings", "set", "nope", "1"]) == 2)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RimectlApplyTests 2>&1 | grep -E "error:" | head -3`
Expected: `extra arguments at positions … in call`（`Context` 还没有新字段）。

- [ ] **Step 3: 改 `Sources/rimectl/Rimectl.swift`**

`Context` 换成：

```swift
    struct Context: Sendable {
        var http: any HTTPClient
        var retry: RetryPolicy
        var catalog: @Sendable () throws -> Catalog
        var defaultPaths: AppPaths
        var output: Output
        var locations: RimeLocations = .default
        /// 空就用鼠须管自带的 rime_deployer
        var compiler: (any RimeCompiler)? = nil
        /// 空就控制真的鼠须管
        var squirrel: (any SquirrelControlling)? = nil
        var deployTimeout: Duration = .seconds(120)
        var sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }
```

`usage` 换成：

```swift
    static let usage = """
    用法：
      rimectl catalog                                          列出内置方案清单
      rimectl fetch [--cache-only] 包名...                      下载（或从缓存取）这些包和它们的依赖
      rimectl settings init <rime-ice|flypy|wubi-pinyin> [--force]   写入起步设置
      rimectl settings show                                    打印当前设置
      rimectl settings set <键> <值>                            改一项设置（键：schemas、font-point、label-font-point、
                                                               comment-font-point、page-size、layout、orientation、
                                                               color-scheme、color-scheme-dark、option；值写 - 表示清空）
      rimectl generate --out 目录 [--cache-only]                按设置生成一份 Rime 配置（只往空目录写）
      rimectl apply [--cache-only] [--overwrite] [--adopt-personal]   把设置应用到 Rime 目录并通知鼠须管部署
      rimectl status                                           查看鼠须管、Rime 目录、外部改动、备份
      rimectl restore --list | <备份 id>                        列出备份 / 还原到某个备份
    通用参数：--data-dir 目录（应用数据目录）  --rime-dir 目录（Rime 用户目录，默认 ~/Library/Rime）
    """
```

`run` 的参数解析：在 `var force = false` 后面加

```swift
        var rimeDir: String?
        var overwrite = false
        var adoptPersonal = false
        var listOnly = false
```

在 `case "--force":` 前面加

```swift
            case "--rime-dir":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                rimeDir = args[i + 1]
                i += 2
            case "--overwrite":
                overwrite = true
                i += 1
            case "--adopt-personal":
                adoptPersonal = true
                i += 1
            case "--list":
                listOnly = true
                i += 1
```

在 `let paths = …` 后面加

```swift
        var locations = context.locations
        if let rimeDir { locations.rimeDirectory = URL(fileURLWithPath: rimeDir, isDirectory: true) }
```

`switch command` 里加（放在 `case "fetch":` 前面）：

```swift
            case "apply":
                return try await apply(cacheOnly: cacheOnly,
                                       options: ApplyOptions(overwriteExternalChanges: overwrite, adoptPersonalChanges: adoptPersonal),
                                       paths: paths, locations: locations, context)
            case "status":
                return try status(paths: paths, locations: locations, context)
            case "restore":
                return try await restore(Array(positional.dropFirst()), listOnly: listOnly,
                                         paths: paths, locations: locations, context)
```

把 `generate` 里「读设置、取包、拼 GenerationInput」抽成一个函数，`generate` 和 `apply` 共用（`generate` 改成调用它，行为不变）：

```swift
    /// 读设置、取包、读个人内容；失败时已经输出了错误，返回 nil
    private static func prepareInput(cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> GenerationInput? {
        let out = context.output
        guard let settings = try SettingsStore(paths: paths).load() else {
            out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
            return nil
        }
        let catalog = try context.catalog()
        try settings.validate(catalog)
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return nil }
            packages[spec.id] = pkg
        }
        return GenerationInput(settings: settings, catalog: catalog, packages: packages,
                               personal: try PersonalContent.load(from: paths), textReplacementPhrases: [])
    }

    private static func generate(out target: URL, cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        if RimeDirectoryGuard.isInsideRealRimeDirectory(target) {
            out.error("拒绝：--out 指向真实的 ~/Library/Rime（\(target.path)）。generate 只往别的空目录里写")
            return 1
        }
        guard let input = try await prepareInput(cacheOnly: cacheOnly, paths: paths, context) else { return 1 }
        let result = try ConfigGenerator().generate(input, into: target)
        for warning in result.warnings { out.line("注意：\(warning)") }
        out.line("已生成 \(result.files.count) 个文件到 \(target.path)")
        return 0
    }

    private static func deployer(paths: AppPaths, locations: RimeLocations, _ context: Context) -> Deployer {
        Deployer(
            paths: paths,
            locations: locations,
            compiler: context.compiler ?? DeployerCompiler(locations: locations),
            squirrel: context.squirrel ?? SquirrelControl(locations: locations),
            watcher: DeployWatcher(locations: locations, timeout: context.deployTimeout, sleep: context.sleep))
    }

    private static func apply(cacheOnly: Bool, options: ApplyOptions, paths: AppPaths, locations: RimeLocations,
                              _ context: Context) async throws -> Int32 {
        let out = context.output
        guard let input = try await prepareInput(cacheOnly: cacheOnly, paths: paths, context) else { return 1 }
        switch try await deployer(paths: paths, locations: locations, context).apply(input, options: options) {
        case .externalChanges(let changes):
            out.error("这些文件和应用记录的不一样，没有写入：")
            for change in changes { out.error("  \(change)") }
            out.error("要覆盖就加 --overwrite（会先备份）；被改过的个人词库可以加 --adopt-personal 采用外面的修改")
            return 1
        case .compileFailed(let errors):
            out.error("新配置编译不过，没有写入：")
            for error in errors { out.error("  \(error)") }
            return 1
        case .applied(let report):
            out.line("已备份：\(report.backup.id)（\(report.backup.reason)）")
            out.line("写入 \(report.written.count) 个文件，没变 \(report.unchanged) 个，删掉 \(report.removed.count) 个")
            for warning in report.warnings { out.line("注意：\(warning)") }
            out.line(report.launched ? "已启动鼠须管" : "已通知鼠须管重新部署")
            return reportDeploy(report.deploy, backupID: report.backup.id, out)
        }
    }

    private static func reportDeploy(_ deploy: DeployOutcome, backupID: String, _ out: Output) -> Int32 {
        guard deploy.finished else {
            out.error("等了很久还没看到部署完成。可以过一会儿用 rimectl status 再看；有问题可以 rimectl restore \(backupID)")
            return 1
        }
        guard deploy.errors.isEmpty else {
            out.error("部署完成，但有错误：")
            for error in deploy.errors { out.error("  \(error)") }
            out.error("想回到之前的样子：rimectl restore \(backupID)")
            return 1
        }
        out.line("部署完成")
        return 0
    }

    private static func status(paths: AppPaths, locations: RimeLocations, _ context: Context) throws -> Int32 {
        let out = context.output
        let s = try deployer(paths: paths, locations: locations, context).status()
        let squirrelText = s.squirrelInstalled ? (s.squirrelRunning ? "已安装，正在运行" : "已安装，没在运行") : "没安装"
        out.line("鼠须管：\(squirrelText)")
        out.line("Rime 目录：\(s.rimeDirectory.path)")
        let applied = s.appliedAt.map { "，上次应用：\($0.formatted(date: .numeric, time: .standard))" } ?? "，还没应用过"
        out.line("应用管理的文件：\(s.managedFiles) 个\(applied)")
        if s.externalChanges.isEmpty {
            out.line("外部改动：没有")
        } else {
            out.line("外部改动：")
            for change in s.externalChanges { out.line("  \(change)") }
        }
        out.line("备份：\(s.backups.count) 份" + (s.backups.first.map { "，最近一份 \($0.id)（\($0.reason)）" } ?? ""))
        return 0
    }

    private static func restore(_ args: [String], listOnly: Bool, paths: AppPaths, locations: RimeLocations,
                                _ context: Context) async throws -> Int32 {
        let out = context.output
        if listOnly {
            for b in BackupStore(paths: paths).list() {
                out.line("\(b.id)  \(b.reason)\(b.permanent ? "（永久保留）" : "")  \(b.files.count) 个文件")
            }
            return 0
        }
        guard args.count == 1 else { out.error(usage); return 2 }
        let report = try await deployer(paths: paths, locations: locations, context).restore(args[0])
        out.line("已还原到 \(report.restored.id)（\(report.restored.reason)）")
        out.line("还原前的状态也备份了：\(report.safetyBackup.id)")
        for warning in report.warnings { out.line("注意：\(warning)") }
        return reportDeploy(report.deploy, backupID: report.safetyBackup.id, out)
    }
```

`settingsCommand` 的 `switch args.first` 里加一个分支（放在 `case "show":` 前面）：

```swift
        case "set":
            guard args.count == 3 else { out.error(usage); return 2 }
            guard var settings = try store.load() else {
                out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
                return 1
            }
            guard applySetting(args[1], args[2], to: &settings) else { out.error(usage); return 2 }
            try settings.validate(try context.catalog())
            try store.save(settings)
            out.line("已更新 \(args[1])")
            return 0
```

并加这个函数：

```swift
    /// 改一项设置；键或值的格式不对返回 false
    private static func applySetting(_ key: String, _ value: String, to s: inout Settings) -> Bool {
        let clear = value == "-"
        func int() -> Int?? { clear ? .some(nil) : Int(value).map { .some($0) } }
        switch key {
        case "schemas":
            s.schemas = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        case "font-point":
            guard let v = int() else { return false }
            s.appearance.fontPoint = v
        case "label-font-point":
            guard let v = int() else { return false }
            s.appearance.labelFontPoint = v
        case "comment-font-point":
            guard let v = int() else { return false }
            s.appearance.commentFontPoint = v
        case "page-size":
            guard let v = int() else { return false }
            s.appearance.pageSize = v
        case "layout":
            if clear { s.appearance.candidateListLayout = nil } else {
                guard let v = CandidateListLayout(rawValue: value) else { return false }
                s.appearance.candidateListLayout = v
            }
        case "orientation":
            if clear { s.appearance.textOrientation = nil } else {
                guard let v = TextOrientation(rawValue: value) else { return false }
                s.appearance.textOrientation = v
            }
        case "color-scheme":
            s.appearance.colorScheme = clear ? nil : value
        case "color-scheme-dark":
            s.appearance.colorSchemeDark = clear ? nil : value
        case "option":
            let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
            let head = parts.first?.split(separator: ".", maxSplits: 1).map(String.init) ?? []
            guard parts.count == 2, head.count == 2 else { return false }
            s.options[head[0], default: [:]][head[1]] = parts[1]
        default:
            return false
        }
        return true
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test|Expectation failed" | head -8`
Expected: 全部通过（新增 5 个；原来的 rimectl 测试不受影响）。

- [ ] **Step 5: 提交**

```bash
git add Sources/rimectl Tests/RimeKitTests/RimectlApplyTests.swift
git commit -m "feat: rimectl apply / status / restore / settings set

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 测试机里跑真实流程

**Files:**
- Modify: `docs/phase0-log.md` 不动；新建 `docs/phase3-vm-log.md`（实测记录）

**Interfaces:**
- Consumes: `rimectl`（任务 8，宿主机编译，测试机里通过共享文件夹运行）。

测试机现状（阶段 0 留下的）：`squirrel-dev` 已装鼠须管 1.1.2、已添加并选中输入法；`~/Library/Rime` 里有手动放进去的雾凇完整方案、手写的 `default.custom.yaml` 和 `squirrel.custom.yaml`（都不是应用写的）。下面的命令都在宿主机仓库根目录运行。

先定义一个在桌面会话里跑 rimectl 的写法（每条命令都这样包一层；`/tmp/rk` 是测试机里的应用数据目录）：

```bash
vmrun() { ./tools/vm/vm.sh ssh squirrel-dev "sudo launchctl asuser \$(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' $* --data-dir /tmp/rk"; }
```

- [ ] **Step 1: 编译，确认测试机能连上**

```bash
swift build 2>&1 | tail -1
./tools/vm/vm.sh list | grep squirrel-dev
./tools/vm/vm.sh ssh squirrel-dev 'pgrep -lx Squirrel; ls ~/Library/Rime | head'
```

Expected：`squirrel-dev` 是 running；鼠须管在运行。没开就照阶段 1 计划任务 9 的办法启动（需要桌面时请用户登录）。

- [ ] **Step 2: 场景 A——接手已有的手动配置**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rk'
vmrun settings init rime-ice
vmrun apply; echo "exit=$?"
vmrun apply --overwrite; echo "exit=$?"
vmrun status
```

Expected：第一次 `apply` 列出 `default.custom.yaml`、`rime_ice.schema.yaml` 等「不是应用写的，这次会被覆盖」，`exit=1`，Rime 目录没变；第二次输出「已备份：…（第一次应用前）」「已通知鼠须管重新部署」「部署完成」，`exit=0`；`status` 显示外部改动：没有。再用打字检查工具在副本上确认：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rimecopy && rsync -a --exclude "*.userdb" ~/Library/Rime/ /tmp/rimecopy/ && "/Volumes/My Shared Files/vm/rime-type-probe" /tmp/rimecopy rime_ice nihao rq 2>/dev/null'
```

Expected：`nihao` → 你好；`rq` → 今天的日期。

- [ ] **Step 3: 场景 B——只改外观，判断部署完成，并请用户看效果**

```bash
vmrun settings set font-point 28
vmrun apply; echo "exit=$?"
./tools/vm/vm.sh ssh squirrel-dev 'sed -n "/^style:/,/^[a-z]/p" ~/Library/Rime/build/squirrel.yaml | grep -E "^  font_point"; grep -A30 "purity_of_form_custom:" ~/Library/Rime/build/squirrel.yaml | grep -m1 font_point'
```

Expected：输出「写入 1 个文件」（只有 `squirrel.custom.yaml`）和「部署完成」，`exit=0`；`build/squirrel.yaml` 里 `style` 和 `purity_of_form_custom` 的 `font_point` 都是 28。请用户在测试机「文本编辑」里打几个字，确认候选字明显变大。

- [ ] **Step 4: 场景 C——外部改动**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'echo "# 手改" >> ~/Library/Rime/default.custom.yaml'
vmrun apply; echo "exit=$?"
vmrun apply --overwrite; echo "exit=$?"
```

Expected：第一次列出「default.custom.yaml：在应用外被改过」，`exit=1`；第二次成功。

- [ ] **Step 5: 场景 D——编译失败什么都不写**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'printf "patch:\n  \"translator/dictionary\": [1, 2\n" > ~/Library/Rime/rime_ice.custom.yaml; ls -l ~/Library/Rime/squirrel.custom.yaml'
vmrun settings set font-point 22
vmrun apply; echo "exit=$?"
./tools/vm/vm.sh ssh squirrel-dev 'ls -l ~/Library/Rime/squirrel.custom.yaml; rm ~/Library/Rime/rime_ice.custom.yaml'
```

Expected：`apply` 输出「新配置编译不过，没有写入：rime_ice.custom.yaml 的格式不对（不是合法的 YAML）」，`exit=1`；`squirrel.custom.yaml` 的修改时间没变。

- [ ] **Step 6: 场景 E——鼠须管没运行**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'killall Squirrel; sleep 1; pgrep -x Squirrel || echo 已退出'
vmrun apply; echo "exit=$?"
./tools/vm/vm.sh ssh squirrel-dev 'pgrep -lx Squirrel'
```

Expected：输出「已启动鼠须管」和「部署完成」，`exit=0`；鼠须管在运行。

- [ ] **Step 7: 场景 F——还原**

```bash
vmrun restore --list
```

记下标着「第一次应用前（永久保留）」的那份 id，然后：

```bash
vmrun restore <那份 id>; echo "exit=$?"
./tools/vm/vm.sh ssh squirrel-dev 'head -3 ~/Library/Rime/default.custom.yaml; ls ~/Library/Rime | head -5'
vmrun status
```

Expected：「已还原到 …（第一次应用前）」「部署完成」；`default.custom.yaml` 变回阶段 0 手写的（没有「由 squirrel-macos 生成」那行）；`status` 显示应用管理的文件 0 个。最后再 `vmrun apply --overwrite` 回到应用管理的状态，`exit=0`。

- [ ] **Step 8: 写实测记录 `docs/phase3-vm-log.md`**

按场景 A–F 各写一小节：命令、关键输出、是否符合预期；不符合的写清楚现象和处理（修代码就回到对应任务，用 superpowers:systematic-debugging，写 Ruling）。

- [ ] **Step 9: 提交**

```bash
git add docs/phase3-vm-log.md
git commit -m "docs: 阶段 3 测试机实测记录

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 更新文档

**Files:**
- Modify: `docs/verified-facts.md`、`docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`、`docs/superpowers/plans/2026-10-15-roadmap.md`、`CLAUDE.md`、`README.md`

- [ ] **Step 1: `verified-facts.md` 第 1 节「单独编译：rime_deployer」后面加**

```markdown
| 事实 | 验证 |
|---|---|
| `rime_deployer --build`：正常时退出码 0；方案或词库出错（找不到词库、方案 YAML 写坏）时退出码 1，输出 `E…` 开头的错误行 | 实测（宿主机临时目录，2026-10-15） |
| **`*.custom.yaml` 补丁写坏时退出码仍是 0**，补丁被悄悄忽略，只有一行 `E… Error parsing YAML "…"`。所以判断编译成功要同时看退出码和有没有 `E` 行 | 实测（同上） |
```

第 3 节表格末尾加：

```markdown
| 每次 `Squirrel --reload`（配置没变也一样）都会更新 `user.yaml` 的 `var/last_build_time`，可以当「部署跑完了」的信号；只改 `squirrel.custom.yaml` 时 `build/` 里方案文件的修改时间不变 | 实测（squirrel-dev，2026-10-15） |
| 鼠须管部署时会编译 `build/squirrel.yaml`（`rime_deployer` 不会），外观补丁的效果可以在这里查 | 实测（squirrel-dev） |
| 日志按鼠须管进程分文件：`rime.squirrel.<主机>.<用户>.log.<INFO\|WARNING\|ERROR>.<日期>-<时间>.<进程号>`，有出错才会有 ERROR 文件 | 实测（squirrel-dev） |
```

- [ ] **Step 2: 设计文档**

- 6.1 第 3 步改成：「用 `rime_deployer --build` 编译暂存区：退出码 0 并且没有 `E` 开头的日志行才算成功（补丁写坏时退出码也是 0）。失败就停，真实配置没动。」
- 6.1 第 4 步改成：「对照 ledger：应用管理的文件在应用外被改过、删了，或者这次要覆盖应用不管的文件，都列出来问用户（覆盖前先备份；被改过的个人词库可以采用外部的修改）。」
- 6.1 第 8 步改成：「检查结果：`user.yaml` 的 `var/last_build_time` 变了就算部署完（最多等 120 秒），再看这次新增的 ERROR 日志。不看 `build/` 文件的修改时间（只改外观时方案不重编译）。」
- 第 7 节「备份保留」后面加一句：「备份只包含配置文件，不含 `build/`、`sync/`、`installation.yaml`、`user.yaml`、`*.userdb` 这些 Rime 自己的运行文件。还原前会先给当前状态做一份「还原前」备份，还原也能撤销。」

- [ ] **Step 3: 路线图、CLAUDE.md、README**

- 路线图阶段 3 那一行「成果」末尾加「（已完成，2026-10-15）」。
- `CLAUDE.md` 开头阶段说明改成「阶段 0–3 已完成（…；写入真实配置、部署、备份还原），下一步写阶段 4 的计划」；「测试虚拟机」一节加一行：「在测试机里跑 `rimectl apply/restore` 要用桌面会话：`sudo launchctl asuser $(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' … --data-dir /tmp/rk`。」
- `README.md` 阶段说明改成「阶段 0–3 已完成（方案清单、下载缓存、生成配置、写入和部署）。下一步是阶段 4（安装鼠须管、环境检查）」；「开发」一节加：「- 宿主机上只用 `--rime-dir` 指向临时目录试 `rimectl apply`；写真实配置只在测试机里做」。

- [ ] **Step 4: 跑全部测试，提交，推送**

Run: `swift test 2>&1 | grep -E "error:|Test run" | tail -2`
Expected: 全部通过。

```bash
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 3 的事实和设计细节（编译判断、部署信号、备份范围）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```

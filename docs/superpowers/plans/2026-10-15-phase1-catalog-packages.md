# 阶段 1：工程骨架 + 方案清单 + 下载缓存 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建好 Swift Package（`RimeKit` 库 + `rimectl` 命令行 + 测试），做出内置方案清单 `catalog.json`（3 个包）和下载缓存：`rimectl fetch` 能从 GitHub 拿到最新版、解压、挑出要装的文件、检查结构、按版本缓存。

**Architecture:** 所有逻辑在 `RimeKit`。网络通过 `HTTPClient` 协议注入，单元测试用假的客户端和自己造的 zip，只在宿主机临时目录里跑。版本解析（`SourceResolver`）和下载缓存（`PackageStore`）分开：先问 GitHub「最新版本是什么、从哪下」，本地已有这个版本就直接用，没有才下载。缓存先在暂存区做好，最后一步整体移进 `packages/`，所以中途失败不会留下看起来完整的半成品。`rimectl` 只是一层很薄的命令行入口。

**Tech Stack:** Swift 6.4（swift-tools-version 6.4）、Swift Testing、Foundation（`URLSession`、`Process`、`FileManager`）、CryptoKit、Darwin `fnmatch`、系统自带 `/usr/bin/ditto`。本阶段**不引入任何第三方依赖**（Yams 等到阶段 2 读写 YAML 时再加）。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 3、4、5、7、8 节）；上游目录结构 [docs/upstream-layouts.md](../../upstream-layouts.md)；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## Global Constraints

- 最低 macOS 27：`platforms: [.macOS("27.0")]`；`// swift-tools-version: 6.4`。
- 运行时不依赖 python3、git、Homebrew；解压只用 `/usr/bin/ditto -x -k`。
- 本阶段不加第三方依赖。
- 应用数据目录默认 `~/Library/Application Support/squirrel-macos/`，下面有 `packages/`、`staging/`（设计第 5 节）。**测试一律用临时目录**，不写真实的数据目录；宿主机上手动试 `rimectl` 时也加 `--data-dir`。
- 不碰宿主机的 `~/Library/Rime`、`/Library/Input Methods`、输入法状态。本阶段的代码根本不读写 `~/Library/Rime`。
- 代码注释、错误信息、命令行输出用简单直白的中文；标识符用英文。
- 清单格式带 `formatVersion`，当前是 1；以后在线清单也用同一格式（设计第 4 节）。第一版发布前改格式不用升版本号。
- 版本：Release 附件用 `updated_at`；按分支下载的包用提交号 `sha`，并且按这个 sha 下载，保证「版本号」和「下载到的内容」一致。
- 路径用查找定位，不写死顶层目录名（极点五笔 zip 带 `rime-wubi86-jidian-<sha>/`，雾凇 `full.zip` 没有顶层目录，`cn_dicts.zip` 顶层是 `cn_dicts/`）。
- 提交：用户已同意执行计划时按任务提交、阶段结束推送到 `main`。提交信息结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 每个任务的测试命令都在仓库根目录运行。

## Review Focus

1. GitHub 接口限流（403）或返回非 200 → 给出看得懂的错误，不能崩溃，也不能报「JSON 解析失败」这种误导的话（任务 6 有测试）。
2. 下载或解压到一半失败 → `packages/` 里不能留下以后会被当成「已缓存」的目录（任务 7 有测试）。
3. zip 里有符号链接（可能指到包外面）→ 不复制（任务 7 有测试）。
4. 版本号里有 `:` 这类字符（`updated_at` 是 `2026-10-05T13:38:43Z`）→ 目录名要安全（任务 7 有测试）。
5. 同一个包本地已有旧版本、上游出了新版本 → 新旧都保留，「最近一次」取最新取到的那个；断网时提示可以用旧版本（任务 7、8 有测试）。

---

## 文件结构

```
Package.swift
Sources/
  RimeKit/
    AppPaths.swift                 # 应用数据目录
    Support/Shell.swift            # 运行外部程序
    Support/Hashing.swift          # 文件 SHA-256
    Support/JSONCoding.swift       # 统一的 JSON 编解码设置
    Catalog/FileGlob.swift         # 安装文件的匹配规则
    Catalog/Catalog.swift          # 清单的数据结构、读取、校验、依赖顺序
    Catalog/CatalogError.swift     # 清单错误
    Resources/catalog.json         # 内置清单（3 个包）
    Net/HTTPClient.swift           # 网络协议、URLSession 实现、重试
    Packages/SourceResolver.swift  # 问 GitHub：最新版本和下载地址
    Packages/Unzipper.swift        # 用 ditto 解压
    Packages/PackageStore.swift    # 下载、挑文件、检查、缓存
  rimectl/
    Rimectl.swift                  # 命令行入口（@main）和命令实现
    Output.swift                   # 输出（命令行打印 / 测试收集）
Tests/
  RimeKitTests/
    Support/TempDir.swift
    Support/ZipFixture.swift
    Support/FakeHTTPClient.swift
    Support/Fixtures.swift
    AppPathsTests.swift
    FileGlobTests.swift
    CatalogTests.swift
    BuiltInCatalogTests.swift
    HTTPRetryTests.swift
    SourceResolverTests.swift
    PackageStoreTests.swift
    RimectlTests.swift
    OnlineTests.swift              # 联网测试，默认不跑
```

---

### Task 1: Package 骨架和 `AppPaths`

**Files:**
- Create: `Package.swift`
- Create: `Sources/RimeKit/AppPaths.swift`
- Create: `Sources/rimectl/Rimectl.swift`（占位，任务 8 实现）
- Create: `Tests/RimeKitTests/Support/TempDir.swift`
- Test: `Tests/RimeKitTests/AppPathsTests.swift`

**Interfaces:**
- Produces: `public struct AppPaths: Sendable, Equatable { public let root: URL; public init(root: URL); public static var default: AppPaths; public var packages: URL; public var staging: URL }`；测试辅助 `TempDir`（`let url: URL`，`func remove()`）。

- [ ] **Step 1: 写 `Package.swift`**

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SquirrelMacOS",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "RimeKit", targets: ["RimeKit"]),
        .executable(name: "rimectl", targets: ["rimectl"]),
    ],
    targets: [
        .target(
            name: "RimeKit",
            resources: [.copy("Resources/catalog.json")]
        ),
        .executableTarget(name: "rimectl", dependencies: ["RimeKit"]),
        .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "rimectl"]),
    ]
)
```

- [ ] **Step 2: 写占位文件，让工程能编译**

`Sources/RimeKit/Resources/catalog.json`（任务 4 会换成真内容）：

```json
{ "formatVersion": 1, "packages": [] }
```

`Sources/rimectl/Rimectl.swift`：

```swift
import Foundation

@main
struct Rimectl {
    static func main() async {
        print("rimectl：还没实现")
    }
}
```

`Tests/RimeKitTests/Support/TempDir.swift`：

```swift
import Foundation

/// 测试用的临时目录，每个测试一个，用完调用 remove()
struct TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "rimekit-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 3: 写失败的测试 `Tests/RimeKitTests/AppPathsTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct AppPathsTests {
    @Test func 默认目录在应用支持目录下() {
        let path = AppPaths.default.root.path
        #expect(path.hasSuffix("/Library/Application Support/squirrel-macos"))
    }

    @Test func 子目录都在根目录下() {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/x", isDirectory: true))
        #expect(paths.packages.path == "/tmp/x/packages")
        #expect(paths.staging.path == "/tmp/x/staging")
    }
}
```

- [ ] **Step 4: 运行，确认失败**

Run: `swift test --filter AppPathsTests 2>&1 | tail -15`
Expected: 编译失败，提示 `cannot find 'AppPaths' in scope`。

- [ ] **Step 5: 写 `Sources/RimeKit/AppPaths.swift`**

```swift
import Foundation

/// 应用自己的数据目录。默认是 ~/Library/Application Support/squirrel-macos，
/// 测试和 rimectl --data-dir 可以换成别的目录。
public struct AppPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: base.appending(path: "squirrel-macos", directoryHint: .isDirectory))
    }

    /// 上游包缓存，按「包名@版本」存放
    public var packages: URL { root.appending(path: "packages", directoryHint: .isDirectory) }

    /// 生成、下载用的暂存区
    public var staging: URL { root.appending(path: "staging", directoryHint: .isDirectory) }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test --filter AppPathsTests 2>&1 | tail -5`
Expected: `Test run with 2 tests … passed`。

- [ ] **Step 7: 提交**

```bash
git add Package.swift Sources Tests
git commit -m "feat: Swift Package 骨架和 AppPaths

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 安装文件的匹配规则 `FileGlob`

**Files:**
- Create: `Sources/RimeKit/Catalog/FileGlob.swift`
- Test: `Tests/RimeKitTests/FileGlobTests.swift`

**Interfaces:**
- Produces: `public struct FileGlob: Sendable, Equatable, Codable { public let pattern: String; public init(_ pattern: String); public func matches(_ relativePath: String) -> Bool }`。JSON 里直接写成字符串。规则：`*`、`?`、`[...]` 不跨目录；以 `/**` 结尾表示这个目录下任意深度的文件。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct FileGlobTests {
    @Test func 星号只匹配同一层() {
        let g = FileGlob("*.schema.yaml")
        #expect(g.matches("rime_ice.schema.yaml"))
        #expect(!g.matches("sub/rime_ice.schema.yaml"))
        #expect(!g.matches("rime_ice.dict.yaml"))
    }

    @Test func 带目录的星号() {
        let g = FileGlob("cn_dicts/*.dict.yaml")
        #expect(g.matches("cn_dicts/8105.dict.yaml"))
        #expect(!g.matches("cn_dicts/deep/8105.dict.yaml"))
        #expect(!g.matches("8105.dict.yaml"))
    }

    @Test func 两个星号匹配任意深度() {
        let g = FileGlob("lua/**")
        #expect(g.matches("lua/date_translator.lua"))
        #expect(g.matches("lua/cold_word_drop/filter.lua"))
        #expect(!g.matches("lua"))
        #expect(!g.matches("lua2/x.lua"))
        #expect(!g.matches("other/lua/x.lua"))
    }

    @Test func 精确文件名() {
        let g = FileGlob("default.yaml")
        #expect(g.matches("default.yaml"))
        #expect(!g.matches("x/default.yaml"))
    }

    @Test func JSON里是字符串() throws {
        let data = Data(#"["*.yaml","lua/**"]"#.utf8)
        let globs = try JSONDecoder().decode([FileGlob].self, from: data)
        #expect(globs == [FileGlob("*.yaml"), FileGlob("lua/**")])
        let back = try JSONEncoder().encode(globs)
        #expect(String(decoding: back, as: UTF8.self) == #"["*.yaml","lua\/**"]"#)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter FileGlobTests 2>&1 | tail -15`
Expected: 编译失败，`cannot find 'FileGlob' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Catalog/FileGlob.swift`**

```swift
import Darwin
import Foundation

/// 安装文件的匹配规则，路径都是相对包根目录的。
/// - `*`、`?`、`[...]` 不跨目录：`*.schema.yaml` 只匹配根目录下的文件
/// - 以 `/**` 结尾：这个目录下任意深度的所有文件，例如 `lua/**`
public struct FileGlob: Sendable, Equatable, Codable {
    public let pattern: String

    public init(_ pattern: String) {
        self.pattern = pattern
    }

    public func matches(_ relativePath: String) -> Bool {
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(2))   // 留下结尾的 "/"
            return relativePath.hasPrefix(prefix) && relativePath.count > prefix.count
        }
        return fnmatch(pattern, relativePath, FNM_PATHNAME) == 0
    }

    public init(from decoder: any Decoder) throws {
        pattern = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(pattern)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter FileGlobTests 2>&1 | tail -5`
Expected: 5 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Catalog/FileGlob.swift Tests/RimeKitTests/FileGlobTests.swift
git commit -m "feat: 安装文件匹配规则 FileGlob

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 清单的数据结构、读取、校验、依赖顺序

**Files:**
- Create: `Sources/RimeKit/Catalog/Catalog.swift`
- Create: `Sources/RimeKit/Catalog/CatalogError.swift`
- Create: `Sources/RimeKit/Support/JSONCoding.swift`
- Create: `Tests/RimeKitTests/Support/Fixtures.swift`（本任务只放清单部分，任务 6、7 往里加）
- Test: `Tests/RimeKitTests/CatalogTests.swift`

**Interfaces:**
- Consumes: `FileGlob`（任务 2）。
- Produces:
  - `public struct Catalog: Sendable, Equatable, Codable { public static let supportedFormatVersion: Int; public let formatVersion: Int; public let packages: [PackageSpec]; public func package(_ id: String) -> PackageSpec?; public static func decode(_ data: Data) throws -> Catalog; public static func builtIn() throws -> Catalog; public func validate() throws; public func installOrder(for ids: [String]) throws -> [PackageSpec] }`
  - `public struct PackageSpec: Sendable, Equatable, Codable { id, name, summary, license: String; homepage: URL; source: PackageSource; anchor: String; include: [FileGlob]; exclude: [FileGlob]; requiredFiles: [String]; schemas: [SchemaSpec]; dependencies: [String] }`
  - `public struct SchemaSpec: Sendable, Equatable, Codable { id: String; name: String; category: SchemaCategory }`，`public enum SchemaCategory: String { pinyin, shuangpin, wubi, other }`
  - `public enum PackageSource: Sendable, Equatable, Codable { case githubReleaseAsset(repo: String, tag: String, asset: String); case githubBranch(repo: String, branch: String) }`，JSON 形如 `{"type":"githubReleaseAsset","repo":…,"tag":…,"asset":…}` / `{"type":"githubBranch","repo":…,"branch":…}`
  - `public enum CatalogError: Error, Equatable, CustomStringConvertible { unsupportedFormat(Int), duplicatePackageID(String), duplicateSchemaID(String), unknownDependency(package: String, dependency: String), dependencyCycle([String]), requiredFileNotIncluded(package: String, file: String), unknownPackage(String), builtInMissing }`
  - `enum JSONCoding { static var encoder: JSONEncoder; static var decoder: JSONDecoder }`（日期用 ISO 8601，输出排序、缩进）
  - 测试辅助 `Fixtures.catalogJSON`、`Fixtures.catalog()`、`Fixtures.catalogData(replacing:with:)`

- [ ] **Step 1: 写测试辅助 `Tests/RimeKitTests/Support/Fixtures.swift`**

```swift
import Foundation
@testable import RimeKit

/// 测试用的清单：base（Release 附件）和 app（按分支下载，依赖 base）
enum Fixtures {
    static let catalogJSON = """
    {"formatVersion":1,"packages":[
     {"id":"base","name":"基础","summary":"s","license":"MIT","homepage":"https://example.com/base",
      "source":{"type":"githubReleaseAsset","repo":"o/base","tag":"t","asset":"base.zip"},
      "anchor":"base.schema.yaml","include":["*.schema.yaml","dicts/**"],"exclude":["dicts/skip.txt"],
      "requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"],
      "schemas":[{"id":"base","name":"基础","category":"pinyin"}],"dependencies":[]},
     {"id":"app","name":"应用","summary":"s","license":"MIT","homepage":"https://example.com/app",
      "source":{"type":"githubBranch","repo":"o/app","branch":"main"},
      "anchor":"app.schema.yaml","include":["*.schema.yaml"],"exclude":[],
      "requiredFiles":["app.schema.yaml"],
      "schemas":[{"id":"app","name":"应用","category":"wubi"}],"dependencies":["base"]}
    ]}
    """

    static func catalog() throws -> Catalog {
        try Catalog.decode(Data(catalogJSON.utf8))
    }

    /// 把清单里的一段文字换掉（这段文字必须正好出现一次），用来造出各种有问题的清单
    static func catalogData(replacing old: String, with new: String) -> Data {
        precondition(catalogJSON.components(separatedBy: old).count == 2, "要替换的文字必须正好出现一次：\(old)")
        return Data(catalogJSON.replacingOccurrences(of: old, with: new).utf8)
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/CatalogTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogTests {
    @Test func 能读出清单的各个字段() throws {
        let catalog = try Fixtures.catalog()
        #expect(catalog.formatVersion == 1)
        #expect(catalog.packages.map(\.id) == ["base", "app"])
        let base = try #require(catalog.package("base"))
        #expect(base.source == .githubReleaseAsset(repo: "o/base", tag: "t", asset: "base.zip"))
        #expect(base.include == [FileGlob("*.schema.yaml"), FileGlob("dicts/**")])
        #expect(base.schemas == [SchemaSpec(id: "base", name: "基础", category: .pinyin)])
        let app = try #require(catalog.package("app"))
        #expect(app.source == .githubBranch(repo: "o/app", branch: "main"))
        #expect(app.dependencies == ["base"])
        #expect(catalog.package("nope") == nil)
    }

    @Test func 编码再解码不变() throws {
        let catalog = try Fixtures.catalog()
        let data = try JSONCoding.encoder.encode(catalog)
        #expect(try Catalog.decode(data) == catalog)
    }

    @Test func 不认识的格式版本() {
        #expect(throws: CatalogError.unsupportedFormat(2)) {
            try Catalog.decode(Fixtures.catalogData(replacing: #""formatVersion":1"#, with: #""formatVersion":2"#))
        }
    }

    @Test func 包名重复() {
        #expect(throws: CatalogError.duplicatePackageID("base")) {
            try Catalog.decode(Fixtures.catalogData(
                replacing: #"{"id":"app","name":"应用","summary""#,
                with: #"{"id":"base","name":"应用","summary""#))
        }
    }

    @Test func 方案名重复() {
        #expect(throws: CatalogError.duplicateSchemaID("base")) {
            try Catalog.decode(Fixtures.catalogData(
                replacing: #"[{"id":"app","name":"应用","category":"wubi"}]"#,
                with: #"[{"id":"base","name":"应用","category":"wubi"}]"#))
        }
    }

    @Test func 依赖了不存在的包() {
        #expect(throws: CatalogError.unknownDependency(package: "app", dependency: "nope")) {
            try Catalog.decode(Fixtures.catalogData(replacing: #""dependencies":["base"]"#, with: #""dependencies":["nope"]"#))
        }
    }

    @Test func 循环依赖() {
        let error = #expect(throws: CatalogError.self) {
            try Catalog.decode(Fixtures.catalogData(replacing: #""dependencies":[]}"#, with: #""dependencies":["app"]}"#))
        }
        guard case .dependencyCycle(let path) = error else {
            Issue.record("应该是循环依赖，实际是 \(String(describing: error))")
            return
        }
        #expect(path.first == path.last)
        #expect(Set(path) == ["base", "app"])
    }

    @Test func 必需文件不在安装规则里() {
        #expect(throws: CatalogError.requiredFileNotIncluded(package: "app", file: "lib/x.lua")) {
            try Catalog.decode(Fixtures.catalogData(
                replacing: #""requiredFiles":["app.schema.yaml"]"#,
                with: #""requiredFiles":["app.schema.yaml","lib/x.lua"]"#))
        }
    }

    @Test func 安装顺序依赖在前而且不重复() throws {
        let catalog = try Fixtures.catalog()
        #expect(try catalog.installOrder(for: ["app"]).map(\.id) == ["base", "app"])
        #expect(try catalog.installOrder(for: ["app", "base"]).map(\.id) == ["base", "app"])
        #expect(try catalog.installOrder(for: ["base"]).map(\.id) == ["base"])
    }

    @Test func 安装顺序遇到不存在的包() throws {
        let catalog = try Fixtures.catalog()
        #expect(throws: CatalogError.unknownPackage("nope")) {
            try catalog.installOrder(for: ["nope"])
        }
    }

    @Test func 错误信息是中文() {
        #expect(CatalogError.unknownPackage("x").description == "清单里没有这个包：x")
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter CatalogTests 2>&1 | tail -15`
Expected: 编译失败，`cannot find 'Catalog' in scope`。

- [ ] **Step 4: 写 `Sources/RimeKit/Support/JSONCoding.swift`**

```swift
import Foundation

/// 全项目统一的 JSON 设置：日期用 ISO 8601，输出排序、缩进，方便看和比对
enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Catalog/CatalogError.swift`**

```swift
import Foundation

public enum CatalogError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormat(Int)
    case duplicatePackageID(String)
    case duplicateSchemaID(String)
    case unknownDependency(package: String, dependency: String)
    case dependencyCycle([String])
    case requiredFileNotIncluded(package: String, file: String)
    case unknownPackage(String)
    case builtInMissing

    public var description: String {
        switch self {
        case .unsupportedFormat(let v):
            return "方案清单的格式版本是 \(v)，这个版本的应用只认识 \(Catalog.supportedFormatVersion)，请更新应用"
        case .duplicatePackageID(let id):
            return "方案清单里有两个包都叫 \(id)"
        case .duplicateSchemaID(let id):
            return "方案清单里有两个方案都叫 \(id)"
        case .unknownDependency(let package, let dependency):
            return "包 \(package) 依赖的 \(dependency) 不在方案清单里"
        case .dependencyCycle(let path):
            return "方案清单里有循环依赖：\(path.joined(separator: " → "))"
        case .requiredFileNotIncluded(let package, let file):
            return "包 \(package) 的必需文件 \(file) 不在安装规则里，永远装不上"
        case .unknownPackage(let id):
            return "清单里没有这个包：\(id)"
        case .builtInMissing:
            return "应用里找不到内置的方案清单 catalog.json"
        }
    }
}
```

- [ ] **Step 6: 写 `Sources/RimeKit/Catalog/Catalog.swift`**

```swift
import Foundation

/// 方案清单：有哪些包、从哪下载、装哪些文件、依赖谁（设计第 4 节）
public struct Catalog: Sendable, Equatable, Codable {
    public static let supportedFormatVersion = 1

    public let formatVersion: Int
    public let packages: [PackageSpec]

    public func package(_ id: String) -> PackageSpec? {
        packages.first { $0.id == id }
    }

    /// 读取并校验。先只读格式版本号，版本不对就不往下解析。
    public static func decode(_ data: Data) throws -> Catalog {
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONCoding.decoder.decode(Header.self, from: data)
        guard header.formatVersion == supportedFormatVersion else {
            throw CatalogError.unsupportedFormat(header.formatVersion)
        }
        let catalog = try JSONCoding.decoder.decode(Catalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    /// 打包在应用里的清单
    public static func builtIn() throws -> Catalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
            throw CatalogError.builtInMissing
        }
        return try decode(Data(contentsOf: url))
    }

    public func validate() throws {
        var packageIDs = Set<String>()
        for p in packages where !packageIDs.insert(p.id).inserted {
            throw CatalogError.duplicatePackageID(p.id)
        }
        var schemaIDs = Set<String>()
        for s in packages.flatMap(\.schemas) where !schemaIDs.insert(s.id).inserted {
            throw CatalogError.duplicateSchemaID(s.id)
        }
        for p in packages {
            for d in p.dependencies where !packageIDs.contains(d) {
                throw CatalogError.unknownDependency(package: p.id, dependency: d)
            }
        }
        try checkCycles()
        for p in packages {
            for file in p.requiredFiles {
                let included = p.include.contains { $0.matches(file) } && !p.exclude.contains { $0.matches(file) }
                if !included { throw CatalogError.requiredFileNotIncluded(package: p.id, file: file) }
            }
        }
    }

    /// 要装这些包时的顺序：依赖在前，每个包只出现一次
    public func installOrder(for ids: [String]) throws -> [PackageSpec] {
        var result: [PackageSpec] = []
        var seen = Set<String>()
        func visit(_ id: String) throws {
            if seen.contains(id) { return }
            guard let p = package(id) else { throw CatalogError.unknownPackage(id) }
            seen.insert(id)
            for d in p.dependencies { try visit(d) }
            result.append(p)
        }
        for id in ids { try visit(id) }
        return result
    }

    private func checkCycles() throws {
        enum State { case visiting, done }
        var state: [String: State] = [:]
        var stack: [String] = []
        func visit(_ id: String) throws {
            if state[id] == .done { return }
            if state[id] == .visiting {
                let start = stack.firstIndex(of: id) ?? 0
                throw CatalogError.dependencyCycle(Array(stack[start...]) + [id])
            }
            state[id] = .visiting
            stack.append(id)
            for d in package(id)?.dependencies ?? [] { try visit(d) }
            stack.removeLast()
            state[id] = .done
        }
        for p in packages { try visit(p.id) }
    }
}

public struct PackageSpec: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let summary: String
    public let license: String
    public let homepage: URL
    public let source: PackageSource
    /// 用来找包根目录的文件（相对包根目录）。zip 里顶层目录名不固定，靠它定位。
    public let anchor: String
    public let include: [FileGlob]
    public let exclude: [FileGlob]
    /// 解压后必须存在的文件；缺了说明上游结构变了
    public let requiredFiles: [String]
    public let schemas: [SchemaSpec]
    public let dependencies: [String]
}

public struct SchemaSpec: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let category: SchemaCategory

    public init(id: String, name: String, category: SchemaCategory) {
        self.id = id
        self.name = name
        self.category = category
    }
}

public enum SchemaCategory: String, Sendable, Equatable, Codable {
    case pinyin, shuangpin, wubi, other
}

public enum PackageSource: Sendable, Equatable, Codable {
    /// GitHub Release 的附件，版本用附件的 updated_at
    case githubReleaseAsset(repo: String, tag: String, asset: String)
    /// GitHub 某个分支的最新提交，版本用提交号，并按提交号下载
    case githubBranch(repo: String, branch: String)

    private enum CodingKeys: String, CodingKey { case type, repo, tag, asset, branch }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "githubReleaseAsset":
            self = .githubReleaseAsset(
                repo: try c.decode(String.self, forKey: .repo),
                tag: try c.decode(String.self, forKey: .tag),
                asset: try c.decode(String.self, forKey: .asset))
        case "githubBranch":
            self = .githubBranch(
                repo: try c.decode(String.self, forKey: .repo),
                branch: try c.decode(String.self, forKey: .branch))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "不认识的下载来源类型：\(type)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .githubReleaseAsset(repo, tag, asset):
            try c.encode("githubReleaseAsset", forKey: .type)
            try c.encode(repo, forKey: .repo)
            try c.encode(tag, forKey: .tag)
            try c.encode(asset, forKey: .asset)
        case let .githubBranch(repo, branch):
            try c.encode("githubBranch", forKey: .type)
            try c.encode(repo, forKey: .repo)
            try c.encode(branch, forKey: .branch)
        }
    }
}
```

- [ ] **Step 7: 运行，确认通过**

Run: `swift test --filter CatalogTests 2>&1 | tail -5`
Expected: 11 个测试全部通过。

- [ ] **Step 8: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 方案清单的数据结构、校验和依赖顺序

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 内置清单 `catalog.json`（3 个包）

**Files:**
- Modify: `Sources/RimeKit/Resources/catalog.json`（替换占位内容）
- Test: `Tests/RimeKitTests/BuiltInCatalogTests.swift`

**Interfaces:**
- Consumes: `Catalog.builtIn()`（任务 3）。
- Produces: 内置包 `rime-ice`、`rime-ice-dicts`、`wubi86-jidian`。方案 id：`rime_ice`、`double_pinyin_flypy`、`wubi86_jidian`、`wubi86_jidian_pinyin`、`wubi86_jidian_trad`、`wubi86_jidian_trad_pinyin`、`pinyin_simp`、`numbers`。阶段 2 会给这个格式加「选项」等字段。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct BuiltInCatalogTests {
    @Test func 内置清单能读出来而且通过校验() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.packages.map(\.id) == ["rime-ice", "rime-ice-dicts", "wubi86-jidian"])
    }

    @Test func 第一版的方案都在() throws {
        let ids = Set(try Catalog.builtIn().packages.flatMap(\.schemas).map(\.id))
        #expect(ids == ["rime_ice", "double_pinyin_flypy",
                        "wubi86_jidian", "wubi86_jidian_pinyin", "wubi86_jidian_trad",
                        "wubi86_jidian_trad_pinyin", "pinyin_simp", "numbers"])
    }

    @Test func 下载来源和上游目录结构一致() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.package("rime-ice")?.source == .githubReleaseAsset(repo: "iDvel/rime-ice", tag: "nightly", asset: "full.zip"))
        #expect(catalog.package("rime-ice-dicts")?.source == .githubReleaseAsset(repo: "iDvel/rime-ice", tag: "nightly", asset: "cn_dicts.zip"))
        #expect(catalog.package("wubi86-jidian")?.source == .githubBranch(repo: "KyleBing/rime-wubi86-jidian", branch: "master"))
        #expect(catalog.package("rime-ice-dicts")?.anchor == "cn_dicts/8105.dict.yaml")
    }

    @Test func GPL的包都标了许可证() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.package("rime-ice")?.license == "GPL-3.0")
        #expect(catalog.package("rime-ice-dicts")?.license == "GPL-3.0")
        #expect(catalog.package("wubi86-jidian")?.license == "Apache-2.0")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter BuiltInCatalogTests 2>&1 | tail -15`
Expected: 失败，`packages` 是空的（占位清单）。

- [ ] **Step 3: 写 `Sources/RimeKit/Resources/catalog.json`**

各包装哪些文件，依据 [upstream-layouts.md](../../upstream-layouts.md)。

```json
{
  "formatVersion": 1,
  "packages": [
    {
      "id": "rime-ice",
      "name": "雾凇拼音",
      "summary": "雾凇拼音完整方案：全拼、小鹤双拼等，带大词库、英文词库、Lua 脚本和 emoji",
      "license": "GPL-3.0",
      "homepage": "https://github.com/iDvel/rime-ice",
      "source": { "type": "githubReleaseAsset", "repo": "iDvel/rime-ice", "tag": "nightly", "asset": "full.zip" },
      "anchor": "rime_ice.schema.yaml",
      "include": [
        "*.schema.yaml", "*.dict.yaml", "cn_dicts/*.dict.yaml", "en_dicts/*", "lua/**", "opencc/*",
        "default.yaml", "squirrel.yaml", "symbols_v.yaml", "symbols_caps_v.yaml", "custom_phrase.txt", "LICENSE"
      ],
      "exclude": [],
      "requiredFiles": [
        "rime_ice.schema.yaml", "double_pinyin_flypy.schema.yaml", "rime_ice.dict.yaml",
        "cn_dicts/8105.dict.yaml", "cn_dicts/base.dict.yaml", "cn_dicts/ext.dict.yaml",
        "lua/date_translator.lua", "opencc/emoji.json", "default.yaml"
      ],
      "schemas": [
        { "id": "rime_ice", "name": "雾凇拼音（全拼）", "category": "pinyin" },
        { "id": "double_pinyin_flypy", "name": "小鹤双拼", "category": "shuangpin" }
      ],
      "dependencies": []
    },
    {
      "id": "rime-ice-dicts",
      "name": "雾凇词库",
      "summary": "雾凇拼音的中文词库（字表、基础词库、扩展词库），给别的方案当拼音词库用",
      "license": "GPL-3.0",
      "homepage": "https://github.com/iDvel/rime-ice",
      "source": { "type": "githubReleaseAsset", "repo": "iDvel/rime-ice", "tag": "nightly", "asset": "cn_dicts.zip" },
      "anchor": "cn_dicts/8105.dict.yaml",
      "include": ["cn_dicts/8105.dict.yaml", "cn_dicts/base.dict.yaml", "cn_dicts/ext.dict.yaml"],
      "exclude": [],
      "requiredFiles": ["cn_dicts/8105.dict.yaml", "cn_dicts/base.dict.yaml", "cn_dicts/ext.dict.yaml"],
      "schemas": [],
      "dependencies": []
    },
    {
      "id": "wubi86-jidian",
      "name": "极点五笔 86",
      "summary": "极点五笔 86 版：五笔、五笔拼音混输、简入繁出，带拼音和大写数字方案",
      "license": "Apache-2.0",
      "homepage": "https://github.com/KyleBing/rime-wubi86-jidian",
      "source": { "type": "githubBranch", "repo": "KyleBing/rime-wubi86-jidian", "branch": "master" },
      "anchor": "wubi86_jidian.schema.yaml",
      "include": ["*.schema.yaml", "*.dict.yaml", "default.custom.yaml", "squirrel.custom.yaml", "LICENSE"],
      "exclude": [],
      "requiredFiles": [
        "wubi86_jidian.schema.yaml", "wubi86_jidian_pinyin.schema.yaml", "wubi86_jidian_trad.schema.yaml",
        "wubi86_jidian_trad_pinyin.schema.yaml", "pinyin_simp.schema.yaml", "numbers.schema.yaml",
        "wubi86_jidian.dict.yaml", "pinyin_simp.dict.yaml"
      ],
      "schemas": [
        { "id": "wubi86_jidian_pinyin", "name": "五笔拼音混输", "category": "wubi" },
        { "id": "wubi86_jidian", "name": "五笔", "category": "wubi" },
        { "id": "wubi86_jidian_trad", "name": "五笔（简入繁出）", "category": "wubi" },
        { "id": "wubi86_jidian_trad_pinyin", "name": "五笔拼音混输（简入繁出）", "category": "wubi" },
        { "id": "pinyin_simp", "name": "拼音", "category": "pinyin" },
        { "id": "numbers", "name": "大写数字", "category": "other" }
      ],
      "dependencies": []
    }
  ]
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter BuiltInCatalogTests 2>&1 | tail -5`
Expected: 4 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Resources/catalog.json Tests/RimeKitTests/BuiltInCatalogTests.swift
git commit -m "feat: 内置方案清单（雾凇拼音、雾凇词库、极点五笔 86）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 网络协议、URLSession 实现和重试

**Files:**
- Create: `Sources/RimeKit/Net/HTTPClient.swift`
- Create: `Tests/RimeKitTests/Support/FakeHTTPClient.swift`
- Test: `Tests/RimeKitTests/HTTPRetryTests.swift`

**Interfaces:**
- Produces:
  - `public protocol HTTPClient: Sendable { func get(_ url: URL) async throws -> Data; func download(_ url: URL, to destination: URL) async throws }`
  - `public enum HTTPError: Error, Equatable, Sendable, CustomStringConvertible { case status(Int, URL); case transport(String); var isRetryable: Bool }`（断网、5xx、429 可以重试；403、404 不重试）
  - `public struct URLSessionHTTPClient: HTTPClient`（带 `User-Agent: squirrel-macos`；只对 `api.github.com` 加 `Accept: application/vnd.github+json`）
  - `public struct RetryPolicy: Sendable { attempts: Int; delay: Duration; static let standard /* 3 次，间隔 2 秒 */; static let immediate /* 3 次，不等 */ }`
  - `func withRetry<T: Sendable>(_ policy: RetryPolicy, _ operation: @Sendable () async throws -> T) async throws -> T`（RimeKit 内部）
  - 测试辅助 `FakeHTTPClient`：`stub(_ url: URL, _ results: Result<Data, HTTPError>...)` 按顺序返回，最后一个一直重复；没有设置的地址返回 404；`callCount(_ url: URL) -> Int`

- [ ] **Step 1: 写测试辅助 `Tests/RimeKitTests/Support/FakeHTTPClient.swift`**

```swift
import Foundation
@testable import RimeKit

/// 假的网络：每个地址按顺序返回事先设置好的结果，最后一个结果一直重复
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: [Result<Data, HTTPError>]] = [:]
    private var calls: [URL: Int] = [:]

    func stub(_ url: URL, _ results: Result<Data, HTTPError>...) {
        lock.withLock { responses[url] = results }
    }

    func callCount(_ url: URL) -> Int {
        lock.withLock { calls[url, default: 0] }
    }

    func get(_ url: URL) async throws -> Data {
        try next(url)
    }

    func download(_ url: URL, to destination: URL) async throws {
        let data = try next(url)
        try data.write(to: destination)
    }

    private func next(_ url: URL) throws -> Data {
        let result: Result<Data, HTTPError> = lock.withLock {
            let n = calls[url, default: 0]
            calls[url] = n + 1
            guard let list = responses[url], !list.isEmpty else { return .failure(.status(404, url)) }
            return list[min(n, list.count - 1)]
        }
        return try result.get()
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/HTTPRetryTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct HTTPRetryTests {
    let url = URL(string: "https://example.com/x")!

    @Test func 断网两次第三次成功() async throws {
        let http = FakeHTTPClient()
        http.stub(url, .failure(.transport("断网")), .failure(.transport("断网")), .success(Data("ok".utf8)))
        let data = try await withRetry(.immediate) { try await http.get(url) }
        #expect(String(decoding: data, as: UTF8.self) == "ok")
        #expect(http.callCount(url) == 3)
    }

    @Test func 重试次数用完就放弃() async {
        let http = FakeHTTPClient()
        http.stub(url, .failure(.status(503, url)))
        await #expect(throws: HTTPError.status(503, url)) {
            try await withRetry(.immediate) { try await http.get(url) }
        }
        #expect(http.callCount(url) == 3)
    }

    @Test func 限流和找不到不重试() async {
        let http = FakeHTTPClient()
        http.stub(url, .failure(.status(403, url)))
        await #expect(throws: HTTPError.status(403, url)) {
            try await withRetry(.immediate) { try await http.get(url) }
        }
        #expect(http.callCount(url) == 1)
    }

    @Test func 哪些错误可以重试() {
        #expect(HTTPError.transport("x").isRetryable)
        #expect(HTTPError.status(500, url).isRetryable)
        #expect(HTTPError.status(429, url).isRetryable)
        #expect(!HTTPError.status(403, url).isRetryable)
        #expect(!HTTPError.status(404, url).isRetryable)
    }

    @Test func 错误信息是中文() {
        #expect(HTTPError.status(403, url).description.contains("403"))
        #expect(HTTPError.status(403, url).description.contains("限制"))
        #expect(HTTPError.transport("超时").description == "网络连接失败：超时")
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter HTTPRetryTests 2>&1 | tail -15`
Expected: 编译失败，`cannot find type 'HTTPClient' in scope`。

- [ ] **Step 4: 实现 `Sources/RimeKit/Net/HTTPClient.swift`**

```swift
import Foundation

/// 网络访问。正式用 URLSessionHTTPClient，测试换成假的。
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> Data
    func download(_ url: URL, to destination: URL) async throws
}

public enum HTTPError: Error, Equatable, Sendable, CustomStringConvertible {
    case status(Int, URL)
    case transport(String)

    /// 断网、服务器出错、请求太快可以重试；被拒绝（403，多半是 GitHub 限流）、找不到（404）不重试
    public var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .status(let code, _): return code == 429 || (500...599).contains(code)
        }
    }

    public var description: String {
        switch self {
        case .transport(let message):
            return "网络连接失败：\(message)"
        case .status(403, let url):
            return "GitHub 拒绝了请求（403），可能是一小时内访问次数超过了限制，请过一会儿再试：\(url.absoluteString)"
        case .status(404, let url):
            return "找不到（404）：\(url.absoluteString)"
        case .status(let code, let url):
            return "服务器返回错误 \(code)：\(url.absoluteString)"
        }
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request(url))
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        try check(response, url)
        return data
    }

    public func download(_ url: URL, to destination: URL) async throws {
        let (temp, response): (URL, URLResponse)
        do {
            (temp, response) = try await URLSession.shared.download(for: request(url))
        } catch {
            throw HTTPError.transport(error.localizedDescription)
        }
        try check(response, url)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temp, to: destination)
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("squirrel-macos", forHTTPHeaderField: "User-Agent")
        if url.host() == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        return request
    }

    private func check(_ response: URLResponse, _ url: URL) throws {
        guard let http = response as? HTTPURLResponse else { throw HTTPError.transport("不是 HTTP 响应") }
        guard http.statusCode == 200 else { throw HTTPError.status(http.statusCode, url) }
    }
}

public struct RetryPolicy: Sendable {
    public var attempts: Int
    public var delay: Duration

    public init(attempts: Int, delay: Duration) {
        self.attempts = attempts
        self.delay = delay
    }

    /// 正式使用：最多 3 次，每次间隔 2 秒
    public static let standard = RetryPolicy(attempts: 3, delay: .seconds(2))
    /// 测试用：最多 3 次，不等待
    public static let immediate = RetryPolicy(attempts: 3, delay: .zero)
}

/// 出错时按策略重试；不该重试的错误（HTTPError.isRetryable == false）马上抛出
func withRetry<T: Sendable>(_ policy: RetryPolicy, _ operation: @Sendable () async throws -> T) async throws -> T {
    var lastError: any Error = HTTPError.transport("没有尝试")
    for attempt in 1...max(1, policy.attempts) {
        do {
            return try await operation()
        } catch let error as HTTPError where !error.isRetryable {
            throw error
        } catch {
            lastError = error
            if attempt < policy.attempts { try await Task.sleep(for: policy.delay) }
        }
    }
    throw lastError
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter HTTPRetryTests 2>&1 | tail -5`
Expected: 5 个测试全部通过。

- [ ] **Step 6: 提交**

```bash
git add Sources/RimeKit/Net Tests/RimeKitTests
git commit -m "feat: 网络协议、URLSession 实现和重试

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 问 GitHub 最新版本和下载地址 `SourceResolver`

**Files:**
- Create: `Sources/RimeKit/Packages/SourceResolver.swift`
- Modify: `Tests/RimeKitTests/Support/Fixtures.swift`（加 GitHub 接口的假数据）
- Test: `Tests/RimeKitTests/SourceResolverTests.swift`

**Interfaces:**
- Consumes: `PackageSource`（任务 3）、`HTTPClient`、`HTTPError`、`RetryPolicy`、`withRetry`（任务 5）。
- Produces:
  - `public struct ResolvedSource: Sendable, Equatable { public let version: String; public let downloadURL: URL }`
  - `public enum SourceError: Error, Equatable, Sendable, CustomStringConvertible { case assetNotFound(repo: String, tag: String, asset: String); case badResponse(URL) }`
  - `public struct SourceResolver: Sendable { public init(http: any HTTPClient, retry: RetryPolicy = .standard); public func resolve(_ source: PackageSource) async throws -> ResolvedSource }`
  - 接口地址：`https://api.github.com/repos/<repo>/releases/tags/<tag>`（读 `assets[].name/browser_download_url/updated_at`）；`https://api.github.com/repos/<repo>/commits/<branch>`（读 `sha`），下载地址 `https://codeload.github.com/<repo>/zip/<sha>`
  - 测试辅助 `Fixtures.releaseJSON(assets:)`、`Fixtures.commitJSON(sha:)`、各个假地址

- [ ] **Step 1: 往 `Fixtures.swift` 里加 GitHub 假数据（加在 `enum Fixtures` 里面）**

```swift
    // MARK: GitHub 接口

    static let baseReleaseURL = URL(string: "https://api.github.com/repos/o/base/releases/tags/t")!
    static let baseZipURL = URL(string: "https://example.com/dl/base.zip")!
    static let appCommitURL = URL(string: "https://api.github.com/repos/o/app/commits/main")!

    static func appZipURL(_ sha: String) -> URL {
        URL(string: "https://codeload.github.com/o/app/zip/\(sha)")!
    }

    /// assets: (附件名, 下载地址, 更新时间)
    static func releaseJSON(assets: [(String, URL, String)]) -> Data {
        let items = assets.map { name, url, updated in
            #"{"name":"\#(name)","browser_download_url":"\#(url.absoluteString)","updated_at":"\#(updated)","size":1}"#
        }
        return Data(#"{"tag_name":"t","assets":[\#(items.joined(separator: ","))]}"#.utf8)
    }

    static func commitJSON(sha: String) -> Data {
        Data(#"{"sha":"\#(sha)","commit":{"message":"x"}}"#.utf8)
    }
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/SourceResolverTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct SourceResolverTests {
    @Test func Release附件用更新时间当版本() async throws {
        let http = FakeHTTPClient()
        http.stub(Fixtures.baseReleaseURL, .success(Fixtures.releaseJSON(assets: [
            ("other.zip", URL(string: "https://example.com/other.zip")!, "2020-01-01T00:00:00Z"),
            ("base.zip", Fixtures.baseZipURL, "2026-10-05T13:38:43Z"),
        ])))
        let resolver = SourceResolver(http: http, retry: .immediate)
        let r = try await resolver.resolve(.githubReleaseAsset(repo: "o/base", tag: "t", asset: "base.zip"))
        #expect(r == ResolvedSource(version: "2026-10-05T13:38:43Z", downloadURL: Fixtures.baseZipURL))
    }

    @Test func Release里没有这个附件() async {
        let http = FakeHTTPClient()
        http.stub(Fixtures.baseReleaseURL, .success(Fixtures.releaseJSON(assets: [])))
        let resolver = SourceResolver(http: http, retry: .immediate)
        await #expect(throws: SourceError.assetNotFound(repo: "o/base", tag: "t", asset: "base.zip")) {
            try await resolver.resolve(.githubReleaseAsset(repo: "o/base", tag: "t", asset: "base.zip"))
        }
    }

    @Test func 分支用提交号当版本并按提交号下载() async throws {
        let http = FakeHTTPClient()
        http.stub(Fixtures.appCommitURL, .success(Fixtures.commitJSON(sha: "18a6016c")))
        let resolver = SourceResolver(http: http, retry: .immediate)
        let r = try await resolver.resolve(.githubBranch(repo: "o/app", branch: "main"))
        #expect(r == ResolvedSource(version: "18a6016c", downloadURL: Fixtures.appZipURL("18a6016c")))
    }

    @Test func 被GitHub限流时报HTTP错误而不是解析错误() async {
        let http = FakeHTTPClient()
        http.stub(Fixtures.appCommitURL, .failure(.status(403, Fixtures.appCommitURL)))
        let resolver = SourceResolver(http: http, retry: .immediate)
        await #expect(throws: HTTPError.status(403, Fixtures.appCommitURL)) {
            try await resolver.resolve(.githubBranch(repo: "o/app", branch: "main"))
        }
    }

    @Test func 返回内容看不懂() async {
        let http = FakeHTTPClient()
        http.stub(Fixtures.appCommitURL, .success(Data("<html>".utf8)))
        let resolver = SourceResolver(http: http, retry: .immediate)
        await #expect(throws: SourceError.badResponse(Fixtures.appCommitURL)) {
            try await resolver.resolve(.githubBranch(repo: "o/app", branch: "main"))
        }
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter SourceResolverTests 2>&1 | tail -15`
Expected: 编译失败，`cannot find 'SourceResolver' in scope`。

- [ ] **Step 4: 实现 `Sources/RimeKit/Packages/SourceResolver.swift`**

```swift
import Foundation

public struct ResolvedSource: Sendable, Equatable {
    public let version: String
    public let downloadURL: URL

    public init(version: String, downloadURL: URL) {
        self.version = version
        self.downloadURL = downloadURL
    }
}

public enum SourceError: Error, Equatable, Sendable, CustomStringConvertible {
    case assetNotFound(repo: String, tag: String, asset: String)
    case badResponse(URL)

    public var description: String {
        switch self {
        case let .assetNotFound(repo, tag, asset):
            return "GitHub 上 \(repo) 的 \(tag) 版本里找不到 \(asset)，上游可能改了发布方式，需要更新应用"
        case .badResponse(let url):
            return "看不懂 GitHub 返回的内容：\(url.absoluteString)"
        }
    }
}

/// 问 GitHub：这个包现在的最新版本是什么、从哪下载
public struct SourceResolver: Sendable {
    let http: any HTTPClient
    let retry: RetryPolicy

    public init(http: any HTTPClient, retry: RetryPolicy = .standard) {
        self.http = http
        self.retry = retry
    }

    public func resolve(_ source: PackageSource) async throws -> ResolvedSource {
        switch source {
        case let .githubReleaseAsset(repo, tag, asset):
            let url = URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!
            let release: Release = try await fetchJSON(url)
            guard let found = release.assets.first(where: { $0.name == asset }) else {
                throw SourceError.assetNotFound(repo: repo, tag: tag, asset: asset)
            }
            return ResolvedSource(version: found.updatedAt, downloadURL: found.downloadURL)

        case let .githubBranch(repo, branch):
            let url = URL(string: "https://api.github.com/repos/\(repo)/commits/\(branch)")!
            let commit: Commit = try await fetchJSON(url)
            return ResolvedSource(
                version: commit.sha,
                downloadURL: URL(string: "https://codeload.github.com/\(repo)/zip/\(commit.sha)")!)
        }
    }

    private func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        let http = self.http
        let data = try await withRetry(retry) { try await http.get(url) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.badResponse(url)
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let downloadURL: URL
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case name
                case downloadURL = "browser_download_url"
                case updatedAt = "updated_at"
            }
        }
        let assets: [Asset]
    }

    private struct Commit: Decodable {
        let sha: String
    }
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter SourceResolverTests 2>&1 | tail -5`
Expected: 5 个测试全部通过。

- [ ] **Step 6: 提交**

```bash
git add Sources/RimeKit/Packages/SourceResolver.swift Tests/RimeKitTests
git commit -m "feat: SourceResolver 从 GitHub 取最新版本和下载地址

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 解压和下载缓存 `PackageStore`

**Files:**
- Create: `Sources/RimeKit/Support/Shell.swift`
- Create: `Sources/RimeKit/Support/Hashing.swift`
- Create: `Sources/RimeKit/Packages/Unzipper.swift`
- Create: `Sources/RimeKit/Packages/PackageStore.swift`
- Create: `Tests/RimeKitTests/Support/ZipFixture.swift`
- Modify: `Tests/RimeKitTests/Support/Fixtures.swift`（加测试 zip 和一次设置好全部假地址的辅助函数）
- Test: `Tests/RimeKitTests/PackageStoreTests.swift`

**Interfaces:**
- Consumes: `AppPaths`（任务 1）、`PackageSpec`、`Catalog.installOrder`（任务 3）、`HTTPClient`、`RetryPolicy`、`withRetry`（任务 5）、`SourceResolver`（任务 6）。
- Produces:
  - `struct ShellResult { status: Int32; stdout: String; stderr: String }`，`enum Shell { static func run(_ executable: String, _ arguments: [String]) throws -> ShellResult }`（RimeKit 内部）
  - `enum Hashing { static func sha256(of file: URL) throws -> String }`（内部）
  - `public struct Unzipper: Sendable { public init(); public func unzip(_ zip: URL, into directory: URL) throws }`，`public enum UnzipError: Error, Equatable { case failed(status: Int32, message: String) }`
  - `public struct PackageInfo: Sendable, Equatable, Codable { id, version: String; sourceURL: URL; zipSHA256: String; fetchedAt: Date; files: [String] }`（存成 `packages/<目录名>/package.json`）
  - `public struct CachedPackage: Sendable, Equatable { public let info: PackageInfo; public let filesDirectory: URL }`
  - `public enum PackageStoreError: Error, Equatable, Sendable, CustomStringConvertible { case anchorNotFound(package: String, anchor: String); case missingRequiredFiles(package: String, files: [String]) }`
  - `public struct PackageStore: Sendable { public let paths: AppPaths; public init(paths: AppPaths, http: any HTTPClient = URLSessionHTTPClient(), retry: RetryPolicy = .standard, now: @escaping @Sendable () -> Date = { Date() }); public static func directoryName(id: String, version: String) -> String; public func cached(_ id: String, version: String) -> CachedPackage?; public func cachedVersions(_ id: String) -> [CachedPackage] /* 最新取到的在前 */; public func latestCached(_ id: String) -> CachedPackage?; public func fetch(_ spec: PackageSpec) async throws -> CachedPackage; public func fetchAll(_ ids: [String], catalog: Catalog) async throws -> [CachedPackage] }`
  - 缓存目录：`packages/<id>@<版本>/package.json` + `packages/<id>@<版本>/files/…`。版本里 `A-Z a-z 0-9 . _ -` 以外的字符换成 `-`。**只有带合法 `package.json` 的目录才算缓存。**
  - 测试辅助 `ZipFixture.make(_ files: [String: String], topFolder: String?, symlinks: [String: String] = [:]) throws -> Data`、`Fixtures.baseZip()`、`Fixtures.appZip(sha:)`、`Fixtures.stubAll(_ http:, baseVersion:, appSHA:)`

- [ ] **Step 1: 写 `Sources/RimeKit/Support/Shell.swift` 和 `Hashing.swift`**

```swift
import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// 运行一个外部程序并等它结束（只用于系统自带的小工具，比如 ditto）
enum Shell {
    static func run(_ executable: String, _ arguments: [String]) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }
}
```

```swift
import CryptoKit
import Foundation

enum Hashing {
    static func sha256(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 2: 写测试辅助 `Tests/RimeKitTests/Support/ZipFixture.swift`**

```swift
import Foundation
@testable import RimeKit

/// 用 ditto 现场造一个 zip，内容由测试决定
enum ZipFixture {
    /// files：相对路径 → 文字内容；topFolder 不为 nil 时 zip 里多一层这个名字的目录；
    /// symlinks：相对路径 → 链接指向的路径
    static func make(_ files: [String: String], topFolder: String?, symlinks: [String: String] = [:]) throws -> Data {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appending(path: "zipfixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: base) }
        let content = base.appending(path: topFolder ?? "content", directoryHint: .isDirectory)
        try fm.createDirectory(at: content, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = content.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        for (path, target) in symlinks {
            try fm.createSymbolicLink(atPath: content.appending(path: path).path, withDestinationPath: target)
        }
        let zip = base.appending(path: "out.zip")
        var args = ["-c", "-k", "--sequesterRsrc"]
        if topFolder != nil { args.append("--keepParent") }
        args += [content.path, zip.path]
        let result = try Shell.run("/usr/bin/ditto", args)
        precondition(result.status == 0, "造 zip 失败：\(result.stderr)")
        return try Data(contentsOf: zip)
    }
}
```

- [ ] **Step 3: 往 `Fixtures.swift` 里加测试 zip 和设置假地址的辅助函数（加在 `enum Fixtures` 里面）**

```swift
    // MARK: 测试 zip

    /// base：没有顶层目录；有一个要排除的文件、一个不该装的 README
    static func baseZip() throws -> Data {
        try ZipFixture.make([
            "base.schema.yaml": "base",
            "dicts/a.dict.yaml": "a",
            "dicts/sub/b.dict.yaml": "b",
            "dicts/skip.txt": "skip",
            "README.md": "readme",
        ], topFolder: nil)
    }

    /// app：有顶层目录 app-<sha>/（像 codeload 的 zip）
    static func appZip(sha: String) throws -> Data {
        try ZipFixture.make(["app.schema.yaml": "app", "notes.txt": "n"], topFolder: "app-\(sha)")
    }

    /// 把 base 和 app 的接口、下载地址都设置好
    static func stubAll(_ http: FakeHTTPClient, baseVersion: String = "2026-10-05T13:38:43Z", appSHA: String = "abc123") throws {
        http.stub(baseReleaseURL, .success(releaseJSON(assets: [("base.zip", baseZipURL, baseVersion)])))
        http.stub(baseZipURL, .success(try baseZip()))
        http.stub(appCommitURL, .success(commitJSON(sha: appSHA)))
        http.stub(appZipURL(appSHA), .success(try appZip(sha: appSHA)))
    }

    static func paths(_ dir: TempDir) -> AppPaths {
        AppPaths(root: dir.url.appending(path: "data", directoryHint: .isDirectory))
    }
```

- [ ] **Step 4: 写失败的测试 `Tests/RimeKitTests/PackageStoreTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct PackageStoreTests {
    @Test func 没有顶层目录的zip按规则挑文件() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkg = try await store.fetch(try #require(try Fixtures.catalog().package("base")))

        #expect(pkg.info.id == "base")
        #expect(pkg.info.version == "2026-10-05T13:38:43Z")
        #expect(pkg.info.files == ["base.schema.yaml", "dicts/a.dict.yaml", "dicts/sub/b.dict.yaml"])
        #expect(pkg.info.zipSHA256.count == 64)
        let text = try String(contentsOf: pkg.filesDirectory.appending(path: "dicts/sub/b.dict.yaml"), encoding: .utf8)
        #expect(text == "b")
        #expect(!FileManager.default.fileExists(atPath: pkg.filesDirectory.appending(path: "README.md").path))
        #expect(!FileManager.default.fileExists(atPath: pkg.filesDirectory.appending(path: "dicts/skip.txt").path))
    }

    @Test func 有顶层目录的zip靠定位文件找到根目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, appSHA: "18a6016c")
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkg = try await store.fetch(try #require(try Fixtures.catalog().package("app")))
        #expect(pkg.info.version == "18a6016c")
        #expect(pkg.info.files == ["app.schema.yaml"])
        #expect(pkg.info.sourceURL == Fixtures.appZipURL("18a6016c"))
    }

    @Test func 版本号里的冒号不进目录名() {
        #expect(PackageStore.directoryName(id: "rime-ice", version: "2026-10-05T13:38:43Z") == "rime-ice@2026-10-05T13-38-43Z")
        #expect(PackageStore.directoryName(id: "x", version: "a/b c") == "x@a-b-c")
    }

    @Test func 已经缓存的版本不再下载() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let spec = try #require(try Fixtures.catalog().package("base"))
        let first = try await store.fetch(spec)
        let second = try await store.fetch(spec)
        #expect(first == second)
        #expect(http.callCount(Fixtures.baseZipURL) == 1)
        #expect(http.callCount(Fixtures.baseReleaseURL) == 2)   // 每次都要问最新版本
    }

    @Test func 缺必需文件时报错而且不留缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .success(try ZipFixture.make(["base.schema.yaml": "b"], topFolder: nil)))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        await #expect(throws: PackageStoreError.missingRequiredFiles(package: "base", files: ["dicts/a.dict.yaml"])) {
            try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        }
        #expect(store.cachedVersions("base").isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: Fixtures.paths(dir).packages.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func 找不到定位文件() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .success(try ZipFixture.make(["other.yaml": "x"], topFolder: "x")))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        await #expect(throws: PackageStoreError.anchorNotFound(package: "base", anchor: "base.schema.yaml")) {
            try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        }
    }

    @Test func 下载到一半断网不留缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .failure(.transport("断网")))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        await #expect(throws: HTTPError.transport("断网")) {
            try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        }
        #expect(http.callCount(Fixtures.baseZipURL) == 3)   // 重试过
        #expect(store.latestCached("base") == nil)
    }

    @Test func 没有package_json的残留目录不算缓存() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let half = paths.packages.appending(path: "base@v1/files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: half, withIntermediateDirectories: true)
        let store = PackageStore(paths: paths, http: FakeHTTPClient(), retry: .immediate)
        #expect(store.cached("base", version: "v1") == nil)
        #expect(store.cachedVersions("base").isEmpty)
    }

    @Test func zip里的符号链接不复制() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        http.stub(Fixtures.baseZipURL, .success(try ZipFixture.make(
            ["base.schema.yaml": "b", "dicts/a.dict.yaml": "a"],
            topFolder: nil,
            symlinks: ["dicts/evil.dict.yaml": "/etc/hosts"])))
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkg = try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        #expect(pkg.info.files == ["base.schema.yaml", "dicts/a.dict.yaml"])
        let evil = pkg.filesDirectory.appending(path: "dicts/evil.dict.yaml").path
        #expect((try? FileManager.default.attributesOfItem(atPath: evil)) == nil)
    }

    @Test func 新旧版本都保留而且最新取到的排前面() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let paths = Fixtures.paths(dir)
        let spec = try #require(try Fixtures.catalog().package("base"))

        try Fixtures.stubAll(http, baseVersion: "v1")
        let store = PackageStore(paths: paths, http: http, retry: .immediate, now: clock.next)
        _ = try await store.fetch(spec)
        try Fixtures.stubAll(http, baseVersion: "v2")
        _ = try await store.fetch(spec)

        #expect(store.cachedVersions("base").map(\.info.version) == ["v2", "v1"])
        #expect(store.latestCached("base")?.info.version == "v2")
        #expect(store.cached("base", version: "v1") != nil)
    }

    @Test func 一次取多个包时依赖在前() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let store = PackageStore(paths: Fixtures.paths(dir), http: http, retry: .immediate)
        let pkgs = try await store.fetchAll(["app"], catalog: try Fixtures.catalog())
        #expect(pkgs.map(\.info.id) == ["base", "app"])
    }

    @Test func 下载用的暂存目录用完就删() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let paths = Fixtures.paths(dir)
        let store = PackageStore(paths: paths, http: http, retry: .immediate)
        _ = try await store.fetch(try #require(try Fixtures.catalog().package("base")))
        let left = (try? FileManager.default.contentsOfDirectory(atPath: paths.staging.path)) ?? []
        #expect(left.isEmpty)
    }
}

/// 每次调用往后走一秒的假时钟，让「谁先取到」有确定的顺序
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) { current = start }

    var next: @Sendable () -> Date {
        { [self] in
            lock.withLock {
                current = current.addingTimeInterval(1)
                return current
            }
        }
    }
}
```

- [ ] **Step 5: 运行，确认失败**

Run: `swift test --filter PackageStoreTests 2>&1 | tail -15`
Expected: 编译失败，`cannot find 'PackageStore' in scope`（`Shell` 已经有了，所以 `ZipFixture` 能编译）。

- [ ] **Step 6: 写 `Sources/RimeKit/Packages/Unzipper.swift`**

```swift
import Foundation

public enum UnzipError: Error, Equatable, Sendable, CustomStringConvertible {
    case failed(status: Int32, message: String)

    public var description: String {
        switch self {
        case let .failed(status, message):
            return "解压失败（ditto 退出码 \(status)）：\(message)"
        }
    }
}

/// 用系统自带的 ditto 解压（干净的 macOS 27 上已验证可用，见 verified-facts）
public struct Unzipper: Sendable {
    public init() {}

    public func unzip(_ zip: URL, into directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try Shell.run("/usr/bin/ditto", ["-x", "-k", zip.path, directory.path])
        guard result.status == 0 else {
            throw UnzipError.failed(status: result.status, message: result.stderr)
        }
    }
}
```

- [ ] **Step 7: 写 `Sources/RimeKit/Packages/PackageStore.swift`**

```swift
import Foundation

/// 缓存里一个包的说明，存成 packages/<id>@<版本>/package.json
public struct PackageInfo: Sendable, Equatable, Codable {
    public let id: String
    public let version: String
    public let sourceURL: URL
    public let zipSHA256: String
    public let fetchedAt: Date
    /// 装进来的文件（相对包根目录），已排序
    public let files: [String]
}

public struct CachedPackage: Sendable, Equatable {
    public let info: PackageInfo
    /// 文件所在目录：packages/<id>@<版本>/files
    public let filesDirectory: URL
}

public enum PackageStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case anchorNotFound(package: String, anchor: String)
    case missingRequiredFiles(package: String, files: [String])

    public var description: String {
        switch self {
        case let .anchorNotFound(package, anchor):
            return "\(package) 的下载内容里找不到 \(anchor)，上游方案目录结构变了，需要更新应用"
        case let .missingRequiredFiles(package, files):
            return "\(package) 的下载内容里缺少这些文件：\(files.joined(separator: "、"))。上游方案目录结构变了，需要更新应用"
        }
    }
}

/// 上游包的下载和缓存（设计第 3、5 节）。
/// 先在暂存区做好一个完整的包（最后写 package.json），再整体移进 packages/，
/// 所以中途失败不会留下看起来像缓存的半成品。
public struct PackageStore: Sendable {
    public let paths: AppPaths
    let http: any HTTPClient
    let retry: RetryPolicy
    let resolver: SourceResolver
    let now: @Sendable () -> Date

    public init(
        paths: AppPaths,
        http: any HTTPClient = URLSessionHTTPClient(),
        retry: RetryPolicy = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.paths = paths
        self.http = http
        self.retry = retry
        self.resolver = SourceResolver(http: http, retry: retry)
        self.now = now
    }

    /// 缓存目录名：<id>@<版本>，版本里不安全的字符换成 "-"
    public static func directoryName(id: String, version: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let safe = String(version.map { allowed.contains($0) ? $0 : "-" })
        return "\(id)@\(safe)"
    }

    public func cached(_ id: String, version: String) -> CachedPackage? {
        load(paths.packages.appending(path: Self.directoryName(id: id, version: version), directoryHint: .isDirectory), id: id)
    }

    /// 本地缓存的所有版本，最新取到的在前
    public func cachedVersions(_ id: String) -> [CachedPackage] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.packages.path)) ?? []
        return names
            .filter { $0.hasPrefix("\(id)@") }
            .compactMap { load(paths.packages.appending(path: $0, directoryHint: .isDirectory), id: id) }
            .sorted { $0.info.fetchedAt > $1.info.fetchedAt }
    }

    public func latestCached(_ id: String) -> CachedPackage? {
        cachedVersions(id).first
    }

    /// 取这个包的最新版：本地已有这个版本就直接用，没有就下载
    public func fetch(_ spec: PackageSpec) async throws -> CachedPackage {
        let resolved = try await resolver.resolve(spec.source)
        if let hit = cached(spec.id, version: resolved.version) { return hit }

        let fm = FileManager.default
        let work = paths.staging.appending(path: "fetch-\(spec.id)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zip = work.appending(path: "download.zip")
        let http = self.http
        try await withRetry(retry) { try await http.download(resolved.downloadURL, to: zip) }
        let sha = try Hashing.sha256(of: zip)

        let extracted = work.appending(path: "extracted", directoryHint: .isDirectory)
        try Unzipper().unzip(zip, into: extracted)
        let all = try fm.subpathsOfDirectory(atPath: extracted.path)
        guard let root = Self.locateRoot(in: all, anchor: spec.anchor) else {
            throw PackageStoreError.anchorNotFound(package: spec.id, anchor: spec.anchor)
        }

        let staged = work.appending(path: "package", directoryHint: .isDirectory)
        let filesDir = staged.appending(path: "files", directoryHint: .isDirectory)
        let copied = try Self.copySelected(from: extracted, subpaths: all, root: root, to: filesDir, spec: spec)
        let missing = spec.requiredFiles.filter { !copied.contains($0) }
        guard missing.isEmpty else {
            throw PackageStoreError.missingRequiredFiles(package: spec.id, files: missing)
        }

        let info = PackageInfo(id: spec.id, version: resolved.version, sourceURL: resolved.downloadURL,
                               zipSHA256: sha, fetchedAt: now(), files: copied.sorted())
        try JSONCoding.encoder.encode(info).write(to: staged.appending(path: "package.json"))

        try fm.createDirectory(at: paths.packages, withIntermediateDirectories: true)
        let destination = paths.packages.appending(path: Self.directoryName(id: spec.id, version: resolved.version), directoryHint: .isDirectory)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }   // 没有 package.json 的残留
        try fm.moveItem(at: staged, to: destination)
        // 从磁盘再读一次再返回：JSON 里的时间只精确到秒，这样和以后从缓存读出来的完全一样
        guard let saved = load(destination, id: spec.id) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: destination.path])
        }
        return saved
    }

    /// 取多个包（自动带上依赖，依赖在前）
    public func fetchAll(_ ids: [String], catalog: Catalog) async throws -> [CachedPackage] {
        var result: [CachedPackage] = []
        for spec in try catalog.installOrder(for: ids) {
            result.append(try await fetch(spec))
        }
        return result
    }

    // MARK: 内部

    private func load(_ directory: URL, id: String) -> CachedPackage? {
        guard let data = try? Data(contentsOf: directory.appending(path: "package.json")),
              let info = try? JSONCoding.decoder.decode(PackageInfo.self, from: data),
              info.id == id
        else { return nil }
        return CachedPackage(info: info, filesDirectory: directory.appending(path: "files", directoryHint: .isDirectory))
    }

    /// 找包根目录：哪个目录下有 anchor 这个相对路径的文件。返回 "" 或 "xxx/" 这样的前缀，取最浅的。
    static func locateRoot(in subpaths: [String], anchor: String) -> String? {
        subpaths
            .filter { $0 == anchor || $0.hasSuffix("/" + anchor) }
            .map { String($0.dropLast(anchor.count)) }
            .min { $0.count < $1.count }
    }

    /// 按安装规则把根目录下的普通文件复制出来；符号链接、目录都跳过。返回复制了的相对路径。
    static func copySelected(from extracted: URL, subpaths: [String], root: String, to filesDir: URL, spec: PackageSpec) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        var copied: [String] = []
        for sub in subpaths where sub.hasPrefix(root) {
            let relative = String(sub.dropFirst(root.count))
            guard !relative.isEmpty,
                  spec.include.contains(where: { $0.matches(relative) }),
                  !spec.exclude.contains(where: { $0.matches(relative) })
            else { continue }
            let source = extracted.appending(path: sub)
            let type = try fm.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType
            guard type == .typeRegular else { continue }
            let target = filesDir.appending(path: relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            copied.append(relative)
        }
        return copied
    }
}
```

- [ ] **Step 8: 运行，确认通过**

Run: `swift test --filter PackageStoreTests 2>&1 | tail -5`
Expected: 12 个测试全部通过。

- [ ] **Step 9: 跑全部测试**

Run: `swift test 2>&1 | tail -5`
Expected: 全部通过（AppPaths 2、FileGlob 5、Catalog 11、BuiltInCatalog 4、HTTPRetry 5、SourceResolver 5、PackageStore 12）。

- [ ] **Step 10: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: PackageStore 下载、挑文件、检查结构、按版本缓存

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 命令行 `rimectl catalog` / `rimectl fetch`

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`（替换占位内容）
- Create: `Sources/rimectl/Output.swift`
- Test: `Tests/RimeKitTests/RimectlTests.swift`

**Interfaces:**
- Consumes: `Catalog`、`PackageStore`、`HTTPClient`、`RetryPolicy`、`AppPaths`、各错误类型的 `description`。
- Produces（`rimectl` 模块，测试用 `@testable import rimectl`）：
  - `final class Output: @unchecked Sendable { init(echo: Bool); func line(_ s: String); func error(_ s: String); var text: String }`
  - `struct Rimectl { struct Context { var http: any HTTPClient; var retry: RetryPolicy; var catalog: @Sendable () throws -> Catalog; var defaultPaths: AppPaths; var output: Output }; static func run(_ args: [String], _ context: Context) async -> Int32 }`
  - 命令：`rimectl catalog`；`rimectl fetch [--data-dir 目录] [--cache-only] <包名>...`。退出码：0 成功；1 运行出错；2 用法不对。
  - `fetch` 每个包输出一行：`<id>@<版本>  <N> 个文件  <files 目录>`。断网且本地有旧版本时，错误信息里提示 `--cache-only`。

- [ ] **Step 1: 写失败的测试 `Tests/RimeKitTests/RimectlTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTests {
    func context(_ http: FakeHTTPClient, _ dir: TempDir, catalog: Catalog? = nil) -> (Rimectl.Context, Output) {
        let output = Output(echo: false)
        let fixed = catalog
        let ctx = Rimectl.Context(
            http: http,
            retry: .immediate,
            catalog: { try fixed ?? Fixtures.catalog() },
            defaultPaths: Fixtures.paths(dir),
            output: output)
        return (ctx, output)
    }

    @Test func catalog列出内置的包和方案() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir, catalog: try Catalog.builtIn())
        #expect(await Rimectl.run(["catalog"], ctx) == 0)
        #expect(out.text.contains("rime-ice"))
        #expect(out.text.contains("double_pinyin_flypy"))
        #expect(out.text.contains("GPL-3.0"))
    }

    @Test func fetch带上依赖并输出每个包() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, appSHA: "abc123")
        let (ctx, out) = context(http, dir)
        #expect(await Rimectl.run(["fetch", "app"], ctx) == 0)
        let lines = out.text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("base@2026-10-05T13:38:43Z"))
        #expect(lines[0].contains("3 个文件"))
        #expect(lines[1].hasPrefix("app@abc123"))
    }

    @Test func data_dir可以换数据目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http)
        let (ctx, _) = context(http, dir)
        let other = dir.url.appending(path: "other", directoryHint: .isDirectory)
        #expect(await Rimectl.run(["fetch", "--data-dir", other.path, "base"], ctx) == 0)
        #expect(PackageStore(paths: AppPaths(root: other), http: http).latestCached("base") != nil)
        #expect(PackageStore(paths: Fixtures.paths(dir), http: http).latestCached("base") == nil)
    }

    @Test func 断网时提示可以用旧版本() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "v1")
        let (ctx, out) = context(http, dir)
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 0)
        http.stub(Fixtures.baseReleaseURL, .failure(.transport("断网")))
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 1)
        #expect(out.text.contains("网络连接失败：断网"))
        #expect(out.text.contains("v1"))
        #expect(out.text.contains("--cache-only"))
    }

    @Test func cache_only只用本地缓存不联网() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        try Fixtures.stubAll(http, baseVersion: "v1")
        let (ctx, out) = context(http, dir)
        #expect(await Rimectl.run(["fetch", "base"], ctx) == 0)
        let callsBefore = http.callCount(Fixtures.baseReleaseURL)
        #expect(await Rimectl.run(["fetch", "--cache-only", "base"], ctx) == 0)
        #expect(http.callCount(Fixtures.baseReleaseURL) == callsBefore)
        #expect(out.text.split(separator: "\n").last?.hasPrefix("base@v1") == true)
    }

    @Test func cache_only但没有缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["fetch", "--cache-only", "base"], ctx) == 1)
        #expect(out.text.contains("base：本地没有缓存"))
    }

    @Test func 不认识的包() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["fetch", "nope"], ctx) == 1)
        #expect(out.text.contains("清单里没有这个包：nope"))
    }

    @Test func 用法不对() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run([], ctx) == 2)
        #expect(await Rimectl.run(["what"], ctx) == 2)
        #expect(await Rimectl.run(["fetch"], ctx) == 2)
        #expect(await Rimectl.run(["fetch", "--data-dir"], ctx) == 2)
        #expect(out.text.contains("用法"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RimectlTests 2>&1 | tail -15`
Expected: 编译失败，`type 'Rimectl' has no member 'Context'`。如果报的是「不能 import 可执行目标」，见下面的后备办法。

后备办法：如果 SwiftPM 不允许测试导入 `rimectl`，就把 `Rimectl.swift` 里除 `@main` 入口以外的代码挪到新的库目标 `RimectlCore`（`Sources/RimectlCore/`），`rimectl` 只留一个调用 `RimectlCore.Rimectl.run` 的 `main`，测试改成 `@testable import RimectlCore`。在执行记录里写一条 Ruling。

- [ ] **Step 3: 写 `Sources/rimectl/Output.swift`**

```swift
import Foundation

/// 命令行输出：正常运行时打印到终端，测试时收集起来检查
final class Output: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let echo: Bool

    init(echo: Bool) {
        self.echo = echo
    }

    func line(_ s: String) {
        lock.withLock { lines.append(s) }
        if echo { print(s) }
    }

    func error(_ s: String) {
        lock.withLock { lines.append(s) }
        if echo { FileHandle.standardError.write(Data((s + "\n").utf8)) }
    }

    var text: String {
        lock.withLock { lines.joined(separator: "\n") }
    }
}
```

- [ ] **Step 4: 写 `Sources/rimectl/Rimectl.swift`**

```swift
import Foundation
import RimeKit

/// rimectl：RimeKit 的命令行入口，用来在测试机里通过 SSH 跑完整流程
@main
struct Rimectl {
    struct Context: Sendable {
        var http: any HTTPClient
        var retry: RetryPolicy
        var catalog: @Sendable () throws -> Catalog
        var defaultPaths: AppPaths
        var output: Output
    }

    static let usage = """
    用法：
      rimectl catalog                                    列出内置方案清单
      rimectl fetch [--data-dir 目录] [--cache-only] 包名...   下载（或从缓存取）这些包和它们的依赖
    """

    static func main() async {
        let context = Context(
            http: URLSessionHTTPClient(),
            retry: .standard,
            catalog: { try Catalog.builtIn() },
            defaultPaths: .default,
            output: Output(echo: true))
        exit(await run(Array(CommandLine.arguments.dropFirst()), context))
    }

    static func run(_ args: [String], _ context: Context) async -> Int32 {
        let out = context.output
        var dataDir: String?
        var cacheOnly = false
        var positional: [String] = []
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--data-dir":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                dataDir = args[i + 1]
                i += 2
            case "--cache-only":
                cacheOnly = true
                i += 1
            case "-h", "--help":
                out.line(usage)
                return 0
            default:
                positional.append(args[i])
                i += 1
            }
        }
        guard let command = positional.first else { out.error(usage); return 2 }
        let paths = dataDir.map { AppPaths(root: URL(fileURLWithPath: $0, isDirectory: true)) } ?? context.defaultPaths

        do {
            switch command {
            case "catalog":
                try listCatalog(try context.catalog(), out)
                return 0
            case "fetch":
                let ids = Array(positional.dropFirst())
                guard !ids.isEmpty else { out.error(usage); return 2 }
                return try await fetch(ids, cacheOnly: cacheOnly, paths: paths, context)
            default:
                out.error(usage)
                return 2
            }
        } catch {
            out.error(String(describing: error))
            return 1
        }
    }

    private static func listCatalog(_ catalog: Catalog, _ out: Output) throws {
        for p in catalog.packages {
            out.line("\(p.id)  \(p.name)  \(p.license)")
            for s in p.schemas {
                out.line("  - \(s.id)  \(s.name)")
            }
        }
    }

    private static func fetch(_ ids: [String], cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        let catalog = try context.catalog()
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        for spec in try catalog.installOrder(for: ids) {
            if cacheOnly {
                guard let pkg = store.latestCached(spec.id) else {
                    out.error("\(spec.id)：本地没有缓存")
                    return 1
                }
                report(pkg, out)
                continue
            }
            do {
                report(try await store.fetch(spec), out)
            } catch let error as HTTPError {
                var message = "\(spec.id)：下载失败。\(error)"
                if let old = store.latestCached(spec.id) {
                    message += "\n本地有缓存的旧版本 \(old.info.version)，可以加 --cache-only 先用它"
                }
                out.error(message)
                return 1
            }
        }
        return 0
    }

    private static func report(_ pkg: CachedPackage, _ out: Output) {
        out.line("\(pkg.info.id)@\(pkg.info.version)  \(pkg.info.files.count) 个文件  \(pkg.filesDirectory.path)")
    }
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter RimectlTests 2>&1 | tail -5`
Expected: 8 个测试全部通过。

- [ ] **Step 6: 跑全部测试**

Run: `swift test 2>&1 | tail -5`
Expected: 全部通过（共 52 个）。

- [ ] **Step 7: 提交**

```bash
git add Sources/rimectl Tests/RimeKitTests/RimectlTests.swift
git commit -m "feat: rimectl catalog / fetch 命令

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 联网测试、真实下载，以及在测试机里跑一遍

**Files:**
- Create: `Tests/RimeKitTests/OnlineTests.swift`
- Modify: `README.md`（加「开发」一节）
- Modify: `CLAUDE.md`（加 Swift 工程的常用命令）
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`（阶段 1 标为完成）

**Interfaces:**
- Consumes: `Catalog.builtIn()`、`PackageStore`、`URLSessionHTTPClient`。
- Produces: 设置环境变量 `RIMEKIT_ONLINE=1` 才会跑的联网测试。

- [ ] **Step 1: 写联网测试 `Tests/RimeKitTests/OnlineTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

/// 真的去 GitHub 下载内置清单里的包，检查上游结构没变。默认不跑：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1"))
struct OnlineTests {
    @Test(arguments: ["rime-ice", "rime-ice-dicts", "wubi86-jidian"])
    func 真实下载内置清单里的包(id: String) async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let catalog = try Catalog.builtIn()
        let spec = try #require(catalog.package(id))
        let store = PackageStore(paths: Fixtures.paths(dir))
        let pkg = try await store.fetch(spec)
        for file in spec.requiredFiles {
            #expect(pkg.info.files.contains(file), "缺少 \(file)")
        }
        #expect(!pkg.info.version.isEmpty)
    }
}
```

- [ ] **Step 2: 确认默认不跑**

Run: `swift test --filter OnlineTests 2>&1 | tail -5`
Expected: 测试被跳过（显示 skipped），不联网。

- [ ] **Step 3: 联网跑一次**

Run: `RIMEKIT_ONLINE=1 swift test --filter OnlineTests 2>&1 | tail -8`
Expected: 3 个参数全部通过。如果某个包报 `missingRequiredFiles` 或 `anchorNotFound`，说明清单和上游不一致：对照 [upstream-layouts.md](../../upstream-layouts.md) 修 `catalog.json`，并在执行记录里写 Ruling。

- [ ] **Step 4: 在宿主机上用临时数据目录试 `rimectl`**

```bash
swift build 2>&1 | tail -2
D=$(mktemp -d)
.build/debug/rimectl catalog
.build/debug/rimectl fetch --data-dir "$D" wubi86-jidian rime-ice rime-ice-dicts
.build/debug/rimectl fetch --data-dir "$D" --cache-only wubi86-jidian
ls "$D/packages"
rm -rf "$D"
```

Expected：`catalog` 列出 3 个包和 8 个方案；`fetch` 输出 3 行（`wubi86-jidian@<40 位 sha>  约 16 个文件`、`rime-ice@2026-…  约 60 多个文件`、`rime-ice-dicts@2026-…  3 个文件`）；`--cache-only` 立刻输出同一个版本；`packages/` 下有 3 个目录，名字里没有冒号。

- [ ] **Step 5: 在测试机 `squirrel-dev` 里跑一遍（干净的系统里没有开发工具，验证 rimectl 能直接运行）**

先确认测试机开着（`./tools/vm/vm.sh list` 里 `squirrel-dev` 是 running；没开就 `tart run squirrel-dev --dir=vm:$PWD/tools/vm:ro --dir=project:$PWD:ro &`，SSH 能连就行，这一步不需要桌面）。然后：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'R="/Volumes/My Shared Files/project/.build/debug/rimectl"; rm -rf /tmp/rk; "$R" catalog | head -3; "$R" fetch --data-dir /tmp/rk wubi86-jidian rime-ice rime-ice-dicts; echo "exit=$?"; ls /tmp/rk/packages'
```

Expected：和宿主机一样输出 3 行，`exit=0`。这说明 `rimectl`（连同旁边的资源包 `SquirrelMacOS_RimeKit.bundle`）在没有开发工具的 Mac 上能运行，`ditto` 解压也正常。

- [ ] **Step 6: 更新文档**

`README.md` 末尾加：

```markdown
## 开发

Swift Package（需要 Xcode 27）：`RimeKit` 是全部逻辑，`rimectl` 是命令行入口。

- 跑测试（只用临时目录，不碰真实配置）：`swift test`
- 联网检查上游结构有没有变：`RIMEKIT_ONLINE=1 swift test --filter OnlineTests`
- 试用命令行：`swift build && .build/debug/rimectl catalog`；下载时请加 `--data-dir 某个临时目录`
```

`CLAUDE.md` 的「工作方式」一节末尾加一行：

```markdown
- Swift 工程：`swift test` 跑全部单元测试（只用临时目录）；`RIMEKIT_ONLINE=1 swift test --filter OnlineTests` 联网检查上游；手动试 `rimectl fetch` 一律加 `--data-dir`，别写进真实的 `~/Library/Application Support/squirrel-macos`。测试机里可以直接运行 `/Volumes/My Shared Files/project/.build/debug/rimectl`。
```

`docs/superpowers/plans/2026-10-15-roadmap.md` 表格里阶段 1 那一行的「成果」列末尾加「（已完成，2026-10-15）」。

- [ ] **Step 7: 跑全部测试，然后提交、推送**

Run: `swift test 2>&1 | tail -5`
Expected: 全部通过，联网测试显示 skipped。

```bash
git add Tests/RimeKitTests/OnlineTests.swift README.md CLAUDE.md docs/superpowers/plans/2026-10-15-roadmap.md
git commit -m "test: 联网检查上游结构；文档加开发说明

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```

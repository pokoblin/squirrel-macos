# 在线方案清单 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 方案清单除了内置的，还能从 GitHub 拉一份签过名的在线版。用户点「检查方案清单更新」才拉；导入时遇到不认识的方案会自动拉一次。不发版就能加新方案、修上游结构变化。

**Architecture:**
- RimeKit 的 `Catalog` 模块新增四样：签名（`CatalogSignature`）、两份清单的比较（`CatalogDiff`、`CatalogPublishCheck`）、生效清单和在线更新（`CatalogStore`）。
- 应用里用一个共享的 `CatalogHolder` 放当前生效的清单，引导和主窗口都从它取。
- rimectl 的所有命令改用 `CatalogStore.effective()`，另加 `catalog show/check` 和几个发布用的隐藏子命令。
- 发布靠 `tools/catalog/publish.sh`：校验 → 复制到 `catalog/v1/` → 用钥匙串里的私钥签名。

**Tech Stack:** Swift 6.4、CryptoKit（`Curve25519.Signing`，系统自带）、Swift Testing、SwiftUI、bash、`security`、`curl`。

**Spec:** [docs/superpowers/specs/2026-10-15-online-catalog-design.md](../specs/2026-10-15-online-catalog-design.md)（下面写成「设计 x.y」）。路线图：[2026-10-15-v2-roadmap.md](2026-10-15-v2-roadmap.md)。

## 计划里定下的细节（设计没写死的地方）

| # | 问题 | 计划里的做法 |
|---|---|---|
| 1 | `serial` 是必填吗 | 读的时候没有就当成 0（测试里的清单不用改）。内置清单有测试要求大于 0；在线清单必须比手头的大，所以没写 serial 的在线清单自然不会被采用。发布脚本也要求大于 0 |
| 2 | 应用版本号从哪来 | RimeKit 加 `AppInfo.version = "0.2.0"`，有测试检查它和 `tools/app/Info.plist` 一致 |
| 3 | 「在线（某日检查）」的日期 | 用缓存文件的修改时间，也就是下载并采用的那一天。界面上写「某日下载」 |
| 4 | 「规则变了」怎么算 | 比较下载来源、anchor、include、exclude、requiredFiles、方案、依赖、选项、个人词库模板。只改了名字、说明、许可证、主页、是否下架的，不算 |
| 5 | 「诊断」页的域名 | 下载 Release 附件时 GitHub 会跳转到它自己的下载服务器，所以写成「github.com 和它的下载服务器」，不列具体域名 |
| 6 | 签名、生成密钥放在哪 | RimeKit 的 `CatalogSignature`，rimectl 加隐藏子命令 `catalog keygen/sign/verify/verify-source`（不写进 usage，写进 `docs/release.md`）。发布包里没有 rimectl |
| 7 | 测试机里怎么试在线清单 | debug 编译认两个环境变量：`RIMEKIT_CATALOG_URL`、`RIMEKIT_CATALOG_TEST_PUBKEY`。宿主机用 `python3 -m http.server` 把测试清单发给测试机 |
| 8 | 联网测试 | `OnlineTests` 的下载测试改成对内置清单里的每个包都跑；新增一条检查真实的在线清单。`OnlineGenerateTests` 按起步方案测，不会自动覆盖新包，加新方案时要手动补打字检查（写进 `docs/release.md`） |

## Global Constraints

- 宿主机不运行应用，不碰 `~/Library/Rime`、`/Library/Input Methods`、输入法状态；单元测试只用临时目录。
- 不加第三方依赖（签名用系统自带的 CryptoKit）。
- 在线清单地址：`https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json`，签名在同一目录的 `catalog.json.sig`。只用 GitHub，不配镜像（设计 1）。
- 应用只在用户点「检查方案清单更新」时拉清单；唯一的例外是导入时遇到不认识的方案（设计 4.5）。打开应用、第一次打开的引导都不联网拉清单。
- 签名：Ed25519，签清单文件的原始字节；签名文件是一行 base64（设计 5.1）。私钥只放在宿主机登录钥匙串（服务名 `squirrel-macos-catalog-signing`），不进 git、不打印到日志。
- 界面和提示用简单直白的中文；应用里不让用户运行 rimectl（`AppWording` 负责换说法）。
- 每个任务：先写测试看它失败，再实现，再跑 `swift test`（全部通过）。视图层没有单元测试，用 `swift build` 编译通过，测试机里检查。
- 提交：按任务提交，提交信息结尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。推送 `main`、生成真正的签名密钥前先问用户。
- 测试机：用长期的 `squirrel-dev`，数据目录用新的（例如 `/tmp/rk-catalog`），别动 `/tmp/rk`；登录桌面、在界面上点按钮由用户来做。

## Review Focus

1. **缓存清单坏了**（半个文件、签名对不上、手动改过）：应用照常打开，退回内置清单，「诊断」页说原因——任务 4 有测试（缓存签名不对、只剩一个文件）。
2. **在线清单拿掉了正在用的方案**（发布时漏掉、或 `minAppVersion` 挡掉）：不采用，原来的设置不受影响——任务 4 有测试（`和正在用的设置对不上就不采用`），任务 3 的发布检查也会拦。
3. **应用降级或旧版应用**遇到新格式、新字段：格式版本不对直接不采用；不认识的包按 `minAppVersion` 跳过——任务 1、4 有测试。
4. **导入的文件来自装过新方案的电脑**，而 GitHub 连不上：报清楚「不认识的方案」和检查失败的原因，不写任何东西——任务 5 有测试（`更新了还是不认识`、`清单已是最新`）；连不上的情况走同一条路径（`check` 返回 `.rejected`）。
5. **release 编译里不能有测试后门**（环境变量换地址、多认公钥）——任务 10 用 `strings` 检查 release 版 rimectl。

---

## 文件结构

| 文件 | 做什么 | 任务 |
|---|---|---|
| `Sources/RimeKit/Catalog/Catalog.swift` | 加 `serial`、`deprecated`、`minAppVersion`；`available(for:)`；`PackageSpec.sameRules(as:)` | 1、3 |
| `Sources/RimeKit/Catalog/AppVersion.swift`（新） | 点分版本号 | 1 |
| `Sources/RimeKit/AppInfo.swift` | `AppInfo.version` | 1 |
| `Sources/RimeKit/Resources/catalog.json` | 加 `"serial": 2026101501` | 1 |
| `Sources/RimeKit/Catalog/CatalogError.swift` | `badMinAppVersion` | 1 |
| `Sources/RimeKit/Catalog/CatalogSignature.swift`（新） | 公钥、签名、验证、生成密钥 | 2、11 |
| `Sources/RimeKit/Catalog/CatalogDiff.swift`（新） | 两份清单变了什么 | 3 |
| `Sources/RimeKit/Catalog/CatalogPublishCheck.swift`（新） | 发布前检查：serial 变大、id 不能删 | 3 |
| `Sources/RimeKit/Catalog/CatalogStore.swift`（新） | 生效清单、缓存、检查更新、导入时自动检查 | 4、5 |
| `Sources/RimeKit/AppPaths.swift` | `catalogCache` | 4 |
| `Sources/RimeKit/Transfer/ExportManifest.swift`、`ImportArchive.swift` | `TransferError.unknownToCatalog` | 5 |
| `Sources/RimeKit/Catalog/CatalogHint.swift`（新）、`Packages/PackageStore.swift`、`Packages/SourceResolver.swift`、`Sources/AppCore/AppWording.swift` | 出错提示的新说法 | 6 |
| `Sources/rimectl/Rimectl.swift` | 用 `CatalogStore`；`catalog` 子命令；导入时自动检查 | 7 |
| `Sources/AppCore/CatalogHolder.swift`（新）、`NetworkUse.swift`（新）、`AppEnvironment.swift`、`MainModel.swift`、`MainModel+Actions.swift`、`SetupFlow.swift` | 应用逻辑 | 8 |
| `Sources/AppUI/SchemasPage.swift`、`DiagnosticsPage.swift`、`MainView.swift` | 界面 | 9 |
| `tools/catalog/keygen.sh`、`tools/catalog/publish.sh`（新）、`docs/release.md`、`Tests/RimeKitTests/OnlineTests.swift` | 发布工具、文档、联网测试 | 10 |
| `catalog/v1/catalog.json`、`catalog/v1/catalog.json.sig`（新，由脚本生成） | 发布出去的清单 | 11 |
| `README.md`、`CLAUDE.md`、路线图、`docs/verified-facts.md` | 收尾文档 | 12 |
| 测试：`Tests/RimeKitTests/Support/TestCatalogs.swift`（新）和各任务的新测试文件；`Support/AppFakes.swift`、`ImportArchiveTests.swift`、`BuiltInCatalogTests.swift` | 各任务 |

---

### Task 1: 清单格式加字段、版本号比较

**Files:**
- Create: `Sources/RimeKit/Catalog/AppVersion.swift`
- Modify: `Sources/RimeKit/Catalog/Catalog.swift`、`Sources/RimeKit/Catalog/CatalogError.swift`、`Sources/RimeKit/AppInfo.swift`、`Sources/RimeKit/Resources/catalog.json`
- Create: `Tests/RimeKitTests/Support/TestCatalogs.swift`、`Tests/RimeKitTests/CatalogFormatTests.swift`、`Tests/RimeKitTests/AppInfoTests.swift`
- Modify: `Tests/RimeKitTests/BuiltInCatalogTests.swift`

**Interfaces:**
- Produces:
  - `Catalog.serial: Int`；`Catalog.init(formatVersion: Int = Catalog.supportedFormatVersion, serial: Int, packages: [PackageSpec])`
  - `PackageSpec.deprecated: Bool`、`PackageSpec.minAppVersion: String?`
  - `Catalog.available(for: AppVersion) -> Catalog`
  - `struct AppVersion: Comparable { init?(_ text: String); static var current: AppVersion }`
  - `AppInfo.version: String`
  - `CatalogError.badMinAppVersion(package: String, value: String)`
  - 测试用：`TestCatalogs.json(serial:_:) -> Data`、`TestCatalogs.app(_:)`、`TestCatalogs.base(_:)`、`TestCatalogs.extraPackage`

- [ ] **Step 1: 写测试用的清单小工具**

`Tests/RimeKitTests/Support/TestCatalogs.swift`：

```swift
import Foundation
@testable import RimeKit

/// 在线方案清单测试用：在 Fixtures 的清单（base、app）上加 serial、改字段、签名、放到假网络上
enum TestCatalogs {
    /// Fixtures 的清单加上 serial，再做几处替换（每段要替换的文字必须正好出现一次）
    static func json(serial: Int, _ edits: [(String, String)] = []) -> Data {
        var text = Fixtures.catalogJSON.replacingOccurrences(
            of: #""formatVersion":1,"#, with: #""formatVersion":1,"serial":\#(serial),"#)
        for (old, new) in edits {
            precondition(text.components(separatedBy: old).count == 2, "要替换的文字必须正好出现一次：\(old)")
            text = text.replacingOccurrences(of: old, with: new)
        }
        return Data(text.utf8)
    }

    /// 给 app 包加字段，例如 app(#""deprecated":true"#)
    static func app(_ fields: String) -> (String, String) {
        (#""source":{"type":"githubBranch""#, fields + #","source":{"type":"githubBranch""#)
    }

    /// 给 base 包加字段
    static func base(_ fields: String) -> (String, String) {
        (#""source":{"type":"githubReleaseAsset""#, fields + #","source":{"type":"githubReleaseAsset""#)
    }

    /// 再加一个没有依赖的包 extra（方案 extra「新方案」）。source 的键故意换了顺序，不和 app()/base() 的替换冲突
    static let extraPackage = (#""dependencies":["base"]}"#, #"""
    "dependencies":["base"]},
     {"id":"extra","name":"新方案包","summary":"s","license":"MIT","homepage":"https://example.com/extra",
      "source":{"repo":"o/extra","type":"githubBranch","branch":"main"},
      "anchor":"extra.schema.yaml","include":["*.schema.yaml"],"exclude":[],
      "requiredFiles":["extra.schema.yaml"],
      "schemas":[{"id":"extra","name":"新方案","category":"other"}],"dependencies":[]}
    """#)
}
```

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/CatalogFormatTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogFormatTests {
    typealias C = TestCatalogs

    @Test func 旧清单没写的字段有默认值() throws {
        let c = try Fixtures.catalog()
        #expect(c.serial == 0)
        #expect(c.packages.allSatisfy { !$0.deprecated && $0.minAppVersion == nil })
    }

    @Test func 读出serial_下架_最低版本() throws {
        let c = try Catalog.decode(C.json(serial: 7, [C.app(#""deprecated":true,"minAppVersion":"0.3.0""#)]))
        #expect(c.serial == 7)
        #expect(c.package("app")?.deprecated == true)
        #expect(c.package("app")?.minAppVersion == "0.3.0")
        #expect(c.package("base")?.deprecated == false)
    }

    @Test func 最低版本写错了校验不过() {
        #expect(throws: CatalogError.badMinAppVersion(package: "app", value: "v1")) {
            try Catalog.decode(C.json(serial: 1, [C.app(#""minAppVersion":"v1""#)]))
        }
    }

    @Test func 版本号比较() throws {
        func v(_ s: String) throws -> AppVersion { try #require(AppVersion(s)) }
        #expect(try v("0.10.0") > v("0.9.0"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("0.3.0-rc1") == v("0.3.0"))
        #expect(try v("0.2.0") < v("0.3"))
        #expect(AppVersion("") == nil)
        #expect(AppVersion("v1") == nil)
        #expect(AppVersion("1..0") == nil)
        #expect(AppVersion("+1.0") == nil)
    }

    @Test func 用不了的包和依赖它的包都去掉() throws {
        let c = try Catalog.decode(C.json(serial: 1, [C.base(#""minAppVersion":"9.0.0""#)]))
        let old = c.available(for: try #require(AppVersion("0.2.0")))
        #expect(old.packages.isEmpty)   // app 依赖 base，也去掉
        #expect(old.serial == 1)
        let new = c.available(for: try #require(AppVersion("9.0.0")))
        #expect(new.packages.map(\.id) == ["base", "app"])
    }

    @Test func 只去掉要求新版本的那个包() throws {
        let c = try Catalog.decode(C.json(serial: 1, [C.app(#""minAppVersion":"9.0.0""#)]))
        let available = c.available(for: try #require(AppVersion("0.2.0")))
        #expect(available.packages.map(\.id) == ["base"])
        try available.validate()
    }

    @Test func 选项里依赖的包被去掉时整个包也去掉() throws {
        let text = GenFixtures.catalogJSON.replacingOccurrences(
            of: #"{"id":"words","name":"词库""#, with: #"{"id":"words","minAppVersion":"9.0.0","name":"词库""#)
        let c = try Catalog.decode(Data(text.utf8))
        let ids = c.available(for: try #require(AppVersion("0.2.0"))).packages.map(\.id)
        #expect(ids == ["pinyin"])   // wubi 的「大词库」选项依赖 words
    }
}
```

`Tests/RimeKitTests/AppInfoTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct AppInfoTests {
    @Test func 版本号和Info_plist一致() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "tools/app/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        #expect(plist?["CFBundleShortVersionString"] as? String == AppInfo.version)
        #expect(AppVersion(AppInfo.version) != nil)
    }
}
```

`Tests/RimeKitTests/BuiltInCatalogTests.swift` 末尾（`}` 之前）加：

```swift
    @Test func 内置清单有serial() throws {
        #expect(try Catalog.builtIn().serial > 0)
    }

    @Test func 起步方案用的都在内置清单里而且没下架() throws {
        let catalog = try Catalog.builtIn()
        for starter in Starter.allCases {
            let settings = Settings.starter(starter)
            try settings.validate(catalog)
            for spec in try settings.requiredPackages(catalog) {
                #expect(!spec.deprecated, "\(starter) 用到了下架的 \(spec.id)")
            }
        }
    }
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `swift test --filter 'CatalogFormatTests|AppInfoTests|BuiltInCatalogTests'`
Expected: 编译失败（`serial`、`deprecated`、`AppVersion`、`AppInfo.version` 都还没有）

- [ ] **Step 4: 实现**

`Sources/RimeKit/Catalog/AppVersion.swift`：

```swift
import Foundation

/// 点分数字的版本号，例如 0.10.0。带 -rc1 这类后缀时只看前面的数字；缺的段当 0（1.0 == 1.0.0）
public struct AppVersion: Sendable, Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let core = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let pieces = core.split(separator: ".", omittingEmptySubsequences: false)
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(piece) else { return nil }
            parts.append(n)
        }
        guard !parts.isEmpty else { return nil }
        self.parts = parts
    }

    /// 这个应用的版本（AppInfo.version 有测试保证能解析）
    public static var current: AppVersion { AppVersion(AppInfo.version)! }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        compare(a, b) < 0
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        compare(a, b) == 0
    }

    private static func compare(_ a: AppVersion, _ b: AppVersion) -> Int {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0
            let y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}
```

`Sources/RimeKit/AppInfo.swift` 改成：

```swift
/// 应用的名字。只用在给人看的地方（界面、文件头、提示）；
/// 内部标识（bundle ID、数据目录 squirrel-macos、rimectl）不跟着改，免得已有数据对不上
public enum AppInfo {
    public static let name = "鼠须管助手"
    /// 和 tools/app/Info.plist 的 CFBundleShortVersionString 一致（有测试检查）。在线方案清单的 minAppVersion 和它比
    public static let version = "0.2.0"
}
```

`Sources/RimeKit/Catalog/CatalogError.swift`：加一个 case 和它的说明。

```swift
    case badMinAppVersion(package: String, value: String)
```

```swift
        case let .badMinAppVersion(package, value):
            return "包 \(package) 的 minAppVersion 写成了 \(value)，要写成 0.3.0 这样的版本号"
```

`Sources/RimeKit/Catalog/Catalog.swift`：

1. `Catalog` 的字段和解码改成：

```swift
public struct Catalog: Sendable, Equatable, Codable {
    public static let supportedFormatVersion = 1

    public let formatVersion: Int
    /// 发布序号：在线清单只接受比手头那份更大的（防回滚，在线方案清单设计 3.1）。没写的当成 0
    public let serial: Int
    public let packages: [PackageSpec]

    public init(formatVersion: Int = Catalog.supportedFormatVersion, serial: Int, packages: [PackageSpec]) {
        self.formatVersion = formatVersion
        self.serial = serial
        self.packages = packages
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, serial, packages }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        serial = try c.decodeIfPresent(Int.self, forKey: .serial) ?? 0
        packages = try c.decode([PackageSpec].self, forKey: .packages)
    }
```

（`package(_:)`、`packageOwning(schema:)`、`decode`、`builtIn` 不变。）

2. `validate()` 里，在 `try checkCycles()` 前面加：

```swift
        for p in packages {
            if let v = p.minAppVersion, AppVersion(v) == nil {
                throw CatalogError.badMinAppVersion(package: p.id, value: v)
            }
        }
```

3. 在 `installOrder(for:)` 前面加：

```swift
    /// 去掉这个版本的应用用不了的包（minAppVersion 更高），以及因此缺了依赖（包括选项里的依赖）的包（设计 3.4、4.1）
    public func available(for appVersion: AppVersion) -> Catalog {
        var kept = packages.filter { p in
            guard let text = p.minAppVersion, let needed = AppVersion(text) else { return true }
            return needed <= appVersion
        }
        while true {
            let ids = Set(kept.map(\.id))
            let next = kept.filter { p in
                p.dependencies.allSatisfy(ids.contains)
                    && p.options.allSatisfy { $0.choices.allSatisfy { $0.dependencies.allSatisfy(ids.contains) } }
            }
            if next.count == kept.count { break }
            kept = next
        }
        return Catalog(formatVersion: formatVersion, serial: serial, packages: kept)
    }
```

4. `PackageSpec`：在 `userDicts` 后面加两个字段，`CodingKeys` 和 `init(from:)` 跟着改：

```swift
    /// 下架了：已经在用的照常能用，「可以启用的方案」里不再列出（设计 3.2）；JSON 里可以不写
    public let deprecated: Bool
    /// 要求的最低应用版本（例如 "0.3.0"）；比当前版本高的包当它不存在（设计 3.4）。JSON 里可以不写
    public let minAppVersion: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, license, homepage, source, anchor, include, exclude, requiredFiles, schemas, dependencies, options, userDicts,
             deprecated, minAppVersion
    }
```

`init(from:)` 末尾加：

```swift
        deprecated = try c.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
        minAppVersion = try c.decodeIfPresent(String.self, forKey: .minAppVersion)
```

`Sources/RimeKit/Resources/catalog.json` 第 2 行改成：

```json
  "formatVersion": 1,
  "serial": 2026101501,
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过

- [ ] **Step 6: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat(catalog): 清单加 serial、deprecated、minAppVersion；版本号比较

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 清单签名

**Files:**
- Create: `Sources/RimeKit/Catalog/CatalogSignature.swift`、`Tests/RimeKitTests/CatalogSignatureTests.swift`

**Interfaces:**
- Produces:
  - `CatalogSignature.trustedKeys: [Data]`（正式公钥；debug 编译多认 `RIMEKIT_CATALOG_TEST_PUBKEY`）
  - `CatalogSignature.verify(_ data: Data, signature: Data, keys: [Data]) -> Bool`
  - `CatalogSignature.sign(_ data: Data, privateKey: Data) throws -> Data`（返回签名文件内容：base64 加换行）
  - `CatalogSignature.generateKeyPair() -> (privateKey: String, publicKey: String)`（base64）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/CatalogSignatureTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogSignatureTests {
    let pair = CatalogSignature.generateKeyPair()
    var publicKey: Data { Data(base64Encoded: pair.publicKey)! }
    var privateKey: Data { Data(base64Encoded: pair.privateKey)! }
    let data = Data(#"{"formatVersion":1,"serial":1,"packages":[]}"#.utf8)

    @Test func 签名对的能通过() throws {
        let sig = try CatalogSignature.sign(data, privateKey: privateKey)
        #expect(CatalogSignature.verify(data, signature: sig, keys: [publicKey]))
    }

    @Test func 内容改了一个字节就不通过() throws {
        let sig = try CatalogSignature.sign(data, privateKey: privateKey)
        var changed = data
        changed[changed.count - 2] ^= 1
        #expect(!CatalogSignature.verify(changed, signature: sig, keys: [publicKey]))
    }

    @Test func 签名乱码或空的不通过() {
        #expect(!CatalogSignature.verify(data, signature: Data("不是签名".utf8), keys: [publicKey]))
        #expect(!CatalogSignature.verify(data, signature: Data(), keys: [publicKey]))
    }

    @Test func 别的密钥签的不通过_认了那把公钥才通过() throws {
        let other = CatalogSignature.generateKeyPair()
        let sig = try CatalogSignature.sign(data, privateKey: Data(base64Encoded: other.privateKey)!)
        #expect(!CatalogSignature.verify(data, signature: sig, keys: [publicKey]))
        #expect(CatalogSignature.verify(data, signature: sig, keys: [publicKey, Data(base64Encoded: other.publicKey)!]))
    }

    @Test func 没有公钥时什么都不通过() throws {
        let sig = try CatalogSignature.sign(data, privateKey: privateKey)
        #expect(!CatalogSignature.verify(data, signature: sig, keys: []))
    }

    @Test func 签名文件是一行base64() throws {
        let text = String(decoding: try CatalogSignature.sign(data, privateKey: privateKey), as: UTF8.self)
        #expect(text.hasSuffix("\n"))
        #expect(Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))?.count == 64)
    }

    @Test func 私钥不对时报错() {
        #expect(throws: (any Error).self) { try CatalogSignature.sign(data, privateKey: Data("短".utf8)) }
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter CatalogSignatureTests`
Expected: 编译失败（没有 `CatalogSignature`）

- [ ] **Step 3: 实现**

`Sources/RimeKit/Catalog/CatalogSignature.swift`：

```swift
import CryptoKit
import Foundation

/// 在线方案清单的签名（在线方案清单设计 5.1、5.2）：Ed25519，签的是清单文件的原始字节；签名文件是一行 base64
public enum CatalogSignature {
    /// 正式公钥（base64，32 字节）。私钥在宿主机登录钥匙串里，用 tools/catalog/keygen.sh 生成。
    /// 空的时候任何在线清单都验不过，应用只用内置清单
    static let publicKeys: [String] = []

    /// 认哪些公钥。debug 编译时多认环境变量 RIMEKIT_CATALOG_TEST_PUBKEY 里的测试公钥（测试机实测用）；release 编译没有这段
    public static var trustedKeys: [Data] {
        var keys = publicKeys.compactMap { Data(base64Encoded: $0) }
        #if DEBUG
        if let extra = ProcessInfo.processInfo.environment["RIMEKIT_CATALOG_TEST_PUBKEY"], let key = Data(base64Encoded: extra) {
            keys.append(key)
        }
        #endif
        return keys
    }

    /// signature 是签名文件的内容（base64 文本，前后可以有空白）
    public static func verify(_ data: Data, signature: Data, keys: [Data]) -> Bool {
        let text = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: text) else { return false }
        return keys.contains { key in
            guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else { return false }
            return publicKey.isValidSignature(raw, for: data)
        }
    }

    /// 返回签名文件的内容
    public static func sign(_ data: Data, privateKey: Data) throws -> Data {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        return Data((try key.signature(for: data).base64EncodedString() + "\n").utf8)
    }

    /// 生成一对密钥（base64）：私钥存进钥匙串，公钥写进 publicKeys
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Catalog/CatalogSignature.swift Tests/RimeKitTests/CatalogSignatureTests.swift
git commit -m "feat(catalog): 在线清单的 Ed25519 签名和验证

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 比较两份清单（变化摘要、发布前检查）

**Files:**
- Create: `Sources/RimeKit/Catalog/CatalogDiff.swift`、`Sources/RimeKit/Catalog/CatalogPublishCheck.swift`
- Modify: `Sources/RimeKit/Catalog/Catalog.swift`（`PackageSpec.sameRules(as:)`）
- Create: `Tests/RimeKitTests/CatalogDiffTests.swift`、`Tests/RimeKitTests/CatalogPublishCheckTests.swift`

**Interfaces:**
- Consumes: `Catalog.serial`、`PackageSpec.deprecated`（任务 1）；`TestCatalogs.json/app/extraPackage`（任务 1）
- Produces:
  - `struct CatalogDiff: Equatable { init(old: Catalog, new: Catalog, inUse: Set<String>); addedSchemas: [SchemaSpec]; changedInUse: [String]; newlyDeprecated: [String]; affectsInUse: Bool; lines: [String] }`（`inUse` 是正在用的包 id；`changedInUse`、`newlyDeprecated` 是包的名字）
  - `CatalogPublishCheck.problems(old: Catalog?, new: Catalog) -> [String]`
  - `PackageSpec.sameRules(as: PackageSpec) -> Bool`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/CatalogDiffTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogDiffTests {
    typealias C = TestCatalogs
    let addLua = (#""include":["*.schema.yaml","dicts/**"]"#, #""include":["*.schema.yaml","dicts/**","lua/**"]"#)

    func catalog(_ serial: Int, _ edits: [(String, String)] = []) throws -> Catalog {
        try Catalog.decode(C.json(serial: serial, edits))
    }

    @Test func 新增方案() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [C.extraPackage]), inUse: ["base"])
        #expect(diff.addedSchemas.map(\.id) == ["extra"])
        #expect(!diff.affectsInUse)
        #expect(diff.lines == ["新增方案：新方案"])
    }

    @Test func 在用的包规则变了() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [addLua]), inUse: ["base", "app"])
        #expect(diff.changedInUse == ["基础"])
        #expect(diff.affectsInUse)
        #expect(diff.lines == ["你在用的这些方案包的安装规则变了：基础。应用改动后生效"])
    }

    @Test func 没在用的包规则变了不算() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [addLua]), inUse: ["app"])
        #expect(!diff.affectsInUse)
    }

    @Test func 只改了说明文字不算规则变了() throws {
        let new = try catalog(2, [(#""name":"基础","summary":"s""#, #""name":"基础","summary":"新的说明""#)])
        let diff = CatalogDiff(old: try catalog(1), new: new, inUse: ["base"])
        #expect(!diff.affectsInUse)
        #expect(diff.lines == ["方案没有变化（只更新了说明文字等）"])
    }

    @Test func 新标下架() throws {
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [C.app(#""deprecated":true"#)]), inUse: ["app", "base"])
        #expect(diff.newlyDeprecated == ["应用"])
        #expect(!diff.affectsInUse)   // 下架不算规则变了
        #expect(diff.lines == ["这些方案包下架了（已经在用的照常能用）：应用"])
    }

    @Test func 下架包里的方案不算新增() throws {
        let extraDeprecated = (C.extraPackage.0, C.extraPackage.1.replacingOccurrences(
            of: #"{"id":"extra","name":"新方案包""#, with: #"{"id":"extra","deprecated":true,"name":"新方案包""#))
        let diff = CatalogDiff(old: try catalog(1), new: try catalog(2, [extraDeprecated]), inUse: [])
        #expect(diff.addedSchemas.isEmpty)
    }
}
```

`Tests/RimeKitTests/CatalogPublishCheckTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogPublishCheckTests {
    typealias C = TestCatalogs

    func catalog(_ serial: Int, _ edits: [(String, String)] = []) throws -> Catalog {
        try Catalog.decode(C.json(serial: serial, edits))
    }

    @Test func 第一次发布只要有serial() throws {
        #expect(CatalogPublishCheck.problems(old: nil, new: try catalog(1)).isEmpty)
        #expect(CatalogPublishCheck.problems(old: nil, new: try catalog(0)) == ["清单要写 serial（正整数，例如 2026101501）"])
    }

    @Test func serial要变大() throws {
        #expect(CatalogPublishCheck.problems(old: try catalog(5), new: try catalog(5)) == ["serial 要比上次发布的 5 大"])
        #expect(CatalogPublishCheck.problems(old: try catalog(5), new: try catalog(6)).isEmpty)
    }

    @Test func 加包没问题_删包不行() throws {
        #expect(CatalogPublishCheck.problems(old: try catalog(1), new: try catalog(2, [C.extraPackage])).isEmpty)
        let problems = CatalogPublishCheck.problems(old: try catalog(1, [C.extraPackage]), new: try catalog(2))
        #expect(problems == ["包 extra 不见了：已经发布的包不能删，要下架请标 deprecated",
                             "方案 extra 不见了：已经发布的方案不能删、不能改 id"])
    }

    @Test func 方案改id不行() throws {
        let renamed = try catalog(2, [(#"{"id":"app","name":"应用","category":"wubi"}"#, #"{"id":"app2","name":"应用","category":"wubi"}"#)])
        #expect(CatalogPublishCheck.problems(old: try catalog(1), new: renamed) == ["方案 app 不见了：已经发布的方案不能删、不能改 id"])
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter 'CatalogDiffTests|CatalogPublishCheckTests'`
Expected: 编译失败（没有 `CatalogDiff`、`CatalogPublishCheck`）

- [ ] **Step 3: 实现**

`Sources/RimeKit/Catalog/Catalog.swift`，`PackageSpec` 里（`init(from:)` 后面）加：

```swift
    /// 安装规则一样（名字、说明、许可证、主页、是否下架不算规则）。规则变了，正在用的就要重新应用一次
    public func sameRules(as other: PackageSpec) -> Bool {
        source == other.source && anchor == other.anchor && include == other.include && exclude == other.exclude
            && requiredFiles == other.requiredFiles && schemas == other.schemas && dependencies == other.dependencies
            && options == other.options && userDicts == other.userDicts
    }
```

`Sources/RimeKit/Catalog/CatalogDiff.swift`：

```swift
import Foundation

/// 两份清单比，变了什么（在线方案清单设计 4.2、4.4）：检查更新时告诉用户；正在用的包规则变了要重新应用
public struct CatalogDiff: Sendable, Equatable {
    /// 新增的方案（下架的包里的不算）
    public let addedSchemas: [SchemaSpec]
    /// 正在用的包里，安装规则变了的（包名）
    public let changedInUse: [String]
    /// 这次新标成下架的包（包名）
    public let newlyDeprecated: [String]

    /// inUse：正在用的包 id
    public init(old: Catalog, new: Catalog, inUse: Set<String>) {
        let oldSchemas = Set(old.packages.flatMap(\.schemas).map(\.id))
        addedSchemas = new.packages.filter { !$0.deprecated }.flatMap(\.schemas).filter { !oldSchemas.contains($0.id) }
        changedInUse = new.packages.filter { p in
            guard inUse.contains(p.id), let before = old.package(p.id) else { return false }
            return !p.sameRules(as: before)
        }.map(\.name)
        newlyDeprecated = new.packages.filter { $0.deprecated && old.package($0.id)?.deprecated == false }.map(\.name)
    }

    public var affectsInUse: Bool { !changedInUse.isEmpty }

    /// 给人看的说明
    public var lines: [String] {
        var lines: [String] = []
        if !addedSchemas.isEmpty {
            lines.append("新增方案：" + addedSchemas.map(\.name).joined(separator: "、"))
        }
        if !changedInUse.isEmpty {
            lines.append("你在用的这些方案包的安装规则变了：" + changedInUse.joined(separator: "、") + "。应用改动后生效")
        }
        if !newlyDeprecated.isEmpty {
            lines.append("这些方案包下架了（已经在用的照常能用）：" + newlyDeprecated.joined(separator: "、"))
        }
        if lines.isEmpty { lines.append("方案没有变化（只更新了说明文字等）") }
        return lines
    }
}
```

`Sources/RimeKit/Catalog/CatalogPublishCheck.swift`：

```swift
import Foundation

/// 发布在线清单前的检查（在线方案清单设计 3.3、5.1）：serial 要变大；包 id、方案 id 只能加，不能删、不能改
public enum CatalogPublishCheck {
    /// old：上一次发布的清单（第一次发布时为 nil）。返回发现的问题，空的表示可以发布
    public static func problems(old: Catalog?, new: Catalog) -> [String] {
        var problems: [String] = []
        if new.serial <= 0 { problems.append("清单要写 serial（正整数，例如 2026101501）") }
        guard let old else { return problems }
        if new.serial > 0, new.serial <= old.serial { problems.append("serial 要比上次发布的 \(old.serial) 大") }
        let packages = Set(new.packages.map(\.id))
        let schemas = Set(new.packages.flatMap(\.schemas).map(\.id))
        for id in old.packages.map(\.id) where !packages.contains(id) {
            problems.append("包 \(id) 不见了：已经发布的包不能删，要下架请标 deprecated")
        }
        for id in old.packages.flatMap(\.schemas).map(\.id) where !schemas.contains(id) {
            problems.append("方案 \(id) 不见了：已经发布的方案不能删、不能改 id")
        }
        return problems
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Catalog Tests/RimeKitTests
git commit -m "feat(catalog): 比较两份清单：变化摘要、发布前检查

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: CatalogStore：生效清单、缓存、检查更新

**Files:**
- Create: `Sources/RimeKit/Catalog/CatalogStore.swift`、`Tests/RimeKitTests/CatalogStoreTests.swift`
- Modify: `Sources/RimeKit/AppPaths.swift`、`Tests/RimeKitTests/Support/TestCatalogs.swift`

**Interfaces:**
- Consumes: 任务 1–3 的全部；`HTTPClient`、`RetryPolicy`、`withRetry`（`Net/HTTPClient.swift`）；`Settings.validate(_:)`、`Settings.requiredPackages(_:)`
- Produces:
  - `AppPaths.catalogCache: URL`（`<数据目录>/catalog/`）
  - `enum CatalogOrigin: Equatable { case builtIn; case online(Date) }`
  - `struct CatalogStatus: Equatable { catalog: Catalog; origin: CatalogOrigin; cacheProblem: String? }`
  - `enum CatalogCheckResult: Equatable { case upToDate; case updated(CatalogDiff, CatalogStatus); case rejected(String) }`
  - `struct CatalogStore: Sendable`：
    - `init(paths: AppPaths, http: any HTTPClient = URLSessionHTTPClient(), retry: RetryPolicy = .standard, builtIn: @escaping @Sendable () throws -> Catalog = { try Catalog.builtIn() }, keys: [Data] = CatalogSignature.trustedKeys, remote: URL = CatalogStore.defaultRemote, appVersion: AppVersion = .current)`
    - `static var defaultRemote: URL`；`static func signatureURL(_ remote: URL) -> URL`
    - `func effective() throws -> CatalogStatus`
    - `func check(inUse: Settings?) async -> CatalogCheckResult`
  - 测试用：`TestCatalogs.publicKey`、`.remote`、`.sign(_:)`、`.serve(_:_:signature:)`、`.store(_:_:builtIn:appVersion:)`、`.cache(_:_:signature:)`

- [ ] **Step 1: 测试小工具加上签名和假网络**

`Tests/RimeKitTests/Support/TestCatalogs.swift`，在 `enum TestCatalogs {` 里面末尾加：

```swift
    static let keyPair = CatalogSignature.generateKeyPair()
    static var publicKey: Data { Data(base64Encoded: keyPair.publicKey)! }
    static var privateKey: Data { Data(base64Encoded: keyPair.privateKey)! }
    static let remote = URL(string: "https://example.com/catalog/v1/catalog.json")!

    static func sign(_ data: Data) -> Data {
        try! CatalogSignature.sign(data, privateKey: privateKey)
    }

    /// 假网络上放好在线清单和签名（signature 不给就用正确的）
    static func serve(_ http: FakeHTTPClient, _ data: Data, signature: Data? = nil) {
        http.stub(remote, .success(data))
        http.stub(CatalogStore.signatureURL(remote), .success(signature ?? sign(data)))
    }

    /// 内置清单默认是 serial 10 的 Fixtures 清单
    static func store(_ paths: AppPaths, _ http: FakeHTTPClient = FakeHTTPClient(),
                      builtIn: Data = json(serial: 10), appVersion: String = "0.2.0") -> CatalogStore {
        CatalogStore(paths: paths, http: http, retry: .immediate, builtIn: { try Catalog.decode(builtIn) },
                     keys: [publicKey], remote: remote, appVersion: AppVersion(appVersion)!)
    }

    /// 直接往缓存里放一份清单（模拟上次拉到的）
    static func cache(_ paths: AppPaths, _ data: Data, signature: Data? = nil) throws {
        try FileManager.default.createDirectory(at: paths.catalogCache, withIntermediateDirectories: true)
        try data.write(to: paths.catalogCache.appending(path: "catalog.json"))
        try (signature ?? sign(data)).write(to: paths.catalogCache.appending(path: "catalog.json.sig"))
    }
```

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/CatalogStoreTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogStoreTests {
    typealias C = TestCatalogs

    func cacheExists(_ paths: AppPaths) -> Bool {
        FileManager.default.fileExists(atPath: paths.catalogCache.appending(path: "catalog.json").path)
    }

    // MARK: 生效的清单

    @Test func 没有缓存时用内置的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let status = try C.store(Fixtures.paths(dir)).effective()
        #expect(status.origin == .builtIn)
        #expect(status.catalog.serial == 10)
        #expect(status.cacheProblem == nil)
    }

    @Test func 缓存更新就用缓存() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11, [C.extraPackage]))
        let status = try C.store(paths).effective()
        guard case .online = status.origin else { Issue.record("应该用缓存：\(status.origin)"); return }
        #expect(status.catalog.serial == 11)
        #expect(status.catalog.package("extra") != nil)
    }

    @Test(arguments: [10, 9])
    func 缓存不比内置的新就用内置的(serial: Int) throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: serial))
        let status = try C.store(paths).effective()
        #expect(status.origin == .builtIn)
        #expect(status.cacheProblem == nil)
    }

    @Test func 缓存签名不对时用内置的并说明原因() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11), signature: C.sign(Data("别的内容".utf8)))
        let status = try C.store(paths).effective()
        #expect(status.origin == .builtIn)
        #expect(status.cacheProblem == "缓存的方案清单签名不对")
    }

    @Test func 缓存只剩一个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11))
        try FileManager.default.removeItem(at: paths.catalogCache.appending(path: "catalog.json.sig"))
        let status = try C.store(paths).effective()
        #expect(status.origin == .builtIn)
        #expect(status.cacheProblem == "缓存的方案清单不完整")
    }

    @Test func 当前应用用不了的包不出现() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let builtIn = C.json(serial: 10, [C.app(#""minAppVersion":"9.0.0""#)])
        let status = try C.store(Fixtures.paths(dir), builtIn: builtIn).effective()
        #expect(status.catalog.packages.map(\.id) == ["base"])
    }

    // MARK: 检查更新

    @Test func 有更新就采用并写进缓存() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let store = C.store(paths, http)
        let result = await store.check(inUse: Settings(schemas: ["base"]))
        guard case .updated(let diff, let status) = result else { Issue.record("\(result)"); return }
        #expect(diff.addedSchemas.map(\.id) == ["extra"])
        #expect(status.catalog.serial == 11)
        guard case .online = status.origin else { Issue.record("\(status.origin)"); return }
        #expect(try store.effective().catalog.serial == 11)
    }

    @Test func 不比手头的新就不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 10))
        #expect(await C.store(paths, http).check(inUse: nil) == .upToDate)
        #expect(!cacheExists(paths))
    }

    @Test func 签名不对不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11), signature: C.sign(Data("别的内容".utf8)))
        #expect(await C.store(paths, http).check(inUse: nil) == .rejected("方案清单的签名不对，没有采用"))
        #expect(!cacheExists(paths))
    }

    @Test func 连不上() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let result = await C.store(Fixtures.paths(dir), FakeHTTPClient()).check(inUse: nil)
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.hasPrefix("没拉到方案清单："))
    }

    @Test func 格式不对() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, Data("{}".utf8))
        let result = await C.store(Fixtures.paths(dir), http).check(inUse: nil)
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.hasPrefix("方案清单读不了："))
    }

    @Test func 格式版本太新不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        let newer = String(decoding: C.json(serial: 11), as: UTF8.self)
            .replacingOccurrences(of: #""formatVersion":1"#, with: #""formatVersion":2"#)
        C.serve(http, Data(newer.utf8))
        let result = await C.store(paths, http).check(inUse: nil)
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.contains("请更新应用"))
        #expect(!cacheExists(paths))
    }

    @Test func 和正在用的设置对不上就不采用() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.app(#""minAppVersion":"9.0.0""#)]))
        let store = C.store(paths, http)
        let result = await store.check(inUse: Settings(schemas: ["app"]))
        guard case .rejected(let reason) = result else { Issue.record("\(result)"); return }
        #expect(reason.contains("和你现在的设置对不上"))
        #expect(!cacheExists(paths))
        #expect(try store.effective().catalog.serial == 10)
    }

    @Test func 旧缓存被替换() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try C.cache(paths, C.json(serial: 11))
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 12))
        let store = C.store(paths, http)
        guard case .updated = await store.check(inUse: nil) else { Issue.record("应该更新"); return }
        #expect(try store.effective().catalog.serial == 12)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.catalogCache.path).sorted() == ["catalog.json", "catalog.json.sig"])
    }

    @Test func 签名地址在清单旁边() {
        #expect(CatalogStore.signatureURL(C.remote).absoluteString == "https://example.com/catalog/v1/catalog.json.sig")
        #expect(CatalogStore.defaultRemote.absoluteString == "https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json")
    }
}
```

（最后一条在跑测试的环境里设了 `RIMEKIT_CATALOG_URL` 时会失败，那是对的：跑单元测试时不要设它。）

- [ ] **Step 3: 跑测试，确认失败**

Run: `swift test --filter CatalogStoreTests`
Expected: 编译失败（没有 `CatalogStore`、`catalogCache`）

- [ ] **Step 4: 实现**

`Sources/RimeKit/AppPaths.swift`，在 `packages` 后面加：

```swift
    /// 上次拉到、验过签名的在线方案清单（catalog.json 和 catalog.json.sig）
    public var catalogCache: URL { root.appending(path: "catalog", directoryHint: .isDirectory) }
```

`Sources/RimeKit/Catalog/CatalogStore.swift`：

```swift
import Foundation

/// 现在用的是哪份方案清单
public enum CatalogOrigin: Sendable, Equatable {
    case builtIn
    /// 在线拉到的；日期是下载并采用的时间（缓存文件的修改时间）
    case online(Date)
}

public struct CatalogStatus: Sendable, Equatable {
    /// 生效的清单（已经去掉这个版本的应用用不了的包）
    public let catalog: Catalog
    public let origin: CatalogOrigin
    /// 缓存的在线清单用不了的原因（没有缓存、或缓存正常时为 nil）
    public let cacheProblem: String?

    public init(catalog: Catalog, origin: CatalogOrigin, cacheProblem: String?) {
        self.catalog = catalog
        self.origin = origin
        self.cacheProblem = cacheProblem
    }
}

public enum CatalogCheckResult: Sendable, Equatable {
    case upToDate
    case updated(CatalogDiff, CatalogStatus)
    /// 没用上，继续用手头那份；原因给人看
    case rejected(String)
}

/// 方案清单：内置的和在线拉到的哪份生效；检查在线更新（在线方案清单设计第 4 节）
public struct CatalogStore: Sendable {
    /// 在线清单的地址（路径里带格式版本）；debug 编译时可以用环境变量 RIMEKIT_CATALOG_URL 换掉（测试机实测用）
    public static var defaultRemote: URL {
        #if DEBUG
        if let text = ProcessInfo.processInfo.environment["RIMEKIT_CATALOG_URL"], let url = URL(string: text) { return url }
        #endif
        return URL(string: "https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v\(Catalog.supportedFormatVersion)/catalog.json")!
    }

    /// 签名文件和清单在同一目录：catalog.json.sig
    public static func signatureURL(_ remote: URL) -> URL {
        URL(string: remote.absoluteString + ".sig")!
    }

    public let paths: AppPaths
    let http: any HTTPClient
    let retry: RetryPolicy
    let builtIn: @Sendable () throws -> Catalog
    let keys: [Data]
    let remote: URL
    let appVersion: AppVersion

    public init(
        paths: AppPaths,
        http: any HTTPClient = URLSessionHTTPClient(),
        retry: RetryPolicy = .standard,
        builtIn: @escaping @Sendable () throws -> Catalog = { try Catalog.builtIn() },
        keys: [Data] = CatalogSignature.trustedKeys,
        remote: URL = CatalogStore.defaultRemote,
        appVersion: AppVersion = .current
    ) {
        self.paths = paths
        self.http = http
        self.retry = retry
        self.builtIn = builtIn
        self.keys = keys
        self.remote = remote
        self.appVersion = appVersion
    }

    var cacheFile: URL { paths.catalogCache.appending(path: "catalog.json") }
    var signatureFile: URL { paths.catalogCache.appending(path: "catalog.json.sig") }

    /// 生效的清单（设计 4.1）：内置的和缓存的，serial 大的那份（一样大用内置的）。
    /// 缓存每次都重新验签名，用不了就退回内置的并说明原因。只有内置的读不了才抛错
    public func effective() throws -> CatalogStatus {
        let builtIn = try self.builtIn()
        var chosen = builtIn
        var origin = CatalogOrigin.builtIn
        var problem: String?
        switch loadCache() {
        case .none:
            break
        case .broken(let reason):
            problem = reason
        case .ok(let cached, let date):
            if cached.serial > builtIn.serial {
                chosen = cached
                origin = .online(date)
            }
        }
        return CatalogStatus(catalog: chosen.available(for: appVersion), origin: origin, cacheProblem: problem)
    }

    enum Cached {
        case none
        case broken(String)
        case ok(Catalog, Date)
    }

    func loadCache() -> Cached {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheFile.path) || fm.fileExists(atPath: signatureFile.path) else { return .none }
        guard let data = try? Data(contentsOf: cacheFile), let signature = try? Data(contentsOf: signatureFile) else {
            return .broken("缓存的方案清单不完整")
        }
        guard CatalogSignature.verify(data, signature: signature, keys: keys) else {
            return .broken("缓存的方案清单签名不对")
        }
        do {
            let catalog = try Catalog.decode(data)
            let date = (try? fm.attributesOfItem(atPath: cacheFile.path))?[.modificationDate] as? Date ?? .distantPast
            return .ok(catalog, date)
        } catch {
            return .broken("缓存的方案清单读不了：\(error)")
        }
    }

    /// 检查在线更新（设计 4.2、4.3）：拉清单和签名 → 验签名 → 解析校验 → 比 serial →
    /// 和正在用的设置对得上 → 写进缓存。任何一步不行都不写缓存，继续用手头那份
    public func check(inUse settings: Settings?) async -> CatalogCheckResult {
        let http = self.http
        let remote = self.remote
        let signatureURL = Self.signatureURL(remote)
        let data: Data
        let signature: Data
        do {
            data = try await withRetry(retry) { try await http.get(remote) }
            signature = try await withRetry(retry) { try await http.get(signatureURL) }
        } catch {
            return .rejected("没拉到方案清单：\(error)")
        }
        guard CatalogSignature.verify(data, signature: signature, keys: keys) else {
            return .rejected("方案清单的签名不对，没有采用")
        }
        let fetched: Catalog
        do {
            fetched = try Catalog.decode(data)
        } catch {
            return .rejected("方案清单读不了：\(error)")
        }
        let current: CatalogStatus
        do {
            current = try effective()
        } catch {
            return .rejected("内置的方案清单读不了：\(error)")
        }
        guard fetched.serial > current.catalog.serial else { return .upToDate }
        let next = fetched.available(for: appVersion)
        if let settings {
            do {
                try settings.validate(next)
            } catch {
                return .rejected("这份方案清单和你现在的设置对不上（\(error)），请更新应用")
            }
        }
        do {
            try writeCache(data, signature)
        } catch {
            return .rejected("方案清单没能保存：\(error)")
        }
        var inUse = Set<String>()
        if let settings, let used = try? settings.requiredPackages(current.catalog) { inUse = Set(used.map(\.id)) }
        let status = CatalogStatus(catalog: next, origin: .online(Date()), cacheProblem: nil)
        return .updated(CatalogDiff(old: current.catalog, new: next, inUse: inUse), status)
    }

    /// 先在暂存区写好两个文件，再整个换掉缓存目录：不会只写了一半。万一中途出错，缓存没了就退回内置的
    func writeCache(_ data: Data, _ signature: Data) throws {
        let fm = FileManager.default
        let temp = paths.staging.appending(path: "catalog-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }
        try data.write(to: temp.appending(path: "catalog.json"))
        try signature.write(to: temp.appending(path: "catalog.json.sig"))
        if fm.fileExists(atPath: paths.catalogCache.path) {
            _ = try fm.replaceItemAt(paths.catalogCache, withItemAt: temp)
        } else {
            try fm.createDirectory(at: paths.root, withIntermediateDirectories: true)
            try fm.moveItem(at: temp, to: paths.catalogCache)
        }
    }
}
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过

- [ ] **Step 6: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat(catalog): CatalogStore：内置和在线清单选一份生效，检查在线更新

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 导入时遇到不认识的方案，先检查一次在线清单

**Files:**
- Modify: `Sources/RimeKit/Transfer/ExportManifest.swift`（`TransferError`）、`Sources/RimeKit/Transfer/ImportArchive.swift`、`Sources/RimeKit/Catalog/CatalogStore.swift`
- Modify: `Tests/RimeKitTests/ImportArchiveTests.swift`、`Tests/RimeKitTests/Support/TestCatalogs.swift`
- Create: `Tests/RimeKitTests/CatalogImportTests.swift`

**Interfaces:**
- Consumes: `CatalogStore.check(inUse:)`、`CatalogStatus`（任务 4）
- Produces:
  - `TransferError.unknownToCatalog(String)`
  - `CatalogStore.OpenedArchive { archive: ImportArchive; updated: CatalogStatus? }`
  - `CatalogStore.openArchive(_ file: URL, catalog: Catalog, inUse: Settings?, into dir: URL, checking: @escaping @Sendable () async -> Void = {}) async throws -> OpenedArchive`
  - 测试用：`TestCatalogs.exportFile(schemas:in:) -> URL`

- [ ] **Step 1: 测试小工具加一个只有 manifest 的导出文件**

`Tests/RimeKitTests/Support/TestCatalogs.swift`，`enum TestCatalogs {` 里面末尾加：

```swift
    /// 只有 manifest.json 的导出文件，设置里启用了这些方案
    static func exportFile(schemas: [String], in dir: URL) throws -> URL {
        let content = dir.appending(path: "export-content-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        let manifest = ExportManifest(formatVersion: 1, exportedAt: Date(), settings: Settings(schemas: schemas),
                                      packages: [], personalDicts: [], phrases: 0, userDB: [])
        try JSONCoding.encoder.encode(manifest).write(to: content.appending(path: "manifest.json"))
        let file = dir.appending(path: "export-\(UUID().uuidString).zip")
        try Zipper().zip(content, to: file)
        return file
    }
```

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/ImportArchiveTests.swift` 的 `设置里的方案不认识`，把 `catch let TransferError.badSettings(message)` 改成：

```swift
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("nope"))
        }
```

`Tests/RimeKitTests/CatalogImportTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct CatalogImportTests {
    typealias C = TestCatalogs

    actor Counter {
        var count = 0
        func bump() { count += 1 }
    }

    @Test func 认识的方案不联网() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["base"], in: dir.url)
        let opened = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                                 into: dir.url.appending(path: "work"))
        #expect(opened.updated == nil)
        #expect(opened.archive.manifest.settings.schemas == ["base"])
        #expect(http.callCount(C.remote) == 0)
    }

    @Test func 不认识的方案先检查更新再打开() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        let counter = Counter()
        let opened = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                                 into: dir.url.appending(path: "work"), checking: { await counter.bump() })
        #expect(opened.updated?.catalog.serial == 11)
        #expect(opened.archive.manifest.settings.schemas == ["extra"])
        #expect(await counter.count == 1)
        #expect(try store.effective().catalog.package("extra") != nil)
    }

    @Test func 更新了还是不认识() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11))
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        do {
            _ = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                            into: dir.url.appending(path: "work"))
            Issue.record("应该报错")
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("extra"))
        }
    }

    @Test func 清单已经是最新的() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 10))
        let store = C.store(Fixtures.paths(dir), http)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        do {
            _ = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                            into: dir.url.appending(path: "work"))
            Issue.record("应该报错")
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("方案清单已经是最新的"))
        }
    }

    @Test func 连不上时说清楚() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let store = C.store(Fixtures.paths(dir), FakeHTTPClient())
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        do {
            _ = try await store.openArchive(file, catalog: try store.effective().catalog, inUse: nil,
                                            into: dir.url.appending(path: "work"))
            Issue.record("应该报错")
        } catch let TransferError.unknownToCatalog(message) {
            #expect(message.contains("没拉到方案清单"))
            #expect(TransferError.unknownToCatalog(message).description.hasSuffix("请更新应用"))
        }
    }
}
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `swift test --filter 'CatalogImportTests|ImportArchiveTests'`
Expected: 编译失败（没有 `unknownToCatalog`、`openArchive`）

- [ ] **Step 4: 实现**

`Sources/RimeKit/Transfer/ExportManifest.swift`，`TransferError` 加一个 case（放在 `badSettings` 后面）和说明：

```swift
    /// 导出文件里用到了现在的方案清单里没有的方案或选项（导入时会先检查一次在线清单，在线方案清单设计 4.5）
    case unknownToCatalog(String)
```

```swift
        case .unknownToCatalog(let message):
            return "导出文件里用到了这个版本的应用不认识的方案或选项：\(message)。请更新应用"
```

`Sources/RimeKit/Transfer/ImportArchive.swift`，把：

```swift
        do {
            try manifest.settings.validate(catalog)
        } catch {
            throw TransferError.badSettings(String(describing: error))
        }
```

改成：

```swift
        do {
            try manifest.settings.validate(catalog)
        } catch let error as SettingsError {
            switch error {
            case .unknownSchema, .unknownOption, .unknownChoice:
                throw TransferError.unknownToCatalog(String(describing: error))
            default:
                throw TransferError.badSettings(String(describing: error))
            }
        }
```

（`validate` 只抛 `SettingsError`；如果编译器要求穷尽，再加一个 `catch { throw TransferError.badSettings(String(describing: error)) }`。）

`Sources/RimeKit/Catalog/CatalogStore.swift` 末尾加：

```swift
extension CatalogStore {
    public struct OpenedArchive: Sendable {
        public let archive: ImportArchive
        /// 为了认出导出文件里的方案，更新了方案清单（没更新为 nil）
        public let updated: CatalogStatus?
    }

    /// 打开导出文件（设计 4.5）。里面用到了手头清单里没有的方案时，先检查一次在线清单再打开；
    /// checking 在开始检查前调用（界面上显示「正在更新方案清单」）
    public func openArchive(_ file: URL, catalog: Catalog, inUse: Settings?, into dir: URL,
                            checking: @escaping @Sendable () async -> Void = {}) async throws -> OpenedArchive {
        do {
            return OpenedArchive(archive: try ImportArchive.open(file, catalog: catalog, into: dir), updated: nil)
        } catch TransferError.unknownToCatalog(let message) {
            await checking()
            switch await check(inUse: inUse) {
            case .updated(_, let status):
                try? FileManager.default.removeItem(at: dir)   // 重新解压一次
                return OpenedArchive(archive: try ImportArchive.open(file, catalog: status.catalog, into: dir), updated: status)
            case .upToDate:
                throw TransferError.unknownToCatalog(message + "（方案清单已经是最新的）")
            case .rejected(let reason):
                throw TransferError.unknownToCatalog(message + "（检查方案清单更新：\(reason)）")
            }
        }
    }
}
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过

- [ ] **Step 6: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat(catalog): 导入时遇到不认识的方案先检查一次在线清单

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 「上游结构变了」的提示建议先检查清单更新

**Files:**
- Create: `Sources/RimeKit/Catalog/CatalogHint.swift`、`Tests/RimeKitTests/CatalogHintTests.swift`
- Modify: `Sources/RimeKit/Packages/PackageStore.swift:30-32`、`Sources/RimeKit/Packages/SourceResolver.swift:20`、`Sources/AppCore/AppWording.swift`

**Interfaces:**
- Produces: `CatalogHint.tryUpdate: String`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/CatalogHintTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@Suite struct CatalogHintTests {
    @Test(arguments: [
        PackageStoreError.missingRequiredFiles(package: "p", files: ["a"]).description,
        PackageStoreError.anchorNotFound(package: "p", anchor: "a").description,
        SourceError.assetNotFound(repo: "o/r", tag: "t", asset: "a.zip").description,
    ])
    func 上游变了时先建议检查清单更新(text: String) {
        #expect(text.contains("rimectl catalog check"))
        #expect(text.hasSuffix("还不行的话，请更新应用"))
        let app = AppWording.forApp(text)
        #expect(app.contains("可以先到「方案」页点「检查方案清单更新」"))
        #expect(!app.contains("rimectl"))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter CatalogHintTests`
Expected: FAIL（现在的说法是「需要更新应用」，不含 `rimectl catalog check`）

- [ ] **Step 3: 实现**

`Sources/RimeKit/Catalog/CatalogHint.swift`：

```swift
/// 上游方案变了、装不上时的建议（在线方案清单设计 4.7）。应用里由 AppWording 换成界面上的做法
public enum CatalogHint {
    public static let tryUpdate = "可以先运行 rimectl catalog check 检查方案清单更新；还不行的话，请更新应用"
}
```

`Sources/RimeKit/Packages/PackageStore.swift` 的 `description` 改成：

```swift
        case let .anchorNotFound(package, anchor):
            return "\(package) 的下载内容里找不到 \(anchor)，上游方案的目录结构变了。\(CatalogHint.tryUpdate)"
        case let .missingRequiredFiles(package, files):
            return "\(package) 的下载内容里缺少这些文件：\(files.joined(separator: "、"))。上游方案的目录结构变了。\(CatalogHint.tryUpdate)"
```

`Sources/RimeKit/Packages/SourceResolver.swift` 的 `assetNotFound` 改成：

```swift
            return "GitHub 上 \(repo) 的 \(tag) 版本里找不到 \(asset)，上游可能改了发布方式。\(CatalogHint.tryUpdate)"
```

`Sources/AppCore/AppWording.swift` 的 `replacements` 末尾加一项：

```swift
        (#"可以先运行 rimectl catalog check 检查方案清单更新"#, "可以先到「方案」页点「检查方案清单更新」"),
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过（如果有别的测试检查过旧说法「需要更新应用」，照新说法改那条测试的期望）

- [ ] **Step 5: 提交**

```bash
git add Sources Tests/RimeKitTests/CatalogHintTests.swift
git commit -m "feat(catalog): 上游结构变了时先建议检查方案清单更新

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: rimectl 用上在线清单

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`
- Create: `Tests/RimeKitTests/RimectlCatalogTests.swift`

**Interfaces:**
- Consumes: `CatalogStore`（任务 4、5）、`CatalogSignature`（任务 2）、`CatalogPublishCheck`（任务 3）
- Produces:
  - `Rimectl.Context` 新字段：`catalogKeys: [Data] = CatalogSignature.trustedKeys`、`catalogURL: URL = CatalogStore.defaultRemote`、`readStdin: @Sendable () -> Data = { FileHandle.standardInput.readDataToEndOfFile() }`。`Context.catalog` 的意思变成「内置清单」，`run` 里换成生效的清单
  - 命令：`rimectl catalog [show|check]`；隐藏的 `rimectl catalog keygen`、`catalog sign <文件> --out <签名文件>`（私钥从标准输入读）、`catalog verify <文件> <签名文件>`、`catalog verify-source <新清单> [<上次发布的清单>]`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/RimectlCatalogTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlCatalogTests {
    typealias C = TestCatalogs

    func context(_ http: FakeHTTPClient, _ dir: TempDir, stdin: Data = Data()) throws -> (Rimectl.Context, Output) {
        let output = Output(echo: false)
        var ctx = Rimectl.Context(http: http, retry: .immediate, catalog: { try Catalog.decode(C.json(serial: 10)) },
                                  defaultPaths: Fixtures.paths(dir), output: output)
        ctx.catalogKeys = [C.publicKey]
        ctx.catalogURL = C.remote
        ctx.readStdin = { stdin }
        ctx.locations = try DeployFixtures.locations(dir)
        return (ctx, output)
    }

    @Test func show_说明用的是哪份() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = try context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["catalog", "show"], ctx) == 0)
        #expect(out.text.contains("内置方案清单（编号 10）"))
    }

    @Test func check_有更新以后所有命令都用新的() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let (ctx, out) = try context(http, dir)
        #expect(await Rimectl.run(["catalog", "check"], ctx) == 0)
        #expect(out.text.contains("新增方案：新方案"))
        #expect(await Rimectl.run(["catalog"], ctx) == 0)
        #expect(out.text.contains("extra  新方案"))
    }

    @Test func check_签名不对() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11), signature: C.sign(Data("别的".utf8)))
        let (ctx, out) = try context(http, dir)
        #expect(await Rimectl.run(["catalog", "check"], ctx) == 1)
        #expect(out.text.contains("签名不对"))
    }

    @Test func check_已经是最新的() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 10))
        let (ctx, out) = try context(http, dir)
        #expect(await Rimectl.run(["catalog", "check"], ctx) == 0)
        #expect(out.text.contains("方案清单已经是最新的"))
    }

    @Test func 签名和验证() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let file = dir.url.appending(path: "catalog.json")
        let sig = dir.url.appending(path: "catalog.json.sig")
        try C.json(serial: 11).write(to: file)
        let (ctx, _) = try context(FakeHTTPClient(), dir, stdin: Data((C.keyPair.privateKey + "\n").utf8))
        #expect(await Rimectl.run(["catalog", "sign", file.path, "--out", sig.path], ctx) == 0)
        #expect(await Rimectl.run(["catalog", "verify", file.path, sig.path], ctx) == 0)
        try C.json(serial: 12).write(to: file)
        #expect(await Rimectl.run(["catalog", "verify", file.path, sig.path], ctx) == 1)
    }

    @Test func 发布前检查() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let new = dir.url.appending(path: "new.json")
        let old = dir.url.appending(path: "old.json")
        try C.json(serial: 11).write(to: new)
        try C.json(serial: 11).write(to: old)
        let (ctx, out) = try context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["catalog", "verify-source", new.path, old.path], ctx) == 1)
        #expect(out.text.contains("serial 要比上次发布的 11 大"))
        #expect(await Rimectl.run(["catalog", "verify-source", new.path, dir.url.appending(path: "none.json").path], ctx) == 0)
    }

    @Test func 生成密钥() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = try context(FakeHTTPClient(), dir)
        #expect(await Rimectl.run(["catalog", "keygen"], ctx) == 0)
        let lines = out.text.split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("private ") })
        #expect(lines.contains { $0.hasPrefix("public ") })
    }

    @Test func 导入时不认识的方案先检查清单更新() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, C.json(serial: 11, [C.extraPackage]))
        let (ctx, out) = try context(http, dir)
        let file = try C.exportFile(schemas: ["extra"], in: dir.url)
        _ = await Rimectl.run(["import", file.path, "--cache-only"], ctx)   // 本地没有 extra 的缓存，最后会失败
        #expect(out.text.contains("正在检查方案清单更新"))
        #expect(out.text.contains("方案清单更新了"))
        #expect(await Rimectl.run(["catalog", "show"], ctx) == 0)
        #expect(out.text.contains("在线方案清单（编号 11"))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter RimectlCatalogTests`
Expected: 编译失败（`Context` 没有 `catalogKeys` 等字段）

- [ ] **Step 3: 实现**

`Sources/rimectl/Rimectl.swift`：

1. `Context` 里，`catalog` 的注释改成「内置的方案清单（run 里会换成生效的那份）」，并加三个字段：

```swift
        /// 内置的方案清单；run 里会换成生效的那份（内置的或在线拉到的）
        var catalog: @Sendable () throws -> Catalog
        ...
        /// 认哪些在线清单的签名公钥；测试换成测试公钥
        var catalogKeys: [Data] = CatalogSignature.trustedKeys
        /// 在线清单的地址
        var catalogURL: URL = CatalogStore.defaultRemote
        /// catalog sign 从这里读私钥
        var readStdin: @Sendable () -> Data = { FileHandle.standardInput.readDataToEndOfFile() }
```

2. `usage` 里把 `rimectl catalog` 那行换成：

```
      rimectl catalog [show|check]                             列出方案清单 / 看用的是哪份 / 检查在线方案清单更新
```

3. `run` 里，`if let rimeDir { … }` 后面加：

```swift
        let catalogStore = CatalogStore(paths: paths, http: context.http, retry: context.retry,
                                        builtIn: context.catalog, keys: context.catalogKeys, remote: context.catalogURL)
        // 以后各命令取清单都取生效的那份
        var context = context
        context.catalog = { try catalogStore.effective().catalog }
```

4. `switch command` 里，`case "catalog":` 改成：

```swift
            case "catalog":
                return try await catalogCommand(Array(positional.dropFirst()), outFile: outDir, store: catalogStore,
                                                paths: paths, context)
```

`case "import":` 改成把 `catalogStore` 传进去：

```swift
            case "import":
                return try await importCommand(Array(positional.dropFirst()), includeUserDB: !noUserDB, cacheOnly: cacheOnly,
                                               store: catalogStore, paths: paths, locations: locations, context)
```

5. 在 `listCatalog` 后面加：

```swift
    /// 方案清单（在线方案清单设计 4.8、5.1）。keygen、sign、verify、verify-source 是发布用的，不写进 usage
    private static func catalogCommand(_ args: [String], outFile: String?, store: CatalogStore, paths: AppPaths,
                                       _ context: Context) async throws -> Int32 {
        let out = context.output
        switch args.first {
        case nil:
            try listCatalog(try context.catalog(), out)
            return 0
        case "show":
            let status = try store.effective()
            out.line(describe(status))
            out.line("包 \(status.catalog.packages.count) 个")
            if let problem = status.cacheProblem { out.line("缓存的在线方案清单用不了：\(problem)") }
            return 0
        case "check":
            let settings = try SettingsStore(paths: paths).load()
            switch await store.check(inUse: settings) {
            case .upToDate:
                out.line("方案清单已经是最新的")
                return 0
            case .updated(let diff, let status):
                out.line("方案清单更新了（编号 \(status.catalog.serial)）")
                diff.lines.forEach(out.line)
                if diff.affectsInUse { out.line("运行 rimectl apply 让新的安装规则生效") }
                return 0
            case .rejected(let reason):
                out.error("没有用上新的方案清单：\(reason)")
                return 1
            }
        case "keygen":
            let pair = CatalogSignature.generateKeyPair()
            out.line("private \(pair.privateKey)")
            out.line("public \(pair.publicKey)")
            return 0
        case "sign":
            guard args.count == 2, let outFile else { out.error(usage); return 2 }
            let key = String(decoding: context.readStdin(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let privateKey = Data(base64Encoded: key) else { out.error("标准输入里读不到私钥（base64）"); return 1 }
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            try CatalogSignature.sign(data, privateKey: privateKey).write(to: URL(fileURLWithPath: outFile))
            return 0
        case "verify":
            guard args.count == 3 else { out.error(usage); return 2 }
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let signature = try Data(contentsOf: URL(fileURLWithPath: args[2]))
            guard CatalogSignature.verify(data, signature: signature, keys: context.catalogKeys) else {
                out.error("签名不对")
                return 1
            }
            out.line("签名正确")
            return 0
        case "verify-source":
            guard args.count == 2 || args.count == 3 else { out.error(usage); return 2 }
            let new = try Catalog.decode(Data(contentsOf: URL(fileURLWithPath: args[1])))
            var old: Catalog?
            if args.count == 3, FileManager.default.fileExists(atPath: args[2]) {
                old = try Catalog.decode(Data(contentsOf: URL(fileURLWithPath: args[2])))
            }
            let problems = CatalogPublishCheck.problems(old: old, new: new)
            guard problems.isEmpty else {
                problems.forEach(out.error)
                return 1
            }
            out.line("清单可以发布（编号 \(new.serial)，包 \(new.packages.count) 个）")
            return 0
        default:
            out.error(usage)
            return 2
        }
    }

    private static func describe(_ status: CatalogStatus) -> String {
        switch status.origin {
        case .builtIn:
            return "用的是内置方案清单（编号 \(status.catalog.serial)）"
        case .online(let date):
            return "用的是在线方案清单（编号 \(status.catalog.serial)，\(date.formatted(date: .numeric, time: .shortened)) 下载）"
        }
    }
```

（`Catalog.decode` 本身会跑 `validate()`，所以 `verify-source` 不用再单独校验。）

6. `importCommand` 的参数加 `store: CatalogStore`，开头几行：

```swift
        let catalog = try context.catalog()
        let work = paths.staging.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = try ImportArchive.open(URL(fileURLWithPath: args[0]), catalog: catalog, into: work)
```

改成：

```swift
        let work = paths.staging.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let inUse = (try? SettingsStore(paths: paths).load()) ?? nil
        let opened = try await store.openArchive(
            URL(fileURLWithPath: args[0]), catalog: try context.catalog(), inUse: inUse, into: work,
            checking: { out.line("导出文件里有现在的方案清单不认识的方案，正在检查方案清单更新……") })
        if let updated = opened.updated { out.line("方案清单更新了（编号 \(updated.catalog.serial)）") }
        let archive = opened.archive
        let catalog = try context.catalog()   // 可能刚更新过
```

- [ ] **Step 4: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过（`RimectlTests.catalog列出内置的包和方案` 也要通过：没有缓存时生效的就是内置的）

- [ ] **Step 5: 提交**

```bash
git add Sources/rimectl Tests/RimeKitTests/RimectlCatalogTests.swift
git commit -m "feat(rimectl): catalog show/check，导入时自动检查清单；发布用的 keygen/sign/verify/verify-source

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 应用逻辑（AppCore）

**Files:**
- Create: `Sources/AppCore/CatalogHolder.swift`、`Sources/AppCore/NetworkUse.swift`
- Modify: `Sources/AppCore/AppEnvironment.swift`、`Sources/AppCore/MainModel.swift`、`Sources/AppCore/MainModel+Actions.swift`、`Sources/AppCore/SetupFlow.swift`
- Modify: `Tests/RimeKitTests/Support/AppFakes.swift`、`Tests/RimeKitTests/Support/TestCatalogs.swift`
- Create: `Tests/RimeKitTests/MainModelCatalogTests.swift`

**Interfaces:**
- Consumes: `CatalogStore`、`CatalogStatus`、`CatalogCheckResult`、`CatalogDiff`、`openArchive`（任务 4、5）
- Produces:
  - `final class CatalogHolder: Sendable { init(_ status: CatalogStatus); var status: CatalogStatus; func update(_ status: CatalogStatus) }`
  - `AppEnvironment.catalogStore: CatalogStore`、`AppEnvironment.catalogs: CatalogHolder`、`AppEnvironment.catalog: Catalog`（只读，取自 `catalogs`）
  - `MainModel.catalogStatus: CatalogStatus`（可观察）、`MainModel.catalog: Catalog`、`MainModel.catalogNeedsApply: Bool`、`MainModel.hasPendingChanges: Bool`、`MainModel.checkCatalog() async`
  - `NetworkUse.catalogCheckNote`、`NetworkUse.rows: [NetworkUse.Row]`、`NetworkUse.footer`、`NetworkUse.catalogSource(_:) -> String`
  - 测试用：`Machine.environment(…, catalogHTTP:, catalogKeys:)`；`TestCatalogs.online(_:serial:_:)`、`TestCatalogs.addPackage(copying:as:schema:deprecated:)`

- [ ] **Step 1: 测试小工具**

`Tests/RimeKitTests/Support/TestCatalogs.swift`，`enum TestCatalogs {` 里面末尾加：

```swift
    /// 把一份清单换上新的 serial，再在 JSON 上改一改（给 AppCore 测试用：假电脑的清单是 GenFixtures 的）
    static func online(_ catalog: Catalog, serial: Int, _ change: (inout [[String: Any]]) -> Void = { _ in }) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(catalog)) as! [String: Any]
        var packages = object["packages"] as! [[String: Any]]
        change(&packages)
        object["packages"] = packages
        object["serial"] = serial
        return try JSONSerialization.data(withJSONObject: object)
    }

    /// 复制一个包，换 id 和方案（只有一个方案）
    static func addPackage(copying id: String, as newID: String, schema: String, deprecated: Bool = false)
        -> (inout [[String: Any]]) -> Void {
        { packages in
            var copy = packages.first { $0["id"] as? String == id }!
            copy["id"] = newID
            copy["name"] = "复制的\(newID)"
            copy["schemas"] = [["id": schema, "name": "方案\(schema)", "category": "other"]]
            copy["options"] = []
            copy["userDicts"] = []
            copy["deprecated"] = deprecated
            packages.append(copy)
        }
    }

    /// 改某个包的一个字段
    static func set(_ id: String, _ key: String, _ value: Any) -> (inout [[String: Any]]) -> Void {
        { packages in
            let i = packages.firstIndex { $0["id"] as? String == id }!
            packages[i][key] = value
        }
    }
```

`Tests/RimeKitTests/Support/AppFakes.swift` 的 `environment(...)` 加两个参数，并用 `CatalogStore` 和 `CatalogHolder`：

```swift
    func environment(
        input: FakeInputSource = FakeInputSource(InputSourceState(registered: true, enabled: true, selected: true)),
        compiler: FakeCompiler = FakeCompiler(),
        textReplacements: @escaping @Sendable () throws -> TextReplacementSnapshot = {
            TextReplacementSnapshot(usable: [], badShortcut: 0, badPhrase: 0)
        },
        install: @escaping @Sendable () async throws -> InstallOutcome = { .alreadyInstalled("1.1.2") },
        catalogHTTP: FakeHTTPClient = FakeHTTPClient(),
        catalogKeys: [Data] = []
    ) -> AppEnvironment {
        let packages = self.packages
        let catalog = self.catalog
        let catalogStore = CatalogStore(paths: paths, http: catalogHTTP, retry: .immediate, builtIn: { catalog },
                                        keys: catalogKeys, remote: TestCatalogs.remote, appVersion: AppVersion("0.2.0")!)
        return AppEnvironment(
            paths: paths, locations: locations, catalogStore: catalogStore,
            catalogs: CatalogHolder(try! catalogStore.effective()), compiler: compiler, squirrel: squirrel,
            inputSource: input, userDBTool: tool, textReplacements: textReplacements,
            fetchPackage: { spec in
                guard let package = packages[spec.id] else { throw TakeoverError.missingPackage(spec.id) }
                return package
            },
            cachedPackage: { packages[$0.id] },
            installSquirrel: install, deployTimeout: .milliseconds(20), activationTimeout: 5, sleep: { _ in })
    }
```

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/MainModelCatalogTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

/// 假电脑的设置启用了 wb_py（包 wubi）、py（包 pinyin），「大词库」选项用到 words
@MainActor @Suite struct MainModelCatalogTests {
    typealias T = TransferFixtures
    typealias C = TestCatalogs

    func model(_ m: T.Machine, _ http: FakeHTTPClient) throws -> MainModel {
        try MainModel(env: m.environment(catalogHTTP: http, catalogKeys: [C.publicKey]))
    }

    @Test func 已经是最新的() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 0))
        let model = try model(m, http)
        await model.checkCatalog()
        #expect(model.notice?.title == "方案清单已经是最新的")
        #expect(!model.hasPendingChanges)
        #expect(model.working == nil)
    }

    @Test func 在用的包规则变了要重新应用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.set("wubi", "include", ["*", "lua/**"])))
        let model = try model(m, http)
        await model.checkCatalog()
        #expect(model.notice?.title == "方案清单更新了")
        #expect(model.notice?.lines == ["你在用的这些方案包的安装规则变了：测试五笔。应用改动后生效"])
        #expect(model.catalogNeedsApply)
        #expect(model.hasPendingChanges)
        #expect(!model.isDirty)
        #expect(model.catalogStatus.catalog.serial == 5)
        await model.apply()
        #expect(model.notice?.title == "改动已经生效")
        #expect(!model.catalogNeedsApply)
        #expect(!model.hasPendingChanges)
    }

    @Test func 新增方案出现在可以启用的列表里() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let model = try model(m, http)
        await model.checkCatalog()
        #expect(model.catalogPackages.map(\.id).contains("extra"))
        #expect(!model.catalogNeedsApply)
    }

    @Test func 签名不对时不采用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5), signature: C.sign(Data("别的".utf8)))
        let model = try model(m, http)
        await model.checkCatalog()
        #expect(model.notice?.kind == .warning)
        #expect(model.notice?.title == "没有用上新的方案清单")
        #expect(model.notice?.lines == ["方案清单的签名不对，没有采用", "继续用现在的方案清单"])
        #expect(model.catalogStatus.catalog.serial == 0)
    }

    @Test func 下架的包不再列出_在用的除外() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5) { packages in
            C.addPackage(copying: "pinyin", as: "old", schema: "old1", deprecated: true)(&packages)
            C.set("wubi", "deprecated", true)(&packages)
        })
        let model = try model(m, http)
        await model.checkCatalog()
        let ids = model.catalogPackages.map(\.id)
        #expect(!ids.contains("old"))
        #expect(ids.contains("wubi"))
    }

    @Test func 导入时不认识的方案先更新清单() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let env = m.environment(catalogHTTP: http, catalogKeys: [C.publicKey])
        let model = try MainModel(env: env)
        let file = try C.exportFile(schemas: ["extra"], in: m.dir.url)
        await model.importFile(file)   // 假电脑没有 extra 包，最后会失败；但清单已经更新
        #expect(http.callCount(C.remote) == 1)
        #expect(model.catalogStatus.catalog.package("extra") != nil)
        #expect(env.catalog.package("extra") != nil)   // 引导和主窗口共用一份
    }

    @Test func 引导里导入时也会更新清单() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let http = FakeHTTPClient()
        C.serve(http, try C.online(m.catalog, serial: 5, C.addPackage(copying: "pinyin", as: "extra", schema: "extra")))
        let env = m.environment(catalogHTTP: http, catalogKeys: [C.publicKey])
        let flow = SetupFlow(env: env)
        await flow.importFile(try C.exportFile(schemas: ["extra"], in: m.dir.url))
        #expect(env.catalog.package("extra") != nil)
    }

    @Test func 清单来源的说法() throws {
        let catalog = try Catalog.decode(C.json(serial: 7))
        #expect(NetworkUse.catalogSource(CatalogStatus(catalog: catalog, origin: .builtIn, cacheProblem: nil))
                == "现在用的是应用内置的方案清单（编号 7）")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(NetworkUse.catalogSource(CatalogStatus(catalog: catalog, origin: .online(date), cacheProblem: nil))
                == "现在用的是在线方案清单（编号 7，\(date.formatted(date: .numeric, time: .omitted)) 下载）")
    }
}
```

- [ ] **Step 3: 跑测试，确认失败**

Run: `swift test --filter MainModelCatalogTests`
Expected: 编译失败（没有 `CatalogHolder`、`checkCatalog` 等）

- [ ] **Step 4: 实现**

`Sources/AppCore/CatalogHolder.swift`：

```swift
import Foundation
import RimeKit

/// 生效的方案清单。引导、主窗口共用一个：导入或检查更新换了清单，大家都看到新的
public final class CatalogHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var current: CatalogStatus

    public init(_ status: CatalogStatus) {
        current = status
    }

    public var status: CatalogStatus { lock.withLock { current } }

    public func update(_ status: CatalogStatus) {
        lock.withLock { current = status }
    }
}
```

`Sources/AppCore/NetworkUse.swift`：

```swift
import Foundation
import RimeKit

/// 应用什么时候联网（在线方案清单设计 4.6）：「诊断」页和「检查方案清单更新」按钮下面的说明
public enum NetworkUse {
    public struct Row: Sendable, Equatable {
        public let when: String
        public let host: String
        public let what: String
    }

    public static let catalogCheckNote = "会连接 GitHub（raw.githubusercontent.com），只下载方案清单，不上传任何内容。清单带签名，验不过就不用。"

    public static let rows: [Row] = [
        Row(when: "安装、更新鼠须管", host: "GitHub（api.github.com、github.com 和它的下载服务器）", what: "鼠须管安装包"),
        Row(when: "安装、更新方案，导入", host: "GitHub（api.github.com、codeload.github.com、github.com 和它的下载服务器）", what: "方案文件"),
        Row(when: "点「检查方案清单更新」，或导入时遇到不认识的方案", host: "GitHub（raw.githubusercontent.com）", what: "方案清单"),
    ]

    public static let footer = "以上都只下载，不上传你的设置、词库、短语或文本替换。除此以外应用不联网。"

    /// 现在用的是哪份方案清单
    public static func catalogSource(_ status: CatalogStatus) -> String {
        switch status.origin {
        case .builtIn:
            return "现在用的是应用内置的方案清单（编号 \(status.catalog.serial)）"
        case .online(let date):
            return "现在用的是在线方案清单（编号 \(status.catalog.serial)，\(date.formatted(date: .numeric, time: .omitted)) 下载）"
        }
    }
}
```

写完后核对 `footer` 那句「除此以外应用不联网」：运行 `grep -rn "http.get\|http.download\|\.download(\|URLSession" Sources`，确认只有 `SourceResolver`、`PackageStore`、`SquirrelInstaller`（以及它们用的 `HTTPClient`）和 `CatalogStore` 在联网；`Doctor` 在应用里用的是 `releaseSource: nil`（不联网）。对不上就改 `rows`。

`Sources/AppCore/AppEnvironment.swift`：

1. 把 `public var catalog: Catalog` 换成：

```swift
    /// 方案清单：读内置和缓存的、检查在线更新
    public var catalogStore: CatalogStore
    /// 生效的方案清单（引导和主窗口共用）
    public var catalogs: CatalogHolder
    public var catalog: Catalog { catalogs.status.catalog }
```

2. `live()` 里：

```swift
        let catalogStore = CatalogStore(paths: paths, http: http)
        return AppEnvironment(
            paths: paths, locations: locations, catalogStore: catalogStore, catalogs: CatalogHolder(try catalogStore.effective()),
            compiler: DeployerCompiler(locations: locations),
            ...（其余不变）
```

`Sources/AppCore/MainModel.swift`：

1. 先把这个文件和 `MainModel+Actions.swift` 里的 `env.catalog`（后面不跟字母的）都换成 `catalog`，让视图能观察到清单的变化：

```bash
perl -pi -e 's/env\.catalog\b/catalog/g' Sources/AppCore/MainModel.swift Sources/AppCore/MainModel+Actions.swift
```

（`env.catalogStore`、`env.catalogs` 不受影响。`importFile` 里原来的 `let catalog = env.catalog` 会变成 `let catalog = catalog`，下面第 4 步整段换掉。）

2. 在 `public var includeUserDB = true` 后面加：

```swift
    /// 生效的方案清单（检查更新、导入时会换）
    public internal(set) var catalogStatus: CatalogStatus
    public var catalog: Catalog { catalogStatus.catalog }
    /// 方案清单更新改到了正在用的包：要重新应用一次
    public internal(set) var catalogNeedsApply = false
    /// 底部要不要显示「应用改动」
    public var hasPendingChanges: Bool { isDirty || catalogNeedsApply }
```

`init` 里，`self.env = env` 后面加 `catalogStatus = env.catalogs.status`。

3. `catalogPackages` 改成：

```swift
    /// 有方案的包（方案页列出来让用户启用）。下架的不列，正在用的除外
    public var catalogPackages: [PackageSpec] {
        let used = Set((draft.schemas + saved.schemas).compactMap { catalog.packageOwning(schema: $0)?.id })
        return catalog.packages.filter { !$0.schemas.isEmpty && (!$0.deprecated || used.contains($0.id)) }
    }
```

`Sources/AppCore/MainModel+Actions.swift`：

1. `run(...)` 里 `case .applied(let report):` 下面 `saved = updated` 后面加一行：

```swift
                catalogNeedsApply = false
```

2. 在 `// MARK: 导出（设计 6.3）` 前面加：

```swift
    // MARK: 方案清单（在线方案清单设计 4.2）

    public func checkCatalog() async {
        guard working == nil else { return }
        working = "正在检查方案清单更新……"
        defer { working = nil }
        let store = env.catalogStore
        let inUse = saved
        switch await store.check(inUse: inUse) {
        case .upToDate:
            notice = Notice(kind: .info, title: "方案清单已经是最新的", lines: [])
        case .updated(let diff, let status):
            adoptCatalog(status)
            if diff.affectsInUse { catalogNeedsApply = true }
            notice = Notice(kind: .info, title: "方案清单更新了", lines: diff.lines)
        case .rejected(let reason):
            notice = Notice(kind: .warning, title: "没有用上新的方案清单", lines: [reason, "继续用现在的方案清单"])
        }
    }

    /// 换成新的方案清单；引导和主窗口共用一份
    func adoptCatalog(_ status: CatalogStatus) {
        env.catalogs.update(status)
        catalogStatus = status
        refreshColorSchemes()
    }
```

3. `importFile` 里，从 `do {` 到 `var lines = archive.warnings + fallback` 这几行换成：

```swift
        do {
            let catalogStore = env.catalogStore
            let current = catalog
            let inUse = saved
            let opened = try await offMain {
                try await catalogStore.openArchive(file, catalog: current, inUse: inUse, into: work,
                                                   checking: { await MainActor.run { self.working = "正在更新方案清单……" } })
            }
            var catalogNote: [String] = []
            if let updated = opened.updated {
                adoptCatalog(updated)
                catalogNote = ["导出文件里有现在的方案清单不认识的方案，已经更新了方案清单"]
            }
            let archive = opened.archive
            let catalog = self.catalog
            let settings = archive.manifest.settings
            // 导入是一次性的：下载不了就直接用本地旧版本，结果里提醒（和第一次打开时的导入一样）
            let (packages, fallback) = try await packagesFallingBack(for: settings)
            var lines = catalogNote + archive.warnings + fallback
```

并在 `case .applied(let applied):` 下面第一行加 `catalogNeedsApply = false`。

`Sources/AppCore/SetupFlow.swift` 的 `importFile`，把：

```swift
            let catalog = env.catalog
            let archive = try await offMain { try ImportArchive.open(file, catalog: catalog, into: work) }
            let settings = archive.manifest.settings
            let packages = try await fetch(try settings.requiredPackages(env.catalog))
            var notes = archive.warnings
```

换成：

```swift
            let catalogStore = env.catalogStore
            let current = env.catalog
            let opened = try await offMain {
                try await catalogStore.openArchive(file, catalog: current, inUse: nil, into: work,
                                                   checking: { await MainActor.run { self.step = .working("正在更新方案清单……") } })
            }
            if let updated = opened.updated { env.catalogs.update(updated) }
            let archive = opened.archive
            let catalog = env.catalog
            let settings = archive.manifest.settings
            let packages = try await fetch(try settings.requiredPackages(catalog))
            var notes = archive.warnings
            if opened.updated != nil { notes.insert("导出文件里有现在的方案清单不认识的方案，已经更新了方案清单", at: 0) }
```

- [ ] **Step 5: 跑测试，确认通过**

Run: `swift test`
Expected: 全部通过（原来的 `MainModelActionsTests`、`SetupFlowTests` 也要通过）

- [ ] **Step 6: 提交**

```bash
git add Sources/AppCore Tests/RimeKitTests
git commit -m "feat(app): 检查方案清单更新、导入时自动更新清单、下架的方案不再列出

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 界面

**Files:**
- Modify: `Sources/AppUI/SchemasPage.swift`、`Sources/AppUI/DiagnosticsPage.swift`、`Sources/AppUI/MainView.swift`

**Interfaces:**
- Consumes: `MainModel.checkCatalog()`、`hasPendingChanges`、`catalogNeedsApply`、`catalogStatus`；`NetworkUse`（任务 8）

视图层没有单元测试；这一步只要求编译通过，在任务 12 的测试机里检查。

- [ ] **Step 1: 方案页加按钮和说明**

`Sources/AppUI/SchemasPage.swift`，把：

```swift
            Text("可以启用的方案").font(.title2.bold())
```

换成：

```swift
            HStack(alignment: .firstTextBaseline) {
                Text("可以启用的方案").font(.title2.bold())
                Spacer()
                Button("检查方案清单更新") { Task { await model.checkCatalog() } }
                    .disabled(model.working != nil)
            }
            Text(NetworkUse.catalogCheckNote).font(.caption).foregroundStyle(.secondary)
```

- [ ] **Step 2: 底部提示**

`Sources/AppUI/MainView.swift` 的 `ApplyBar`，把 `} else if model.isDirty {` 那一段换成：

```swift
        } else if model.hasPendingChanges {
            HStack(spacing: 10) {
                Label(model.isDirty ? "有改动还没应用" : "方案清单更新了，还没应用", systemImage: "pencil.circle")
                Spacer()
                if model.isDirty { Button("撤销") { model.revert() } }
                Button("应用改动") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
```

- [ ] **Step 3: 诊断页加「应用什么时候会联网」**

`Sources/AppUI/DiagnosticsPage.swift`，在 `ForEach(Array(model.checks.enumerated()) …) { … }` 后面（`VStack` 里面）加：

```swift
            Divider().padding(.vertical, 6)
            Text("应用什么时候会联网").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("什么时候").bold()
                    Text("连哪里").bold()
                    Text("下载什么").bold()
                }
                ForEach(NetworkUse.rows, id: \.when) { row in
                    GridRow {
                        Text(row.when)
                        Text(row.host)
                        Text(row.what)
                    }
                }
            }
            .font(.callout)
            Text(NetworkUse.footer).font(.caption).foregroundStyle(.secondary)
            Text(NetworkUse.catalogSource(model.catalogStatus)).font(.caption).foregroundStyle(.secondary)
            if let problem = model.catalogStatus.cacheProblem {
                Text("缓存的在线方案清单用不了（\(problem)），先用内置的").font(.caption).foregroundStyle(.orange)
            }
```

- [ ] **Step 4: 编译、跑测试**

Run: `swift build && swift test`
Expected: 编译成功，测试全部通过

- [ ] **Step 5: 提交**

```bash
git add Sources/AppUI
git commit -m "feat(app): 方案页「检查方案清单更新」、诊断页说明什么时候联网

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 发布工具、文档、联网测试

**Files:**
- Create: `tools/catalog/keygen.sh`、`tools/catalog/publish.sh`
- Modify: `docs/release.md`、`Tests/RimeKitTests/OnlineTests.swift`

**Interfaces:**
- Consumes: rimectl 的 `catalog keygen/sign/verify/verify-source`（任务 7）

- [ ] **Step 1: 生成密钥的脚本**

`tools/catalog/keygen.sh`：

```bash
#!/bin/bash
# 第一次发布在线方案清单前运行一次（在线方案清单设计 5.2）：
# 生成签名密钥，私钥存进登录钥匙串，打印公钥。私钥不落盘、不打印。
set -euo pipefail
cd "$(dirname "$0")/../.."
SERVICE="squirrel-macos-catalog-signing"
if security find-generic-password -s "$SERVICE" >/dev/null 2>&1; then
  echo "钥匙串里已经有 $SERVICE，不重新生成（要换密钥，先在「钥匙串访问」里删掉它，并且要发新版应用换公钥）" >&2
  exit 1
fi
swift build --product rimectl >/dev/null
OUTPUT="$(.build/debug/rimectl catalog keygen)"
PRIVATE="$(echo "$OUTPUT" | awk '$1=="private"{print $2}')"
PUBLIC="$(echo "$OUTPUT" | awk '$1=="public"{print $2}')"
# 私钥作为参数传给 security，运行的一瞬间会出现在本机进程列表里；单用户的开发机可以接受
security add-generic-password -s "$SERVICE" -a catalog -w "$PRIVATE"
echo "私钥已存进登录钥匙串（服务名 $SERVICE）。请另外备份一份，例如存进密码管理器："
echo "  security find-generic-password -s $SERVICE -w"
echo "公钥（写进 Sources/RimeKit/Catalog/CatalogSignature.swift 的 publicKeys）："
echo "$PUBLIC"
```

- [ ] **Step 2: 发布脚本**

`tools/catalog/publish.sh`：

```bash
#!/bin/bash
# 发布在线方案清单（在线方案清单设计 5.1）：校验 → 复制到 catalog/v1/ → 签名。提交、推送另外问过再做。
#   ./tools/catalog/publish.sh                   校验、复制、签名
#   ./tools/catalog/publish.sh --verify-remote   推送以后，从 GitHub 拉回来再验一次
set -euo pipefail
cd "$(dirname "$0")/../.."
SERVICE="squirrel-macos-catalog-signing"
SOURCE="Sources/RimeKit/Resources/catalog.json"
DEST="catalog/v1"
REMOTE="https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1"
swift build --product rimectl >/dev/null
RIMECTL=".build/debug/rimectl"

if [[ "${1:-}" == "--verify-remote" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL "$REMOTE/catalog.json" -o "$TMP/catalog.json"
  curl -fsSL "$REMOTE/catalog.json.sig" -o "$TMP/catalog.json.sig"
  "$RIMECTL" catalog verify "$TMP/catalog.json" "$TMP/catalog.json.sig"
  if ! cmp -s "$TMP/catalog.json" "$DEST/catalog.json"; then
    echo "GitHub 上的清单和本地 $DEST 不一样：可能还没推送，或者 GitHub 还在用缓存（几分钟后再试）" >&2
    exit 1
  fi
  echo "GitHub 上的方案清单签名正确，和本地一致"
  exit 0
fi

mkdir -p "$DEST"
"$RIMECTL" catalog verify-source "$SOURCE" "$DEST/catalog.json"
cp "$SOURCE" "$DEST/catalog.json"
security find-generic-password -s "$SERVICE" -w | "$RIMECTL" catalog sign "$DEST/catalog.json" --out "$DEST/catalog.json.sig"
"$RIMECTL" catalog verify "$DEST/catalog.json" "$DEST/catalog.json.sig"
echo "已写好 $DEST/catalog.json 和签名。接下来："
echo "  1. swift test；RIMEKIT_ONLINE=1 swift test --filter OnlineTests；加了新方案的话再跑 OnlineGenerateTests"
echo "  2. 问过以后提交、推送 main"
echo "  3. ./tools/catalog/publish.sh --verify-remote"
```

```bash
chmod +x tools/catalog/keygen.sh tools/catalog/publish.sh
bash -n tools/catalog/keygen.sh && bash -n tools/catalog/publish.sh
```

Expected: 没有输出（语法正确）

- [ ] **Step 3: 联网测试**

`Tests/RimeKitTests/OnlineTests.swift`：

1. 下载测试的参数改成内置清单里的全部包：

```swift
    @Test(arguments: (try? Catalog.builtIn().packages.map(\.id)) ?? [])
    func 真实下载内置清单里的包(id: String) async throws {
```

2. 加一条：

```swift
    @Test func 在线方案清单签名正确而且不比内置的旧() async throws {
        let http = URLSessionHTTPClient()
        let data = try await http.get(CatalogStore.defaultRemote)
        let signature = try await http.get(CatalogStore.signatureURL(CatalogStore.defaultRemote))
        #expect(CatalogSignature.verify(data, signature: signature, keys: CatalogSignature.trustedKeys))
        #expect(try Catalog.decode(data).serial >= Catalog.builtIn().serial)
    }
```

（这条在任务 11 发布第一份在线清单之前会失败，属于正常：它就是用来发现「忘了发布」的。）

- [ ] **Step 4: release 编译里没有测试后门**

```bash
swift build -c release --product rimectl
strings .build/release/rimectl | grep -c RIMEKIT_CATALOG || true
```

Expected: 输出 `0`

- [ ] **Step 5: 写进 `docs/release.md`**

在文件末尾加一节：

```markdown
## 发布方案清单

方案清单和应用是分开发布的：改清单不用发新版应用（在线方案清单设计 5.1）。

1. 改正本 `Sources/RimeKit/Resources/catalog.json`，`serial` 改大（日期加两位序号，例如 `2026102001`）。已经发布过的包 id、方案 id 不能删、不能改；要下架就标 `"deprecated": true`。要新代码才能用的包写 `"minAppVersion"`。
2. `swift test`；`RIMEKIT_ONLINE=1 swift test --filter OnlineTests`（会真的下载清单里的每个包）。加了新方案时，在 `OnlineGenerateTests` 里补一条打字检查，再跑 `RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests`；并在测试机里走一遍（见 `docs/superpowers/plans/2026-10-15-online-catalog.md` 任务 12）。
3. `./tools/catalog/publish.sh`：校验（serial 变大、id 没删）→ 复制到 `catalog/v1/` → 用钥匙串里的私钥签名。钥匙串问能不能用时点「始终允许」。
4. 问过以后提交、推送 `main`。
5. `./tools/catalog/publish.sh --verify-remote`：从 GitHub 拉回来再验一次（GitHub 的 raw 文件有几分钟缓存）。

发应用新版前，先确认正本已经发布（`catalog/v1/catalog.json` 和正本一样）。不然内置清单比在线的新，在线那份就不起作用了——不会出错，但说明漏了一步。

密钥：第一次用 `./tools/catalog/keygen.sh` 生成，私钥在登录钥匙串（服务名 `squirrel-macos-catalog-signing`），**要另外备份**。私钥丢了只能发新版应用换公钥。

开发用的隐藏命令（不在 `rimectl --help` 里）：`rimectl catalog keygen`、`catalog sign <文件> --out <签名文件>`（私钥从标准输入读）、`catalog verify <文件> <签名文件>`、`catalog verify-source <新清单> [<上次发布的清单>]`。debug 编译的 RimeKit 认两个环境变量，测试机实测用：`RIMEKIT_CATALOG_URL`（换清单地址）、`RIMEKIT_CATALOG_TEST_PUBKEY`（多认一个测试公钥）。release 编译里没有。
```

- [ ] **Step 6: 跑测试、提交**

Run: `swift test`
Expected: 全部通过（`OnlineTests` 默认不跑）

```bash
git add tools/catalog docs/release.md Tests/RimeKitTests/OnlineTests.swift
git commit -m "chore(catalog): 发布脚本、生成密钥脚本、发布说明、联网测试

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 生成正式密钥，发布第一份在线清单

这一步会在宿主机的登录钥匙串里加一项，还要推送到 GitHub。**每一步开始前先问用户。**

**Files:**
- Modify: `Sources/RimeKit/Catalog/CatalogSignature.swift`（`publicKeys`）
- Create: `catalog/v1/catalog.json`、`catalog/v1/catalog.json.sig`（脚本生成）

- [ ] **Step 1: 生成密钥（问过用户再运行，或请用户自己运行）**

```bash
./tools/catalog/keygen.sh
```

Expected: 打印「私钥已存进登录钥匙串」和一行公钥（base64，44 个字符）。提醒用户备份私钥。

- [ ] **Step 2: 写进公钥**

`Sources/RimeKit/Catalog/CatalogSignature.swift`：

```swift
    static let publicKeys: [String] = ["<上一步打印的公钥>"]
```

加一条测试（`Tests/RimeKitTests/CatalogSignatureTests.swift`）：

```swift
    @Test func 正式公钥能解析() {
        #expect(CatalogSignature.publicKeys.count == 1)
        #expect(CatalogSignature.publicKeys.allSatisfy { Data(base64Encoded: $0)?.count == 32 })
    }
```

Run: `swift test`
Expected: 全部通过

- [ ] **Step 3: 发布**

```bash
./tools/catalog/publish.sh
swift test
RIMEKIT_ONLINE=1 swift test --filter OnlineTests
```

Expected: `publish.sh` 输出「清单可以发布（编号 2026101501，包 3 个）」「签名正确」；`OnlineTests` 里除了「在线方案清单签名正确」那条（还没推送）都通过。

- [ ] **Step 4: 提交（推送前问用户）**

```bash
git add Sources/RimeKit/Catalog/CatalogSignature.swift Tests/RimeKitTests/CatalogSignatureTests.swift catalog/v1
git commit -m "feat(catalog): 正式公钥，发布第一份在线方案清单（编号 2026101501）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

用户同意后：

```bash
git push origin main
./tools/catalog/publish.sh --verify-remote
RIMEKIT_ONLINE=1 swift test --filter OnlineTests
```

Expected: `--verify-remote` 输出「GitHub 上的方案清单签名正确，和本地一致」（不一致时等几分钟再试）；`OnlineTests` 全部通过。

---

### Task 12: 测试机里走一遍，收尾文档

**Files:**
- Modify: `README.md`、`CLAUDE.md`、`docs/superpowers/plans/2026-10-15-v2-roadmap.md`、`docs/verified-facts.md`
- Create: `docs/online-catalog-vm-log.md`

- [ ] **Step 1: 用 rimectl 试（测试清单、测试密钥）**

宿主机：

```bash
swift build --product rimectl
VMDIR="$(mktemp -d /tmp/catalog-vm.XXXX)"
.build/debug/rimectl catalog keygen > "$VMDIR/keys.txt"
```

从正本做一份测试清单（`serial` 改成 `2099010101`；`rime-ice` 的 `include` 末尾加一项 `README.md`，算规则变化，不影响生成；`wubi86-jidian` 标下架），签名，用宿主机发给测试机：

```bash
mkdir -p "$VMDIR/v1"
/usr/bin/python3 - "$VMDIR/v1/catalog.json" <<'EOF'
import json, sys
c = json.load(open("Sources/RimeKit/Resources/catalog.json"))
c["serial"] = 2099010101
for p in c["packages"]:
    if p["id"] == "rime-ice": p["include"].append("README.md")
    if p["id"] == "wubi86-jidian": p["deprecated"] = True
json.dump(c, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
EOF
awk '$1=="private"{print $2}' "$VMDIR/keys.txt" | .build/debug/rimectl catalog sign "$VMDIR/v1/catalog.json" --out "$VMDIR/v1/catalog.json.sig"
awk '$1=="public"{print $2}' "$VMDIR/keys.txt"      # 测试公钥，下面要用
/usr/bin/python3 -m http.server 8765 --bind 192.168.64.1 --directory "$VMDIR"   # 用 run_in_background 跑；测完停掉
```

先确认测试机连得上宿主机：`./tools/vm/vm.sh ssh squirrel-dev "curl -sI http://192.168.64.1:8765/v1/catalog.json"`。`192.168.64.1` 不对的话，用 `ifconfig bridge100` 查宿主机在虚拟网络里的地址，上面的地址跟着换。

测试机 `squirrel-dev`：按 CLAUDE.md 先把 `.build/debug/rimectl` 和 `SquirrelMacOS_RimeKit.bundle` 复制到 `/tmp/rimectl-bin/`。下面的命令都在测试机里运行，`KEY` 换成上面打印的测试公钥；数据目录用新的 `/tmp/rk-catalog`：

```bash
URL=http://192.168.64.1:8765/v1/catalog.json
KEY=测试公钥
R=/tmp/rimectl-bin/rimectl
# 测试机的 shell 是 zsh，不会拆开变量里的空格，所以用函数
asuser() { sudo launchctl asuser $(id -u) sudo -u tester env RIMEKIT_CATALOG_URL=$URL RIMEKIT_CATALOG_TEST_PUBKEY=$KEY "$@"; }
asuser $R takeover --confirm --data-dir /tmp/rk-catalog       # 先接管测试机上已有的雾凇配置
asuser $R catalog show --data-dir /tmp/rk-catalog             # 用的是内置方案清单（编号 2026101501）
asuser $R catalog check --data-dir /tmp/rk-catalog            # 雾凇拼音的安装规则变了；极点五笔 86 下架了
asuser $R catalog show --data-dir /tmp/rk-catalog             # 用的是在线方案清单（编号 2099010101）
asuser $R apply --data-dir /tmp/rk-catalog                    # 按新规则重新应用
```

然后按 `docs/verified-facts.md`「用 librime 模拟打字」，用 `rime-type-probe` 在 `~/Library/Rime` 的副本上打 `nihao`，第一个候选是「你好」。

再试两种不采用的情况，各自记下输出：
- 签名不对：在宿主机把 `$VMDIR/v1/catalog.json` 的 `serial` 改成 `2099010102`（不重新签名），测试机 `catalog check` → 「签名不对」，`catalog show` 还是 2099010101；
- 和设置对不上：在宿主机用上面的 python 片段再做一份，`serial` 设成 `2099010103`，并删掉 `rime-ice` 的 `double_pinyin_flypy` 方案（`p["schemas"] = [s for s in p["schemas"] if s["id"] != "double_pinyin_flypy"]`），重新签名；测试机 `catalog check` → 「和你现在的设置对不上」。

- [ ] **Step 2: 发布第一份在线清单后，用应用试（由用户在界面上点）**

用 `./tools/vm/install-app.sh squirrel-dev` 装上应用（连的是任务 11 发布的正式清单）。请用户：
1. 「方案」页：看「检查方案清单更新」按钮和下面的灰字；点一下 → 「方案清单已经是最新的」（在线的编号和内置的一样）；
2. 「诊断」页：看「应用什么时候会联网」表格、「现在用的是应用内置的方案清单（编号 2026101501）」；
3. 退出应用。在测试机里放一份缓存清单再改坏它：

   ```bash
   D="$HOME/Library/Application Support/squirrel-macos/catalog"
   mkdir -p "$D"
   curl -fsSL https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json -o "$D/catalog.json"
   curl -fsSL https://raw.githubusercontent.com/pokoblin/squirrel-macos/main/catalog/v1/catalog.json.sig -o "$D/catalog.json.sig"
   printf ' ' >> "$D/catalog.json"
   ```

   重新打开应用 → 「诊断」页显示「缓存的在线方案清单用不了（缓存的方案清单签名不对），先用内置的」，应用照常能用。测完删掉 `$D`。

- [ ] **Step 3: 记录**

`docs/online-catalog-vm-log.md`：按上面的步骤写实际输出和结论（只写条数、编号，不写个人内容）。`docs/verified-facts.md` 加一条：测试机里访问宿主机用的地址；raw.githubusercontent.com 的缓存时间（实测）。

- [ ] **Step 4: 收尾文档**

- `README.md` 第 101 行附近改成：「应用只在安装鼠须管、下载方案、检查方案清单更新时联网，都是从 GitHub 下载……」，并说明方案清单可以在「方案」页检查更新、带签名。
- `CLAUDE.md` 开头的状态改成：第二版子项目 1「在线方案清单」已完成；「先读这些」加上在线方案清单设计；工作方式加一条「发布方案清单：`./tools/catalog/publish.sh`，步骤见 `docs/release.md`；推送前先问用户」。
- `docs/superpowers/plans/2026-10-15-v2-roadmap.md`：子项目 1 的状态改成「已完成（日期）」，链接到本计划和测试记录。

- [ ] **Step 5: 提交、推送（推送前问用户）**

```bash
git add README.md CLAUDE.md docs
git commit -m "docs: 在线方案清单的测试机记录，更新说明和路线图

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

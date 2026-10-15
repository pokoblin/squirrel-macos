# 阶段 2：设置 + 配置生成 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 根据用户的设置（启用哪些方案、包选项、外观、个人词库、短语），加上缓存里的上游包，在一个空目录里生成一份完整的 Rime 用户目录；生成结果能被鼠须管自带的 `rime_deployer` 编译，并且用打字检查工具能打出预期的字。命令行加 `rimectl settings` 和 `rimectl generate`。

**Architecture:** 新增 `Settings`（用户的选择，存 `settings.json`）、`PersonalContent`（个人词库和手动短语）、`Patch`（有顺序的 Rime 补丁，读写 `*.custom.yaml`）、`ConfigGenerator`（生成器）。清单格式加「包选项」（极点五笔的拼音词库）。生成器只往一个**空的**输出目录写，不读不写 `~/Library/Rime`；写入真实配置是阶段 3 的事。生成规则见下面「生成规则」一节，执行任务 11 时补进设计文档。

**Tech Stack:** Swift 6.4、Swift Testing、Yams 6.2.2（读写 YAML，MIT 许可证）、鼠须管自带的 `rime_deployer`（只读使用，只编译临时目录）、`tools/vm/rime-type-probe`（打字检查）。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 4、5、6.1、8 节）；上游结构 [docs/upstream-layouts.md](../../upstream-layouts.md)；样板配置 [docs/reference-wubi-profile.md](../../reference-wubi-profile.md)；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## Global Constraints

- 最低 macOS 27；Swift 6 严格并发。唯一的第三方依赖是 Yams，**固定版本 6.2.2**（`exact:`）。
- 生成器和 `rimectl generate` **绝不写 `~/Library/Rime`**：输出目录必须为空或不存在；`rimectl generate --out` 指向真实 Rime 目录（任何写法、包括子目录）时拒绝。
- 测试只用临时目录。用到鼠须管的测试只读使用 `/Library/Input Methods/Squirrel.app` 里的 `rime_deployer` 和 `librime`，没装鼠须管时跳过。
- 外观只用鼠须管 1.1.2 真正认的键（已用 `strings` 确认）：`style/color_scheme`、`style/color_scheme_dark`、`font_point`、`label_font_point`、`comment_font_point`、`candidate_list_layout`（`stacked`/`linear`）、`text_orientation`（`horizontal`/`vertical`）；每页候选数是 `default.custom.yaml` 的 `menu/page_size`。**不用 `candidate_font_point`、`font_face`**。
- 范围：字号 8…72；每页候选数 1…10。
- 个人内容只统计条数，不打印内容；测试数据全部自造。
- 代码注释、错误信息、命令行输出用简单直白的中文。
- 生成的文件开头写：`# 由 squirrel-macos 生成。请在应用里修改设置；直接改这个文件，下次应用时会被覆盖。`
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## 生成规则（本阶段定下，任务 11 写进设计文档）

1. **要用到的包** = 启用的方案所属的包 + 这些包所选选项的依赖（再按清单的依赖顺序展开）。
2. **复制上游文件**：按安装顺序复制每个包缓存里的文件，**不复制**根目录的 `*.custom.yaml`（当作上游默认补丁）和 `LICENSE`。两个包有同一路径的文件时后面的覆盖前面的；内容不同就记一条提醒。
3. **补丁按顺序叠加**（Rime 按顺序应用补丁，后面的覆盖前面的，已实测）：上游自带的 `<名字>.custom.yaml` → 包选项的补丁 → 短语注入 → 设置里保留的补丁 → 应用管理的键。同一个键再写一次时，删掉旧的、放到最后。
4. **应用管理的键**：`default.custom.yaml` 写 `schema_list`（设置里的顺序，第一个是默认方案）和 `menu/page_size`；`squirrel.custom.yaml` 写外观。外观里的字号、横竖排同时写到 `style/<键>` 和**实际生效的浅色、深色配色**的 `preset_color_schemes/<配色>/<键>`（极点五笔把字号写在配色里，只改 `style` 不生效）。实际生效的配色：设置里指定的 > 补丁里写的 > 包里的 `squirrel.yaml` 写的。
5. **包选项**：所选选项的补丁写进对应方案的 `<方案>.custom.yaml`（只写启用了的方案）；选项要生成的总词库（如 `pinyin_ext.dict.yaml`）由应用生成，标了「只在有个人词库时」的导入表，只在用户有同名个人词库时才挂上。
6. **个人词库**：`personal/dicts/*.dict.yaml` 复制到输出目录根，和上游同名时**用个人的**。
7. **短语**（手动短语 + 文本替换生成的短语，有短语时才处理）：对每个启用的方案，如果方案本来就有 `table_translator@custom_phrase`，用它的 `custom_phrase/user_dict` 指定的文件（雾凇全拼是 `custom_phrase.txt`，小鹤双拼是 `custom_phrase_double.txt`）；没有的（极点五笔）注入短语翻译器，用 `custom_phrase.txt`。每个短语文件 = 上游同名文件原样（如果有）+ 用户的短语；上游没有就新建。
8. 只有内容不为空的补丁才生成 `.custom.yaml` 文件。

## Review Focus

1. 两个包里有同一路径、内容不同的文件 → 后面的覆盖前面的，并给出提醒（任务 5 有测试）。
2. 用户改了字号，而包的配色里本身写了字号 → 必须仍然生效：配色里也要写（任务 6 有测试，任务 9 编译验证）。
3. 个人词库和上游模板同名（`wubi86_jidian_user.dict.yaml`）→ 用个人的，上游更新不会盖掉（任务 7 有测试）。
4. 同时启用全拼和双拼，它们用不同的短语文件 → 每个方案都能打出用户的短语（任务 8、9、11 有测试）。
5. `rimectl generate --out` 指向真实的 `~/Library/Rime`（任何写法，包括还不存在的、子目录、firmlink 路径）→ 什么都不写就拒绝（任务 10 有测试）。

---

## 文件结构

```
Package.swift                                   # 加 Yams
Sources/RimeKit/
  AppPaths.swift                                # 加 settingsFile、personal…
  Catalog/Catalog.swift                         # PackageSpec 加 options；校验选项；packageOwning
  Catalog/CatalogError.swift                    # 加两种错误
  Catalog/PackageOption.swift                   # 包选项的数据结构
  Resources/catalog.json                        # 极点五笔加「拼音词库」选项
  Config/Patch.swift                            # 有顺序的补丁、YAMLNode 小工具
  Config/Settings.swift                         # 设置、校验、起步方案、要用到的包
  Config/SettingsStore.swift                    # 读写 settings.json
  Config/Personal.swift                         # Phrase、PhraseFile、PersonalContent
  Config/ConfigGenerator.swift                  # 生成器入口和公共类型
  Config/GenerationContext.swift                # 生成的各个步骤
  Config/RimeDirectoryGuard.swift               # 判断是不是真实的 ~/Library/Rime
Sources/rimectl/Rimectl.swift                   # 加 settings、generate
Tests/RimeKitTests/
  Support/GenFixtures.swift                     # 自造的三个包（可以真的编译）
  Support/RimeTools.swift                       # 调 rime_deployer 和打字检查工具
  PatchTests.swift
  PackageOptionTests.swift
  SettingsTests.swift
  PersonalTests.swift
  GeneratorBasicsTests.swift
  GeneratorAppearanceTests.swift
  GeneratorOptionsTests.swift
  GeneratorPhraseTests.swift
  GeneratedConfigCompileTests.swift
  RimeDirectoryGuardTests.swift
  RimectlGenerateTests.swift
  OnlineGenerateTests.swift
```

---

### Task 1: 加 Yams，写有顺序的补丁 `Patch`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/RimeKit/Config/Patch.swift`
- Test: `Tests/RimeKitTests/PatchTests.swift`

**Interfaces:**
- Produces:
  - `public enum YAMLNode { static func text(_ s: String) -> Node; static func int(_ n: Int) -> Node; static func bool(_ b: Bool) -> Node; static func map(_ pairs: [(String, Node)]) -> Node; static func list(_ items: [Node]) -> Node; static func parse(_ text: String) throws -> Node? }`
  - `public struct Patch: Equatable { public struct Entry: Equatable { key: String; value: Node }; public private(set) var entries: [Entry]; public init(); public var isEmpty: Bool; public subscript(key: String) -> Node? { get }; public mutating func set(_ key: String, _ value: Node); public mutating func merge(_ other: Patch); public static func parse(customYAML: String) throws -> Patch; public func renderCustomYAML() throws -> String; public static let header: String }`
  - `set`：同一个键已经有了就删掉旧的，新的放到最后（和 Rime 按顺序应用补丁的规则一致）。

- [ ] **Step 1: `Package.swift` 加 Yams**

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
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "RimeKit",
            dependencies: [.product(name: "Yams", package: "Yams")],
            resources: [.copy("Resources/catalog.json")]
        ),
        .executableTarget(name: "rimectl", dependencies: ["RimeKit"]),
        .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "rimectl"]),
    ]
)
```

Run: `swift package resolve 2>&1 | tail -2 && swift build 2>&1 | tail -1`
Expected: 拉到 Yams 6.2.2，`Build complete!`。生成的 `Package.resolved` 要提交。

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/PatchTests.swift`**

```swift
import Foundation
import Testing
import Yams
@testable import RimeKit

@Suite struct PatchTests {
    @Test func 同一个键再写一次会移到最后() {
        var p = Patch()
        p.set("a", YAMLNode.text("1"))
        p.set("b", YAMLNode.text("2"))
        p.set("a", YAMLNode.text("3"))
        #expect(p.entries.map(\.key) == ["b", "a"])
        #expect(p["a"]?.string == "3")
    }

    @Test func 合并时后面的覆盖前面的() {
        var base = Patch()
        base.set("menu/page_size", YAMLNode.int(5))
        base.set("x", YAMLNode.text("keep"))
        var other = Patch()
        other.set("menu/page_size", YAMLNode.int(7))
        base.merge(other)
        #expect(base.entries.map(\.key) == ["x", "menu/page_size"])
        #expect(base["menu/page_size"]?.string == "7")
    }

    @Test func 读上游的补丁文件保留顺序和嵌套() throws {
        let text = """
        # 注释
        patch:
          style:
            color_scheme: roseo_maple   # 行尾注释
          preset_color_schemes:
            roseo_maple:
              font_point: 18
          "menu/page_size": 5
        """
        let p = try Patch.parse(customYAML: text)
        #expect(p.entries.map(\.key) == ["style", "preset_color_schemes", "menu/page_size"])
        #expect(p["style"]?["color_scheme"]?.string == "roseo_maple")
        #expect(p["preset_color_schemes"]?["roseo_maple"]?["font_point"]?.string == "18")
    }

    @Test func 没有patch段或空文件得到空补丁() throws {
        #expect(try Patch.parse(customYAML: "").isEmpty)
        #expect(try Patch.parse(customYAML: "# 只有注释\n").isEmpty)
        #expect(try Patch.parse(customYAML: "other: 1\n").isEmpty)
    }

    @Test func 写出来再读回去不变() throws {
        var p = Patch()
        p.set("schema_list", YAMLNode.list([YAMLNode.map([("schema", YAMLNode.text("wubi86_jidian_pinyin"))])]))
        p.set("preset_color_schemes/roseo_maple/font_point", YAMLNode.int(24))
        p.set("custom_phrase", YAMLNode.map([("dictionary", YAMLNode.text("")), ("enable_sentence", YAMLNode.bool(false))]))
        p.set("name", YAMLNode.text("玫枫"))
        let text = try p.renderCustomYAML()
        #expect(text.hasPrefix(Patch.header))
        #expect(text.contains("玫枫"))   // 中文不转义
        let back = try Patch.parse(customYAML: text)
        #expect(back.entries.map(\.key) == p.entries.map(\.key))
        #expect(back["schema_list"]?.sequence?.first?["schema"]?.string == "wubi86_jidian_pinyin")
        #expect(back["preset_color_schemes/roseo_maple/font_point"]?.string == "24")
        #expect(back["custom_phrase"]?["dictionary"]?.string == "")
        #expect(back["custom_phrase"]?["enable_sentence"]?.string == "false")
    }

    @Test func 坏的YAML会报错() {
        #expect(throws: (any Error).self) {
            try Patch.parse(customYAML: "patch:\n  a: [1, 2\n")
        }
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter PatchTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'Patch' in scope`（或 `YAMLNode`）。

- [ ] **Step 4: 实现 `Sources/RimeKit/Config/Patch.swift`**

```swift
import Foundation
import Yams

/// 造 YAML 节点的小工具
public enum YAMLNode {
    public static func text(_ s: String) -> Node { Node(s) }
    public static func int(_ n: Int) -> Node { Node(String(n)) }
    public static func bool(_ b: Bool) -> Node { Node(b ? "true" : "false") }

    public static func map(_ pairs: [(String, Node)]) -> Node {
        .mapping(Node.Mapping(pairs.map { (Node($0.0), $0.1) }))
    }

    public static func list(_ items: [Node]) -> Node {
        .sequence(Node.Sequence(items))
    }

    /// 读一段 YAML；空文本返回 nil
    public static func parse(_ text: String) throws -> Node? {
        try Yams.compose(yaml: text)
    }
}

/// 一份 Rime 补丁，也就是 xxx.custom.yaml 里 `patch:` 下面的内容。
/// 键按加入的顺序保留。Rime 按顺序应用补丁、后面的覆盖前面的，
/// 所以同一个键再写一次时，删掉旧的、把新的放到最后。
public struct Patch: Equatable {
    public struct Entry: Equatable {
        public let key: String
        public let value: Node
    }

    public static let header = "# 由 squirrel-macos 生成。请在应用里修改设置；直接改这个文件，下次应用时会被覆盖。\n"

    public private(set) var entries: [Entry] = []

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public subscript(key: String) -> Node? {
        entries.last { $0.key == key }?.value
    }

    public mutating func set(_ key: String, _ value: Node) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, value: value))
    }

    public mutating func merge(_ other: Patch) {
        for entry in other.entries { set(entry.key, entry.value) }
    }

    /// 从 xxx.custom.yaml 的全文读出补丁；没有 patch 段时得到空补丁
    public static func parse(customYAML text: String) throws -> Patch {
        var patch = Patch()
        guard let root = try YAMLNode.parse(text), let mapping = root["patch"]?.mapping else { return patch }
        for (key, value) in mapping {
            guard let name = key.string else { continue }
            patch.set(name, value)
        }
        return patch
    }

    /// 生成 xxx.custom.yaml 的全文（带说明头）
    public func renderCustomYAML() throws -> String {
        let body = Node.mapping(Node.Mapping(entries.map { (Node($0.key), $0.value) }))
        let root = YAMLNode.map([("patch", body)])
        return Self.header + (try Yams.serialize(node: root, allowUnicode: true))
    }
}
```

- [ ] **Step 5: 运行，确认通过**

Run: `swift test --filter PatchTests 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 6 个测试全部通过。

- [ ] **Step 6: 提交**

```bash
git add Package.swift Package.resolved Sources/RimeKit/Config/Patch.swift Tests/RimeKitTests/PatchTests.swift
git commit -m "feat: 加 Yams，有顺序的 Rime 补丁 Patch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 清单加「包选项」

**Files:**
- Create: `Sources/RimeKit/Catalog/PackageOption.swift`
- Modify: `Sources/RimeKit/Catalog/Catalog.swift`（`PackageSpec` 加 `options`，自己写解码；`validate()` 加选项检查；加 `packageOwning(schema:)`）
- Modify: `Sources/RimeKit/Catalog/CatalogError.swift`（加两种错误）
- Modify: `Sources/RimeKit/Resources/catalog.json`（极点五笔加选项）
- Modify: `Tests/RimeKitTests/BuiltInCatalogTests.swift`（加一个测试）
- Test: `Tests/RimeKitTests/PackageOptionTests.swift`

**Interfaces:**
- Consumes: `Catalog`、`PackageSpec`、`CatalogError`（阶段 1）。
- Produces:
  - `public struct PackageOption: Sendable, Equatable, Codable { id, name, defaultChoice: String; choices: [OptionChoice]; func choice(_ id: String) -> OptionChoice? }`
  - `public struct OptionChoice: Sendable, Equatable, Codable { id, name: String; dependencies: [String]; generatedDicts: [GeneratedDict]; patches: [String: [String: String]] /* 方案 id → 补丁键 → 字符串值 */ }`
  - `public struct GeneratedDict: Sendable, Equatable, Codable { name: String; importTables: [ImportTable] }`
  - `public struct ImportTable: Sendable, Equatable, Codable { name: String; onlyIfPersonal: Bool /* JSON 里可省略，默认 false */ }`
  - `PackageSpec.options: [PackageOption]`（JSON 里可省略，默认空）
  - `Catalog.packageOwning(schema: String) -> PackageSpec?`
  - `CatalogError.unknownDefaultChoice(package: String, option: String)`、`CatalogError.patchForUnknownSchema(package: String, schema: String)`；选项依赖不存在时复用 `unknownDependency`。

- [ ] **Step 1: 写失败的测试 `Tests/RimeKitTests/PackageOptionTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct PackageOptionTests {
    static let json = """
    {"formatVersion":1,"packages":[
     {"id":"dicts","name":"词库","summary":"s","license":"MIT","homepage":"https://example.com/d",
      "source":{"type":"githubReleaseAsset","repo":"o/d","tag":"t","asset":"d.zip"},
      "anchor":"cn/a.dict.yaml","include":["cn/*"],"exclude":[],"requiredFiles":["cn/a.dict.yaml"],
      "schemas":[],"dependencies":[]},
     {"id":"wubi","name":"五笔","summary":"s","license":"MIT","homepage":"https://example.com/w",
      "source":{"type":"githubBranch","repo":"o/w","branch":"main"},
      "anchor":"wb.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["wb.schema.yaml"],
      "schemas":[{"id":"wb","name":"五笔","category":"wubi"},{"id":"wpy","name":"拼音","category":"pinyin"}],
      "dependencies":[],
      "options":[{"id":"pinyinDictionary","name":"拼音词库","defaultChoice":"ext","choices":[
        {"id":"builtin","name":"自带","dependencies":[],"generatedDicts":[],"patches":{}},
        {"id":"ext","name":"大词库","dependencies":["dicts"],
         "generatedDicts":[{"name":"py_ext","importTables":[{"name":"py_user","onlyIfPersonal":true},{"name":"cn/a"}]}],
         "patches":{"wpy":{"translator/dictionary":"py_ext"},"wb":{"reverse_lookup/dictionary":"py_ext"}}}
      ]}]}
    ]}
    """

    static func data(replacing old: String, with new: String) -> Data {
        precondition(json.components(separatedBy: old).count == 2, "要替换的文字必须正好出现一次：\(old)")
        return Data(json.replacingOccurrences(of: old, with: new).utf8)
    }

    @Test func 能读出选项() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        let wubi = try #require(catalog.package("wubi"))
        let option = try #require(wubi.options.first)
        #expect(option.id == "pinyinDictionary")
        #expect(option.defaultChoice == "ext")
        let ext = try #require(option.choice("ext"))
        #expect(ext.dependencies == ["dicts"])
        #expect(ext.generatedDicts.first?.importTables == [ImportTable(name: "py_user", onlyIfPersonal: true), ImportTable(name: "cn/a", onlyIfPersonal: false)])
        #expect(ext.patches["wb"] == ["reverse_lookup/dictionary": "py_ext"])
        #expect(option.choice("nope") == nil)
    }

    @Test func 没写选项的包选项为空() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        #expect(catalog.package("dicts")?.options == [])
    }

    @Test func 默认选择不存在() {
        #expect(throws: CatalogError.unknownDefaultChoice(package: "wubi", option: "pinyinDictionary")) {
            try Catalog.decode(Self.data(replacing: #""defaultChoice":"ext""#, with: #""defaultChoice":"zzz""#))
        }
    }

    @Test func 选项依赖了不存在的包() {
        #expect(throws: CatalogError.unknownDependency(package: "wubi", dependency: "nope")) {
            try Catalog.decode(Self.data(replacing: #""dependencies":["dicts"]"#, with: #""dependencies":["nope"]"#))
        }
    }

    @Test func 选项补丁写给了别的包的方案() {
        #expect(throws: CatalogError.patchForUnknownSchema(package: "wubi", schema: "other")) {
            try Catalog.decode(Self.data(replacing: #""wpy":{"translator/dictionary":"py_ext"}"#, with: #""other":{"translator/dictionary":"py_ext"}"#))
        }
    }

    @Test func 按方案找所属的包() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        #expect(catalog.packageOwning(schema: "wpy")?.id == "wubi")
        #expect(catalog.packageOwning(schema: "nope") == nil)
    }

    @Test func 编码再解码不变() throws {
        let catalog = try Catalog.decode(Data(Self.json.utf8))
        #expect(try Catalog.decode(try JSONCoding.encoder.encode(catalog)) == catalog)
    }
}
```

`Tests/RimeKitTests/BuiltInCatalogTests.swift` 里加一个测试（放进 `BuiltInCatalogTests` 结构体里）：

```swift
    @Test func 极点五笔有拼音词库选项默认用雾凇() throws {
        let wubi = try #require(try Catalog.builtIn().package("wubi86-jidian"))
        let option = try #require(wubi.options.first { $0.id == "pinyinDictionary" })
        #expect(option.defaultChoice == "rime-ice")
        let ice = try #require(option.choice("rime-ice"))
        #expect(ice.dependencies == ["rime-ice-dicts"])
        #expect(ice.generatedDicts.map(\.name) == ["pinyin_ext"])
        #expect(ice.patches["pinyin_simp"] == ["translator/dictionary": "pinyin_ext"])
        #expect(ice.patches["wubi86_jidian_pinyin"] == ["reverse_lookup/dictionary": "pinyin_ext"])
        #expect(option.choice("builtin")?.dependencies == [])
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "PackageOptionTests|BuiltInCatalogTests" 2>&1 | grep -E "error:" | head -3`
Expected: 编译失败，`value of type 'PackageSpec' has no member 'options'`。

- [ ] **Step 3: 写 `Sources/RimeKit/Catalog/PackageOption.swift`**

```swift
import Foundation

/// 包的可选项，例如极点五笔的「拼音词库」：用自带的还是雾凇大词库
public struct PackageOption: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let defaultChoice: String
    public let choices: [OptionChoice]

    public func choice(_ id: String) -> OptionChoice? {
        choices.first { $0.id == id }
    }
}

public struct OptionChoice: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    /// 选了这一项要额外用到的包
    public let dependencies: [String]
    /// 选了这一项要由应用生成的总词库
    public let generatedDicts: [GeneratedDict]
    /// 方案 id → 补丁键 → 值，写进 <方案>.custom.yaml
    public let patches: [String: [String: String]]
}

/// 只写 import_tables 的总词库，例如 pinyin_ext.dict.yaml
public struct GeneratedDict: Sendable, Equatable, Codable {
    public let name: String
    public let importTables: [ImportTable]
}

public struct ImportTable: Sendable, Equatable, Codable {
    public let name: String
    /// true：只有用户有这个名字的个人词库时才挂上
    public let onlyIfPersonal: Bool

    public init(name: String, onlyIfPersonal: Bool) {
        self.name = name
        self.onlyIfPersonal = onlyIfPersonal
    }

    private enum CodingKeys: String, CodingKey { case name, onlyIfPersonal }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        onlyIfPersonal = try c.decodeIfPresent(Bool.self, forKey: .onlyIfPersonal) ?? false
    }
}
```

- [ ] **Step 4: 改 `Catalog.swift` 里的 `PackageSpec`（整段替换成下面的）**

```swift
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
    /// 包的可选项；JSON 里可以不写
    public let options: [PackageOption]

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, license, homepage, source, anchor, include, exclude, requiredFiles, schemas, dependencies, options
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        summary = try c.decode(String.self, forKey: .summary)
        license = try c.decode(String.self, forKey: .license)
        homepage = try c.decode(URL.self, forKey: .homepage)
        source = try c.decode(PackageSource.self, forKey: .source)
        anchor = try c.decode(String.self, forKey: .anchor)
        include = try c.decode([FileGlob].self, forKey: .include)
        exclude = try c.decode([FileGlob].self, forKey: .exclude)
        requiredFiles = try c.decode([String].self, forKey: .requiredFiles)
        schemas = try c.decode([SchemaSpec].self, forKey: .schemas)
        dependencies = try c.decode([String].self, forKey: .dependencies)
        options = try c.decodeIfPresent([PackageOption].self, forKey: .options) ?? []
    }
}
```

在 `Catalog` 里 `package(_:)` 后面加：

```swift
    /// 这个方案属于哪个包
    public func packageOwning(schema: String) -> PackageSpec? {
        packages.first { $0.schemas.contains { $0.id == schema } }
    }
```

在 `validate()` 的最后（必需文件检查之后）加：

```swift
        for p in packages {
            for option in p.options {
                guard option.choice(option.defaultChoice) != nil else {
                    throw CatalogError.unknownDefaultChoice(package: p.id, option: option.id)
                }
                for choice in option.choices {
                    for d in choice.dependencies where !packageIDs.contains(d) {
                        throw CatalogError.unknownDependency(package: p.id, dependency: d)
                    }
                    for schema in choice.patches.keys.sorted() where !p.schemas.contains(where: { $0.id == schema }) {
                        throw CatalogError.patchForUnknownSchema(package: p.id, schema: schema)
                    }
                }
            }
        }
```

- [ ] **Step 5: `CatalogError.swift` 加两种错误**

在 `case builtInMissing` 后面加：

```swift
    case unknownDefaultChoice(package: String, option: String)
    case patchForUnknownSchema(package: String, schema: String)
```

在 `description` 的 `switch` 里 `case .builtInMissing` 后面加：

```swift
        case let .unknownDefaultChoice(package, option):
            return "包 \(package) 的选项 \(option) 的默认值不在可选项里"
        case let .patchForUnknownSchema(package, schema):
            return "包 \(package) 的选项要改方案 \(schema)，但这个方案不属于这个包"
```

- [ ] **Step 6: `catalog.json` 给极点五笔加选项**

在 `wubi86-jidian` 的 `"dependencies": []` 后面加（注意前面补逗号）：

```json
      "options": [
        {
          "id": "pinyinDictionary",
          "name": "拼音词库（拼音混输、拼音反查用）",
          "defaultChoice": "rime-ice",
          "choices": [
            {
              "id": "builtin",
              "name": "自带拼音词库（约 10 万词，词比较旧）",
              "dependencies": [],
              "generatedDicts": [],
              "patches": {}
            },
            {
              "id": "rime-ice",
              "name": "雾凇大词库（约 90 万词，新词多，多下载约 15 MB）",
              "dependencies": ["rime-ice-dicts"],
              "generatedDicts": [
                {
                  "name": "pinyin_ext",
                  "importTables": [
                    { "name": "pinyin_user", "onlyIfPersonal": true },
                    { "name": "cn_dicts/8105" },
                    { "name": "cn_dicts/base" },
                    { "name": "cn_dicts/ext" }
                  ]
                }
              ],
              "patches": {
                "pinyin_simp": { "translator/dictionary": "pinyin_ext" },
                "wubi86_jidian": { "reverse_lookup/dictionary": "pinyin_ext" },
                "wubi86_jidian_pinyin": { "reverse_lookup/dictionary": "pinyin_ext" },
                "wubi86_jidian_trad": { "reverse_lookup/dictionary": "pinyin_ext" },
                "wubi86_jidian_trad_pinyin": { "reverse_lookup/dictionary": "pinyin_ext" }
              }
            }
          ]
        }
      ]
```

- [ ] **Step 7: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 8 个）。

- [ ] **Step 8: 提交**

```bash
git add Sources/RimeKit/Catalog Sources/RimeKit/Resources/catalog.json Tests/RimeKitTests
git commit -m "feat: 清单加包选项；极点五笔可选拼音词库（默认雾凇）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 设置 `Settings`、读写、起步方案

**Files:**
- Modify: `Sources/RimeKit/AppPaths.swift`（加 `settingsFile`、`personal`、`personalDicts`、`personalPhrases`）
- Modify: `Tests/RimeKitTests/AppPathsTests.swift`（加断言）
- Create: `Sources/RimeKit/Config/Settings.swift`
- Create: `Sources/RimeKit/Config/SettingsStore.swift`
- Test: `Tests/RimeKitTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `Catalog.packageOwning`、`Catalog.installOrder`、`PackageOption`（任务 2）、`JSONCoding`。
- Produces:
  - `AppPaths.settingsFile`（`root/settings.json`）、`AppPaths.personal`（`root/personal`）、`AppPaths.personalDicts`（`root/personal/dicts`）、`AppPaths.personalPhrases`（`root/personal/phrases.txt`）
  - `public struct Settings: Sendable, Equatable, Codable { static let currentFormatVersion = 1; var formatVersion: Int; var schemas: [String]; var options: [String: [String: String]]; var appearance: Appearance; var textReplacement: TextReplacementSettings; var preservedPatches: [String: [PreservedPatch]]; init(schemas:options:appearance:textReplacement:preservedPatches:); func validate(_ catalog: Catalog) throws; func choice(_ option: PackageOption, of package: PackageSpec) -> OptionChoice; func requiredPackages(_ catalog: Catalog) throws -> [PackageSpec]; static func starter(_ s: Starter) -> Settings }`
  - `public struct Appearance: Sendable, Equatable, Codable { colorScheme, colorSchemeDark: String?; fontPoint, labelFontPoint, commentFontPoint: Int?; candidateListLayout: CandidateListLayout?; textOrientation: TextOrientation?; pageSize: Int? }`（都可以为空，空表示用上游默认）
  - `public enum CandidateListLayout: String { stacked, linear }`、`public enum TextOrientation: String { horizontal, vertical }`
  - `public struct TextReplacementSettings: Sendable, Equatable, Codable { var sync: Bool; var lastSyncedHash: String? }`
  - `public struct PreservedPatch: Sendable, Equatable, Codable { var key: String; var yaml: String }`（接管时认不出的补丁项；`yaml` 是这个键的值的 YAML 原文）
  - `public enum Starter: String, CaseIterable, Sendable { case rimeIce = "rime-ice", flypy, wubiPinyin = "wubi-pinyin"; var displayName: String }`
  - `public enum SettingsError: Error, Equatable, CustomStringConvertible { unsupportedFormat(Int), noSchemas, unknownSchema(String), duplicateSchema(String), unknownOption(package: String, option: String), unknownChoice(package: String, option: String, choice: String), outOfRange(field: String, value: Int, range: ClosedRange<Int>) }`
  - `public struct SettingsStore: Sendable { init(paths: AppPaths); func load() throws -> Settings? /* 没有文件返回 nil */; func save(_ s: Settings) throws }`

- [ ] **Step 1: 改 `AppPaths.swift`，在 `staging` 后面加**

```swift
    /// 用户的所有选择
    public var settingsFile: URL { root.appending(path: "settings.json") }

    /// 个人内容的正本：个人词库、手动短语
    public var personal: URL { root.appending(path: "personal", directoryHint: .isDirectory) }
    public var personalDicts: URL { personal.appending(path: "dicts", directoryHint: .isDirectory) }
    public var personalPhrases: URL { personal.appending(path: "phrases.txt") }
```

`AppPathsTests.子目录都在根目录下` 里加：

```swift
        #expect(paths.settingsFile.path == "/tmp/x/settings.json")
        #expect(paths.personalDicts.path == "/tmp/x/personal/dicts")
        #expect(paths.personalPhrases.path == "/tmp/x/personal/phrases.txt")
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/SettingsTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct SettingsTests {
    func catalog() throws -> Catalog { try Catalog.decode(Data(PackageOptionTests.json.utf8)) }

    @Test func 合法的设置通过校验() throws {
        var s = Settings(schemas: ["wb", "wpy"])
        s.appearance.fontPoint = 24
        s.appearance.pageSize = 7
        try s.validate(try catalog())
    }

    @Test func 各种不合法的设置() throws {
        let c = try catalog()
        #expect(throws: SettingsError.noSchemas) { try Settings(schemas: []).validate(c) }
        #expect(throws: SettingsError.unknownSchema("nope")) { try Settings(schemas: ["nope"]).validate(c) }
        #expect(throws: SettingsError.duplicateSchema("wb")) { try Settings(schemas: ["wb", "wb"]).validate(c) }
        #expect(throws: SettingsError.unknownOption(package: "wubi", option: "x")) {
            try Settings(schemas: ["wb"], options: ["wubi": ["x": "y"]]).validate(c)
        }
        #expect(throws: SettingsError.unknownChoice(package: "wubi", option: "pinyinDictionary", choice: "zzz")) {
            try Settings(schemas: ["wb"], options: ["wubi": ["pinyinDictionary": "zzz"]]).validate(c)
        }
        var big = Settings(schemas: ["wb"])
        big.appearance.fontPoint = 100
        #expect(throws: SettingsError.outOfRange(field: "候选字字号", value: 100, range: 8...72)) { try big.validate(c) }
        var page = Settings(schemas: ["wb"])
        page.appearance.pageSize = 0
        #expect(throws: SettingsError.outOfRange(field: "每页候选数", value: 0, range: 1...10)) { try page.validate(c) }
        var old = Settings(schemas: ["wb"])
        old.formatVersion = 9
        #expect(throws: SettingsError.unsupportedFormat(9)) { try old.validate(c) }
    }

    @Test func 没选的选项用默认值() throws {
        let c = try catalog()
        let wubi = try #require(c.package("wubi"))
        let option = try #require(wubi.options.first)
        #expect(Settings(schemas: ["wb"]).choice(option, of: wubi).id == "ext")
        #expect(Settings(schemas: ["wb"], options: ["wubi": ["pinyinDictionary": "builtin"]]).choice(option, of: wubi).id == "builtin")
    }

    @Test func 要用到的包包括选项的依赖() throws {
        let c = try catalog()
        #expect(try Settings(schemas: ["wb"]).requiredPackages(c).map(\.id) == ["dicts", "wubi"])
        #expect(try Settings(schemas: ["wb"], options: ["wubi": ["pinyinDictionary": "builtin"]]).requiredPackages(c).map(\.id) == ["wubi"])
    }

    @Test func 起步方案都能通过内置清单的校验() throws {
        let c = try Catalog.builtIn()
        for starter in Starter.allCases {
            try Settings.starter(starter).validate(c)
        }
        #expect(Settings.starter(.rimeIce).schemas == ["rime_ice"])
        #expect(Settings.starter(.flypy).schemas == ["double_pinyin_flypy"])
        #expect(Settings.starter(.wubiPinyin).schemas.first == "wubi86_jidian_pinyin")
        #expect(try Settings.starter(.wubiPinyin).requiredPackages(c).map(\.id) == ["rime-ice-dicts", "wubi86-jidian"])
    }

    @Test func 存进去再读出来不变() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let store = SettingsStore(paths: Fixtures.paths(dir))
        #expect(try store.load() == nil)
        var s = Settings.starter(.wubiPinyin)
        s.appearance.fontPoint = 24
        s.appearance.candidateListLayout = .linear
        s.preservedPatches = ["default": [PreservedPatch(key: "key_binder/bindings", yaml: "[]")]]
        try store.save(s)
        #expect(try store.load() == s)
    }

    @Test func 读到不认识的格式版本() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":9}"#.utf8).write(to: paths.settingsFile)
        #expect(throws: SettingsError.unsupportedFormat(9)) { try SettingsStore(paths: paths).load() }
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter SettingsTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'Settings' in scope`。

- [ ] **Step 4: 写 `Sources/RimeKit/Config/Settings.swift`**

```swift
import Foundation

/// 用户在应用里做的所有选择（设计第 5 节）
public struct Settings: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// 启用的方案，按顺序；第一个是默认方案
    public var schemas: [String]
    /// 包 id → 选项 id → 选的哪一项；没写的用清单里的默认值
    public var options: [String: [String: String]]
    public var appearance: Appearance
    public var textReplacement: TextReplacementSettings
    /// 接管时认不出的补丁项，按文件名（不带 .custom.yaml）存，生成时原样写回
    public var preservedPatches: [String: [PreservedPatch]]

    public init(
        schemas: [String],
        options: [String: [String: String]] = [:],
        appearance: Appearance = Appearance(),
        textReplacement: TextReplacementSettings = TextReplacementSettings(),
        preservedPatches: [String: [PreservedPatch]] = [:]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.schemas = schemas
        self.options = options
        self.appearance = appearance
        self.textReplacement = textReplacement
        self.preservedPatches = preservedPatches
    }

    public func validate(_ catalog: Catalog) throws {
        guard formatVersion == Self.currentFormatVersion else { throw SettingsError.unsupportedFormat(formatVersion) }
        guard !schemas.isEmpty else { throw SettingsError.noSchemas }
        var seen = Set<String>()
        for schema in schemas {
            guard seen.insert(schema).inserted else { throw SettingsError.duplicateSchema(schema) }
            guard catalog.packageOwning(schema: schema) != nil else { throw SettingsError.unknownSchema(schema) }
        }
        for (packageID, chosen) in options.sorted(by: { $0.key < $1.key }) {
            let package = catalog.package(packageID)
            for (optionID, choiceID) in chosen.sorted(by: { $0.key < $1.key }) {
                guard let option = package?.options.first(where: { $0.id == optionID }) else {
                    throw SettingsError.unknownOption(package: packageID, option: optionID)
                }
                guard option.choice(choiceID) != nil else {
                    throw SettingsError.unknownChoice(package: packageID, option: optionID, choice: choiceID)
                }
            }
        }
        try Self.check("候选字字号", appearance.fontPoint, 8...72)
        try Self.check("序号字号", appearance.labelFontPoint, 8...72)
        try Self.check("注释字号", appearance.commentFontPoint, 8...72)
        try Self.check("每页候选数", appearance.pageSize, 1...10)
    }

    /// 这个包的这个选项现在选的是哪一项（没选就是默认值）
    public func choice(_ option: PackageOption, of package: PackageSpec) -> OptionChoice {
        let id = options[package.id]?[option.id] ?? option.defaultChoice
        return option.choice(id) ?? option.choice(option.defaultChoice) ?? option.choices[0]
    }

    /// 要用到的包：启用的方案所属的包 + 所选选项的依赖；依赖（包括选项的依赖）在前
    public func requiredPackages(_ catalog: Catalog) throws -> [PackageSpec] {
        var ids: [String] = []
        for schema in schemas {
            guard let package = catalog.packageOwning(schema: schema) else { throw SettingsError.unknownSchema(schema) }
            if !ids.contains(package.id) { ids.append(package.id) }
        }
        var optionDependencies: [String] = []
        for id in ids {
            guard let package = catalog.package(id) else { continue }
            for option in package.options {
                for d in choice(option, of: package).dependencies where !optionDependencies.contains(d) {
                    optionDependencies.append(d)
                }
            }
        }
        return try catalog.installOrder(for: optionDependencies + ids)
    }

    /// 起步方案（设计 6.2：~/Library/Rime 是空的时候让用户选一个）
    public static func starter(_ starter: Starter) -> Settings {
        switch starter {
        case .rimeIce:
            return Settings(schemas: ["rime_ice"])
        case .flypy:
            return Settings(schemas: ["double_pinyin_flypy"])
        case .wubiPinyin:
            return Settings(
                schemas: ["wubi86_jidian_pinyin", "wubi86_jidian", "numbers",
                          "wubi86_jidian_trad", "wubi86_jidian_trad_pinyin", "pinyin_simp"],
                options: ["wubi86-jidian": ["pinyinDictionary": "rime-ice"]])
        }
    }

    private static func check(_ field: String, _ value: Int?, _ range: ClosedRange<Int>) throws {
        if let value, !range.contains(value) { throw SettingsError.outOfRange(field: field, value: value, range: range) }
    }
}

public struct Appearance: Sendable, Equatable, Codable {
    public var colorScheme: String?
    public var colorSchemeDark: String?
    public var fontPoint: Int?
    public var labelFontPoint: Int?
    public var commentFontPoint: Int?
    public var candidateListLayout: CandidateListLayout?
    public var textOrientation: TextOrientation?
    public var pageSize: Int?

    public init(
        colorScheme: String? = nil, colorSchemeDark: String? = nil,
        fontPoint: Int? = nil, labelFontPoint: Int? = nil, commentFontPoint: Int? = nil,
        candidateListLayout: CandidateListLayout? = nil, textOrientation: TextOrientation? = nil,
        pageSize: Int? = nil
    ) {
        self.colorScheme = colorScheme
        self.colorSchemeDark = colorSchemeDark
        self.fontPoint = fontPoint
        self.labelFontPoint = labelFontPoint
        self.commentFontPoint = commentFontPoint
        self.candidateListLayout = candidateListLayout
        self.textOrientation = textOrientation
        self.pageSize = pageSize
    }
}

public enum CandidateListLayout: String, Sendable, Equatable, Codable {
    case stacked, linear
}

public enum TextOrientation: String, Sendable, Equatable, Codable {
    case horizontal, vertical
}

public struct TextReplacementSettings: Sendable, Equatable, Codable {
    public var sync: Bool
    /// 上次同步时文本替换内容的哈希（只存哈希，不存内容）
    public var lastSyncedHash: String?

    public init(sync: Bool = false, lastSyncedHash: String? = nil) {
        self.sync = sync
        self.lastSyncedHash = lastSyncedHash
    }
}

public struct PreservedPatch: Sendable, Equatable, Codable {
    public var key: String
    /// 这个键的值的 YAML 原文
    public var yaml: String

    public init(key: String, yaml: String) {
        self.key = key
        self.yaml = yaml
    }
}

public enum Starter: String, CaseIterable, Sendable {
    case rimeIce = "rime-ice"
    case flypy
    case wubiPinyin = "wubi-pinyin"

    public var displayName: String {
        switch self {
        case .rimeIce: return "雾凇拼音（全拼）"
        case .flypy: return "小鹤双拼"
        case .wubiPinyin: return "五笔 + 拼音混输"
        }
    }
}

public enum SettingsError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormat(Int)
    case noSchemas
    case unknownSchema(String)
    case duplicateSchema(String)
    case unknownOption(package: String, option: String)
    case unknownChoice(package: String, option: String, choice: String)
    case outOfRange(field: String, value: Int, range: ClosedRange<Int>)

    public var description: String {
        switch self {
        case .unsupportedFormat(let v):
            return "设置文件的格式版本是 \(v)，这个版本的应用只认识 \(Settings.currentFormatVersion)，请更新应用"
        case .noSchemas:
            return "至少要启用一个输入方案"
        case .unknownSchema(let id):
            return "方案清单里没有这个方案：\(id)"
        case .duplicateSchema(let id):
            return "方案 \(id) 重复启用了"
        case let .unknownOption(package, option):
            return "包 \(package) 没有选项 \(option)"
        case let .unknownChoice(package, option, choice):
            return "包 \(package) 的选项 \(option) 没有「\(choice)」这一项"
        case let .outOfRange(field, value, range):
            return "\(field)是 \(value)，应该在 \(range.lowerBound) 到 \(range.upperBound) 之间"
        }
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Config/SettingsStore.swift`**

```swift
import Foundation

/// 读写 settings.json
public struct SettingsStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    /// 还没有设置文件时返回 nil。先只读格式版本号，版本不对就不往下解析。
    public func load() throws -> Settings? {
        guard FileManager.default.fileExists(atPath: paths.settingsFile.path) else { return nil }
        let data = try Data(contentsOf: paths.settingsFile)
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONCoding.decoder.decode(Header.self, from: data)
        guard header.formatVersion == Settings.currentFormatVersion else {
            throw SettingsError.unsupportedFormat(header.formatVersion)
        }
        return try JSONCoding.decoder.decode(Settings.self, from: data)
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(settings).write(to: paths.settingsFile, options: .atomic)
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 7 个）。

- [ ] **Step 7: 提交**

```bash
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 设置 Settings（校验、起步方案、要用到的包）和 settings.json 读写

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 个人内容和短语

**Files:**
- Create: `Sources/RimeKit/Config/Personal.swift`
- Test: `Tests/RimeKitTests/PersonalTests.swift`

**Interfaces:**
- Consumes: `AppPaths.personalDicts`、`AppPaths.personalPhrases`（任务 3）。
- Produces:
  - `public struct Phrase: Sendable, Equatable, Codable { text, code: String; weight: Int?; init(text:code:weight:); var line: String /* 短语<Tab>编码[<Tab>权重] */ }`
  - `public enum PhraseFile { static let header: String; static func parse(_ text: String) -> [Phrase]; static func render(_ phrases: [Phrase]) -> String }`
  - `public struct PersonalContent: Sendable, Equatable { var dicts: [URL]; var phrases: [Phrase]; init(dicts:phrases:); static let empty; static func load(from paths: AppPaths) throws -> PersonalContent; func hasDict(named: String) -> Bool }`

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct PersonalTests {
    @Test func 读短语文件() {
        let text = "# 注释\n\n测试短语\ttstx\t1\n没有权重\tmyqz\n坏行\n\t空短语\n"
        #expect(PhraseFile.parse(text) == [
            Phrase(text: "测试短语", code: "tstx", weight: 1),
            Phrase(text: "没有权重", code: "myqz", weight: nil),
        ])
    }

    @Test func 写短语文件() {
        let text = PhraseFile.render([Phrase(text: "甲", code: "a", weight: 1), Phrase(text: "乙", code: "b", weight: nil)])
        #expect(text == "甲\ta\t1\n乙\tb\n")
    }

    @Test func 读个人内容() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: paths.personalDicts.appending(path: "py_user.dict.yaml"))
        try Data("x".utf8).write(to: paths.personalDicts.appending(path: "readme.txt"))
        try Data("甲\ta\t1\n".utf8).write(to: paths.personalPhrases)
        let content = try PersonalContent.load(from: paths)
        #expect(content.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml"])
        #expect(content.phrases == [Phrase(text: "甲", code: "a", weight: 1)])
        #expect(content.hasDict(named: "py_user"))
        #expect(!content.hasDict(named: "wb_user"))
    }

    @Test func 没有个人内容时是空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try PersonalContent.load(from: Fixtures.paths(dir)) == .empty)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PersonalTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'PhraseFile' in scope`。

- [ ] **Step 3: 实现 `Sources/RimeKit/Config/Personal.swift`**

```swift
import Foundation

/// 一条自定义短语：打 code 时，text 排在候选第一位
public struct Phrase: Sendable, Equatable, Codable {
    public var text: String
    public var code: String
    public var weight: Int?

    public init(text: String, code: String, weight: Int?) {
        self.text = text
        self.code = code
        self.weight = weight
    }

    /// Rime 短语文件里的一行：短语<Tab>编码[<Tab>权重]
    public var line: String {
        weight.map { "\(text)\t\(code)\t\($0)" } ?? "\(text)\t\(code)"
    }
}

/// custom_phrase.txt 这类短语文件的读写
public enum PhraseFile {
    public static let header = """
    # Rime table
    # coding: utf-8
    # 由 squirrel-macos 生成的自定义短语。格式：短语<Tab>编码<Tab>权重

    """

    /// 跳过空行、注释和格式不对的行
    public static func parse(_ text: String) -> [Phrase] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw)
            if line.hasPrefix("#") { return nil }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            let weight = fields.count >= 3 ? Int(fields[2]) : nil
            return Phrase(text: fields[0], code: fields[1], weight: weight)
        }
    }

    public static func render(_ phrases: [Phrase]) -> String {
        phrases.map { $0.line + "\n" }.joined()
    }
}

/// 个人内容的正本（personal/ 目录）：个人词库和手动短语
public struct PersonalContent: Sendable, Equatable {
    /// personal/dicts/ 下的 *.dict.yaml，按文件名排序
    public var dicts: [URL]
    /// personal/phrases.txt 里的手动短语
    public var phrases: [Phrase]

    public init(dicts: [URL], phrases: [Phrase]) {
        self.dicts = dicts
        self.phrases = phrases
    }

    public static let empty = PersonalContent(dicts: [], phrases: [])

    public static func load(from paths: AppPaths) throws -> PersonalContent {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: paths.personalDicts.path)) ?? []
        let dicts = names.filter { $0.hasSuffix(".dict.yaml") }.sorted()
            .map { paths.personalDicts.appending(path: $0) }
        var phrases: [Phrase] = []
        if fm.fileExists(atPath: paths.personalPhrases.path) {
            phrases = PhraseFile.parse(try String(contentsOf: paths.personalPhrases, encoding: .utf8))
        }
        return PersonalContent(dicts: dicts, phrases: phrases)
    }

    /// 有没有叫这个名字的个人词库（文件名是 <名字>.dict.yaml）
    public func hasDict(named name: String) -> Bool {
        dicts.contains { $0.lastPathComponent == "\(name).dict.yaml" }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PersonalTests 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 4 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Config/Personal.swift Tests/RimeKitTests/PersonalTests.swift
git commit -m "feat: 个人内容和短语文件的读写

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 生成器骨架：复制上游文件、上游补丁、方案列表、保留的补丁

**Files:**
- Create: `Tests/RimeKitTests/Support/GenFixtures.swift`
- Create: `Sources/RimeKit/Config/ConfigGenerator.swift`
- Create: `Sources/RimeKit/Config/GenerationContext.swift`
- Test: `Tests/RimeKitTests/GeneratorBasicsTests.swift`

**Interfaces:**
- Consumes: `Settings`、`requiredPackages`（任务 3）、`PersonalContent`、`Phrase`（任务 4）、`Patch`、`YAMLNode`（任务 1）、`CachedPackage`、`PackageInfo`、`PackageStore.rulesFingerprint`（阶段 1）。
- Produces:
  - `public struct GenerationInput: Sendable { var settings: Settings; var catalog: Catalog; var packages: [String: CachedPackage]; var personal: PersonalContent; var textReplacementPhrases: [Phrase]; init(...) }`
  - `public enum FileOrigin: Sendable, Equatable { case package(String), generated, personal }`
  - `public struct GeneratedFile: Sendable, Equatable { path: String; origin: FileOrigin }`
  - `public struct GenerationResult: Sendable, Equatable { files: [GeneratedFile] /* 按路径排序 */; warnings: [String] }`
  - `public enum GenerationError: Error, Equatable, CustomStringConvertible { outputNotEmpty(String), missingPackage(String), badYAML(file: String, message: String) }`
  - `public struct ConfigGenerator: Sendable { init(); func generate(_ input: GenerationInput, into output: URL) throws -> GenerationResult }`
  - 内部 `final class GenerationContext`：后面任务往里加步骤。
  - 测试辅助 `GenFixtures`：`catalogJSON`、`catalog()`、`makePackages(in root: URL, extra: [String: [String: String]] = [:]) throws -> [String: CachedPackage]`（每个包写成 `root/<id>@v1/files/…` 加 `package.json`，正好也是缓存目录的格式）、`input(_ settings:, packages:, personal:, textReplacement:) throws -> GenerationInput`、`read(_ out: URL, _ path: String) throws -> String`、`patch(_ out: URL, _ name: String) throws -> Patch`

- [ ] **Step 1: 写测试辅助 `Tests/RimeKitTests/Support/GenFixtures.swift`**

三个自造的包，内容是能真的被 `rime_deployer` 编译的最小 Rime 方案（任务 9 会编译它们）：
- `pinyin`：方案 `py`（自带短语翻译器，用 `custom_phrase.txt`）、`sp`（用 `custom_phrase_double.txt`），带上游短语文件、`squirrel.yaml`（配色 `aqua`）、`LICENSE`。
- `words`：只有词库 `cn/a.dict.yaml`。
- `wubi`：方案 `wb`、`wb_py`（没有短语翻译器）、`wpy`（拼音）；上游补丁 `default.custom.yaml`（方案列表、`menu`、`key_binder`）和 `squirrel.custom.yaml`（配色 `roseo`/`roseo_dark`，配色里写了字号）；词库模板 `wb_user.dict.yaml`；选项「拼音词库」默认 `ext`（依赖 `words`，生成 `py_ext`）。

```swift
import Foundation
@testable import RimeKit

/// 给生成器用的三个自造包。内容是能被 rime_deployer 编译的最小方案。
enum GenFixtures {
    static let catalogJSON = """
    {"formatVersion":1,"packages":[
     {"id":"pinyin","name":"测试拼音","summary":"s","license":"MIT","homepage":"https://example.com/p",
      "source":{"type":"githubReleaseAsset","repo":"o/p","tag":"t","asset":"p.zip"},
      "anchor":"py.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["py.schema.yaml"],
      "schemas":[{"id":"py","name":"拼音","category":"pinyin"},{"id":"sp","name":"双拼","category":"shuangpin"}],
      "dependencies":[]},
     {"id":"words","name":"词库","summary":"s","license":"MIT","homepage":"https://example.com/w",
      "source":{"type":"githubReleaseAsset","repo":"o/w","tag":"t","asset":"w.zip"},
      "anchor":"cn/a.dict.yaml","include":["cn/*"],"exclude":[],"requiredFiles":["cn/a.dict.yaml"],
      "schemas":[],"dependencies":[]},
     {"id":"wubi","name":"测试五笔","summary":"s","license":"MIT","homepage":"https://example.com/wb",
      "source":{"type":"githubBranch","repo":"o/wb","branch":"main"},
      "anchor":"wb.schema.yaml","include":["*"],"exclude":[],"requiredFiles":["wb.schema.yaml"],
      "schemas":[{"id":"wb","name":"五笔","category":"wubi"},{"id":"wb_py","name":"五笔拼音","category":"wubi"},{"id":"wpy","name":"五笔里的拼音","category":"pinyin"}],
      "dependencies":[],
      "options":[{"id":"pinyinDictionary","name":"拼音词库","defaultChoice":"ext","choices":[
        {"id":"builtin","name":"自带","dependencies":[],"generatedDicts":[],"patches":{}},
        {"id":"ext","name":"大词库","dependencies":["words"],
         "generatedDicts":[{"name":"py_ext","importTables":[{"name":"py_user","onlyIfPersonal":true},{"name":"cn/a"}]}],
         "patches":{"wpy":{"translator/dictionary":"py_ext"},"wb":{"reverse_lookup/dictionary":"py_ext"},"wb_py":{"reverse_lookup/dictionary":"py_ext"}}}
      ]}]}
    ]}
    """

    static func catalog() throws -> Catalog {
        try Catalog.decode(Data(catalogJSON.utf8))
    }

    static func pinyinSchema(id: String, name: String, dictionary: String, phraseFile: String?) -> String {
        let translators = phraseFile == nil
            ? "    - table_translator"
            : "    - table_translator@custom_phrase\n    - table_translator"
        let phrase = phraseFile.map {
            "custom_phrase:\n  dictionary: \"\"\n  user_dict: \($0)\n  db_class: stabledb\n  enable_completion: false\n  enable_sentence: false\n  initial_quality: 99\n"
        } ?? ""
        return """
        schema:
          schema_id: \(id)
          name: \(name)
          version: "1"
        engine:
          processors:
            - ascii_composer
            - key_binder
            - speller
            - selector
            - navigator
            - express_editor
          segmentors:
            - ascii_segmentor
            - abc_segmentor
            - fallback_segmentor
          translators:
        \(translators)
        speller:
          alphabet: zyxwvutsrqponmlkjihgfedcba
          delimiter: " '"
        translator:
          dictionary: \(dictionary)
          enable_sentence: false

        """ + phrase
    }

    static func wubiSchema(id: String) -> String {
        """
        schema:
          schema_id: \(id)
          name: 测试五笔 \(id)
          version: "1"
          dependencies:
            - wpy
        engine:
          processors:
            - ascii_composer
            - key_binder
            - speller
            - selector
            - navigator
            - express_editor
          segmentors:
            - ascii_segmentor
            - abc_segmentor
            - fallback_segmentor
          translators:
            - table_translator
            - reverse_lookup_translator
        speller:
          alphabet: zyxwvutsrqponmlkjihgfedcba
        translator:
          dictionary: wb
          enable_sentence: false
        reverse_lookup:
          dictionary: wpy
          prefix: "z"
          tips: "〔拼音〕"

        """
    }

    static func dict(_ name: String, _ entries: [String]) -> String {
        "---\nname: \(name)\nversion: \"1\"\nsort: by_weight\n...\n" + entries.map { $0 + "\n" }.joined()
    }

    static let files: [String: [String: String]] = [
        "pinyin": [
            "py.schema.yaml": pinyinSchema(id: "py", name: "测试拼音", dictionary: "py", phraseFile: "custom_phrase"),
            "sp.schema.yaml": pinyinSchema(id: "sp", name: "测试双拼", dictionary: "py", phraseFile: "custom_phrase_double"),
            "py.dict.yaml": dict("py", ["你\tni\t100", "好\thao\t100", "你好\tni hao\t1000"]),
            "custom_phrase.txt": "# Rime table\n#@/db_name\tcustom_phrase.txt\n#@/db_type\ttabledb\n#\n上游短语\tsy\t1\n",
            "squirrel.yaml": "style:\n  color_scheme: aqua\n  font_point: 16\npreset_color_schemes:\n  aqua:\n    name: 碧水\n",
            "LICENSE": "MIT\n",
        ],
        "words": [
            "cn/a.dict.yaml": dict("a", ["你好\tni hao\t5000", "大词库\tda ci ku\t100"]),
        ],
        "wubi": [
            "wb.schema.yaml": wubiSchema(id: "wb"),
            "wb_py.schema.yaml": wubiSchema(id: "wb_py"),
            "wpy.schema.yaml": pinyinSchema(id: "wpy", name: "五笔里的拼音", dictionary: "wpy", phraseFile: nil),
            "wb.dict.yaml": dict("wb", ["一\tg\t100", "工\ta\t100"]),
            "wpy.dict.yaml": dict("wpy", ["拼\tpin\t1"]),
            "wb_user.dict.yaml": dict("wb_user", []),
            "default.custom.yaml": """
            patch:
              schema_list:
                - schema: wb
                - schema: wb_py
              menu:
                page_size: 5
              key_binder:
                bindings:
                  - { when: has_menu, accept: bracketleft, send: Page_Up }

            """,
            "squirrel.custom.yaml": """
            patch:
              style:
                color_scheme: roseo
                color_scheme_dark: roseo_dark
              preset_color_schemes:
                roseo:
                  name: 玫枫
                  font_point: 18
                  label_font_point: 17
                roseo_dark:
                  name: 玫枫暗
                  font_point: 18

            """,
            "LICENSE": "MIT\n",
        ],
    ]

    /// 把三个包写成缓存目录的格式：root/<id>@v1/{package.json, files/…}。
    /// extra：再往某个包里加文件（包 id → 路径 → 内容）
    static func makePackages(in root: URL, extra: [String: [String: String]] = [:]) throws -> [String: CachedPackage] {
        let fm = FileManager.default
        let catalog = try catalog()
        var result: [String: CachedPackage] = [:]
        for (id, baseFiles) in files {
            guard let spec = catalog.package(id) else { fatalError("清单里没有 \(id)") }
            let all = baseFiles.merging(extra[id] ?? [:]) { _, new in new }
            let dir = root.appending(path: PackageStore.directoryName(id: id, version: "v1"), directoryHint: .isDirectory)
            let filesDir = dir.appending(path: "files", directoryHint: .isDirectory)
            for (path, text) in all {
                let url = filesDir.appending(path: path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            let info = PackageInfo(id: id, version: "v1", sourceURL: URL(string: "https://example.com/\(id).zip")!,
                                   zipSHA256: String(repeating: "0", count: 64), fetchedAt: Date(timeIntervalSince1970: 1_000),
                                   files: all.keys.sorted(), rules: PackageStore.rulesFingerprint(spec))
            try JSONCoding.encoder.encode(info).write(to: dir.appending(path: "package.json"))
            result[id] = CachedPackage(info: info, filesDirectory: filesDir)
        }
        return result
    }

    static func input(
        _ settings: Settings,
        packages: [String: CachedPackage],
        personal: PersonalContent = .empty,
        textReplacement: [Phrase] = []
    ) throws -> GenerationInput {
        GenerationInput(settings: settings, catalog: try catalog(), packages: packages,
                        personal: personal, textReplacementPhrases: textReplacement)
    }

    static func read(_ out: URL, _ path: String) throws -> String {
        try String(contentsOf: out.appending(path: path), encoding: .utf8)
    }

    static func patch(_ out: URL, _ name: String) throws -> Patch {
        try Patch.parse(customYAML: read(out, "\(name).custom.yaml"))
    }

    static func exists(_ out: URL, _ path: String) -> Bool {
        FileManager.default.fileExists(atPath: out.appending(path: path).path)
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/GeneratorBasicsTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorBasicsTests {
    let builtinDict = ["wubi": ["pinyinDictionary": "builtin"]]

    @Test func 复制上游文件但不复制上游补丁和许可证() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "py"], options: builtinDict), packages: packages), into: out)

        #expect(GenFixtures.exists(out, "py.schema.yaml"))
        #expect(GenFixtures.exists(out, "wb.dict.yaml"))
        #expect(!GenFixtures.exists(out, "LICENSE"))
        #expect(!GenFixtures.exists(out, "cn/a.dict.yaml"))   // 选了自带词库，不需要 words
        #expect(result.files.contains(GeneratedFile(path: "wb.dict.yaml", origin: .package("wubi"))))
        #expect(result.files.contains(GeneratedFile(path: "default.custom.yaml", origin: .generated)))
        #expect(result.files.map(\.path) == result.files.map(\.path).sorted())
        #expect(result.warnings.isEmpty)
    }

    @Test func 方案列表按设置的顺序并保留上游的其它补丁() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        var settings = Settings(schemas: ["py", "wb"], options: builtinDict)
        settings.appearance.pageSize = 7
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)

        let p = try GenFixtures.patch(out, "default")
        #expect(p.entries.map(\.key) == ["menu", "key_binder", "schema_list", "menu/page_size"])
        #expect(p["schema_list"]?.sequence?.compactMap { $0["schema"]?.string } == ["py", "wb"])
        #expect(p["menu/page_size"]?.string == "7")
        #expect(p["key_binder"]?["bindings"]?.sequence?.count == 1)
        #expect(try GenFixtures.read(out, "default.custom.yaml").hasPrefix(Patch.header))
    }

    @Test func 保留的补丁在上游之后应用管理的键之前() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        var settings = Settings(schemas: ["wb"], options: builtinDict)
        settings.preservedPatches = ["default": [
            PreservedPatch(key: "key_binder/bindings/@next", yaml: "{when: has_menu, accept: minus, send: Page_Up}"),
            PreservedPatch(key: "schema_list", yaml: "[{schema: old}]"),
        ]]
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)

        let p = try GenFixtures.patch(out, "default")
        #expect(p.entries.map(\.key) == ["menu", "key_binder", "key_binder/bindings/@next", "schema_list"])
        #expect(p["key_binder/bindings/@next"]?["accept"]?.string == "minus")
        #expect(p["schema_list"]?.sequence?.compactMap { $0["schema"]?.string } == ["wb"])   // 应用管理的键覆盖保留的
    }

    @Test func 输出目录不是空的就拒绝() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: out.appending(path: "old.txt"))
        #expect(throws: GenerationError.outputNotEmpty(out.path)) {
            try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages), into: out)
        }
    }

    @Test func 缺包就报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        packages["words"] = nil
        #expect(throws: GenerationError.missingPackage("words")) {
            try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages),
                                           into: dir.url.appending(path: "out"))
        }
    }

    @Test func 两个包有同一个文件而且内容不同时提醒() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"),
                                                    extra: ["pinyin": ["shared.yaml": "a: 1\n"], "wubi": ["shared.yaml": "a: 2\n"]])
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["py", "wb"], options: builtinDict), packages: packages), into: out)
        #expect(try GenFixtures.read(out, "shared.yaml") == "a: 2\n")   // 安装顺序里后面的包覆盖前面的
        #expect(result.warnings == ["shared.yaml 在好几个包里都有而且内容不一样，用的是 wubi 的"])
        #expect(result.files.contains(GeneratedFile(path: "shared.yaml", origin: .package("wubi"))))
    }

    @Test func 上游补丁写坏了报出是哪个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"),
                                                    extra: ["wubi": ["default.custom.yaml": "patch:\n  a: [1, 2\n"]])
        let error = #expect(throws: GenerationError.self) {
            try ConfigGenerator().generate(try GenFixtures.input(Settings(schemas: ["wb"], options: builtinDict), packages: packages),
                                           into: dir.url.appending(path: "out"))
        }
        guard case .badYAML(let file, _) = error else {
            Issue.record("应该是 badYAML，实际是 \(String(describing: error))")
            return
        }
        #expect(file == "wubi/default.custom.yaml")
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter GeneratorBasicsTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'ConfigGenerator' in scope`（或 `GenerationInput`）。

- [ ] **Step 4: 写 `Sources/RimeKit/Config/ConfigGenerator.swift`**

```swift
import Foundation

public struct GenerationInput: Sendable {
    public var settings: Settings
    public var catalog: Catalog
    /// 包 id → 缓存
    public var packages: [String: CachedPackage]
    public var personal: PersonalContent
    /// 从 macOS 文本替换生成的短语（阶段 7 接上；现在传空）
    public var textReplacementPhrases: [Phrase]

    public init(settings: Settings, catalog: Catalog, packages: [String: CachedPackage],
                personal: PersonalContent, textReplacementPhrases: [Phrase]) {
        self.settings = settings
        self.catalog = catalog
        self.packages = packages
        self.personal = personal
        self.textReplacementPhrases = textReplacementPhrases
    }
}

public enum FileOrigin: Sendable, Equatable {
    case package(String)
    case generated
    case personal
}

public struct GeneratedFile: Sendable, Equatable {
    public let path: String
    public let origin: FileOrigin
}

public struct GenerationResult: Sendable, Equatable {
    /// 写出的所有文件，按路径排序（阶段 3 记进 ledger）
    public let files: [GeneratedFile]
    public let warnings: [String]
}

public enum GenerationError: Error, Equatable, Sendable, CustomStringConvertible {
    case outputNotEmpty(String)
    case missingPackage(String)
    case badYAML(file: String, message: String)

    public var description: String {
        switch self {
        case .outputNotEmpty(let path):
            return "输出目录不是空的：\(path)。生成配置只往空目录里写"
        case .missingPackage(let id):
            return "缺少包 \(id)，请先下载"
        case let .badYAML(file, message):
            return "读不懂 \(file)：\(message)"
        }
    }
}

/// 设置 + 上游包 + 个人内容 → 一份完整的 Rime 用户目录。
/// 只往一个空目录里写；规则见阶段 2 计划「生成规则」一节和设计文档。
public struct ConfigGenerator: Sendable {
    public init() {}

    public func generate(_ input: GenerationInput, into output: URL) throws -> GenerationResult {
        try input.settings.validate(input.catalog)
        let context = try GenerationContext(input: input, output: output)
        try context.copyPackageFiles()
        try context.collectUpstreamPatches()
        try context.applyPreservedPatches()
        context.applySchemaList()
        try context.writePatches()
        return context.result()
    }
}
```

- [ ] **Step 5: 写 `Sources/RimeKit/Config/GenerationContext.swift`**

```swift
import Foundation
import Yams

/// 一次生成的过程和中间状态
final class GenerationContext {
    let input: GenerationInput
    let output: URL
    let required: [PackageSpec]
    private let fm = FileManager.default
    private var files: [String: FileOrigin] = [:]
    private(set) var warnings: [String] = []
    /// 配置名（default、squirrel、方案 id）→ 补丁
    var patches: [String: Patch] = [:]

    init(input: GenerationInput, output: URL) throws {
        self.input = input
        self.output = output
        if fm.fileExists(atPath: output.path) {
            guard try fm.contentsOfDirectory(atPath: output.path).isEmpty else {
                throw GenerationError.outputNotEmpty(output.path)
            }
        }
        required = try input.settings.requiredPackages(input.catalog)
        for spec in required where input.packages[spec.id] == nil {
            throw GenerationError.missingPackage(spec.id)
        }
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
    }

    func result() -> GenerationResult {
        GenerationResult(
            files: files.keys.sorted().map { GeneratedFile(path: $0, origin: files[$0]!) },
            warnings: warnings)
    }

    // MARK: 写文件

    func write(_ text: String, to path: String, origin: FileOrigin) throws {
        let url = output.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        files[path] = origin
    }

    func copy(_ source: URL, to path: String, origin: FileOrigin) throws {
        let target = output.appending(path: path)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
        files[path] = origin
    }

    func readYAML(_ path: String, label: String) throws -> Node? {
        let url = output.appending(path: path)
        guard fm.fileExists(atPath: url.path) else { return nil }
        do {
            return try YAMLNode.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw GenerationError.badYAML(file: label, message: String(describing: error))
        }
    }

    // MARK: 规则 2：复制上游文件

    static func isUpstreamPatch(_ path: String) -> Bool {
        !path.contains("/") && path.hasSuffix(".custom.yaml")
    }

    func copyPackageFiles() throws {
        for spec in required {
            let package = input.packages[spec.id]!
            for path in package.info.files where !Self.isUpstreamPatch(path) && path != "LICENSE" {
                let source = package.filesDirectory.appending(path: path)
                let target = output.appending(path: path)
                if fm.fileExists(atPath: target.path), !fm.contentsEqual(atPath: source.path, andPath: target.path) {
                    warnings.append("\(path) 在好几个包里都有而且内容不一样，用的是 \(spec.id) 的")
                }
                try copy(source, to: path, origin: .package(spec.id))
            }
        }
    }

    // MARK: 规则 3：上游补丁当默认值

    func collectUpstreamPatches() throws {
        for spec in required {
            let package = input.packages[spec.id]!
            for path in package.info.files where Self.isUpstreamPatch(path) {
                let name = String(path.dropLast(".custom.yaml".count))
                let text = try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8)
                do {
                    patches[name, default: Patch()].merge(try Patch.parse(customYAML: text))
                } catch {
                    throw GenerationError.badYAML(file: "\(spec.id)/\(path)", message: String(describing: error))
                }
            }
        }
    }

    // MARK: 设置里保留的补丁

    func applyPreservedPatches() throws {
        for (name, items) in input.settings.preservedPatches.sorted(by: { $0.key < $1.key }) {
            for item in items {
                let node: Node?
                do {
                    node = try YAMLNode.parse(item.yaml)
                } catch {
                    throw GenerationError.badYAML(file: "settings.json 里保留的 \(name) 补丁 \(item.key)", message: String(describing: error))
                }
                if let node { patches[name, default: Patch()].set(item.key, node) }
            }
        }
    }

    // MARK: 规则 4：方案列表、每页候选数

    func applySchemaList() {
        let list = YAMLNode.list(input.settings.schemas.map { YAMLNode.map([("schema", YAMLNode.text($0))]) })
        patches["default", default: Patch()].set("schema_list", list)
        if let pageSize = input.settings.appearance.pageSize {
            patches["default", default: Patch()].set("menu/page_size", YAMLNode.int(pageSize))
        }
    }

    // MARK: 规则 8：写出补丁文件

    func writePatches() throws {
        for (name, patch) in patches.sorted(by: { $0.key < $1.key }) where !patch.isEmpty {
            try write(try patch.renderCustomYAML(), to: "\(name).custom.yaml", origin: .generated)
        }
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test --filter GeneratorBasicsTests 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 7 个测试全部通过。

- [ ] **Step 7: 跑全部测试并提交**

Run: `swift test 2>&1 | grep -E "error:|Test run" | tail -2`
Expected: 全部通过。

```bash
git add Sources/RimeKit/Config Tests/RimeKitTests
git commit -m "feat: 配置生成器骨架：复制上游文件、上游补丁、方案列表、保留的补丁

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 外观 → `squirrel.custom.yaml`

**Files:**
- Modify: `Sources/RimeKit/Config/GenerationContext.swift`（加 `applyAppearance`、`effectiveColorSchemes`）
- Modify: `Sources/RimeKit/Config/ConfigGenerator.swift`（`generate` 里调用）
- Test: `Tests/RimeKitTests/GeneratorAppearanceTests.swift`

**Interfaces:**
- Consumes: `GenerationContext`（任务 5）、`Appearance`（任务 3）。
- Produces: `GenerationContext.applyAppearance() throws`、`GenerationContext.effectiveColorSchemes(_ patch: Patch) throws -> [String]`。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorAppearanceTests {
    func generate(_ settings: Settings, _ dir: TempDir) throws -> URL {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages), into: out)
        return out
    }

    @Test func 字号同时写到style和上游补丁里的浅色深色配色() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["wb"])
        s.appearance.fontPoint = 24
        s.appearance.labelFontPoint = 20
        s.appearance.candidateListLayout = .linear
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")

        #expect(p["style/font_point"]?.string == "24")
        #expect(p["preset_color_schemes/roseo/font_point"]?.string == "24")
        #expect(p["preset_color_schemes/roseo_dark/font_point"]?.string == "24")
        #expect(p["preset_color_schemes/roseo/label_font_point"]?.string == "20")
        #expect(p["style/candidate_list_layout"]?.string == "linear")
        #expect(p["preset_color_schemes/roseo_dark/candidate_list_layout"]?.string == "linear")
        // 上游整体替换配色的那条在前，我们改字号的在后，Rime 按顺序应用，所以字号生效
        let keys = p.entries.map(\.key)
        #expect(keys.firstIndex(of: "preset_color_schemes")! < keys.firstIndex(of: "preset_color_schemes/roseo/font_point")!)
    }

    @Test func 没有上游补丁时用包里squirrel_yaml的配色() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["py"])
        s.appearance.fontPoint = 20
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")
        #expect(p["preset_color_schemes/aqua/font_point"]?.string == "20")
        #expect(p.entries.map(\.key) == ["style/font_point", "preset_color_schemes/aqua/font_point"])
    }

    @Test func 设置里指定的配色优先() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["wb"])
        s.appearance.colorScheme = "luna"
        s.appearance.commentFontPoint = 14
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")
        #expect(p["style/color_scheme"]?.string == "luna")
        #expect(p["preset_color_schemes/luna/comment_font_point"]?.string == "14")
        #expect(p["preset_color_schemes/roseo_dark/comment_font_point"]?.string == "14")
        #expect(p["preset_color_schemes/roseo/comment_font_point"] == nil)
    }

    @Test func 竖排() throws {
        let dir = try TempDir(); defer { dir.remove() }
        var s = Settings(schemas: ["py"])
        s.appearance.textOrientation = .vertical
        let p = try GenFixtures.patch(try generate(s, dir), "squirrel")
        #expect(p["style/text_orientation"]?.string == "vertical")
        #expect(p["preset_color_schemes/aqua/text_orientation"]?.string == "vertical")
    }

    @Test func 什么都没设也没有上游补丁时不生成文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try generate(Settings(schemas: ["py"]), dir)
        #expect(!GenFixtures.exists(out, "squirrel.custom.yaml"))
    }

    @Test func 没设外观时上游补丁原样保留() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let p = try GenFixtures.patch(try generate(Settings(schemas: ["wb"]), dir), "squirrel")
        #expect(p.entries.map(\.key) == ["style", "preset_color_schemes"])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter GeneratorAppearanceTests 2>&1 | grep -E "Test run|✘ Test" | head -8`
Expected: 失败（`squirrel.custom.yaml` 里没有字号的键）。

- [ ] **Step 3: 在 `GenerationContext.swift` 末尾（`writePatches` 前）加**

```swift
    // MARK: 规则 4：外观

    func applyAppearance() throws {
        let a = input.settings.appearance
        var p = patches["squirrel"] ?? Patch()
        if let s = a.colorScheme { p.set("style/color_scheme", YAMLNode.text(s)) }
        if let s = a.colorSchemeDark { p.set("style/color_scheme_dark", YAMLNode.text(s)) }
        var values: [(String, Node)] = []
        if let v = a.fontPoint { values.append(("font_point", YAMLNode.int(v))) }
        if let v = a.labelFontPoint { values.append(("label_font_point", YAMLNode.int(v))) }
        if let v = a.commentFontPoint { values.append(("comment_font_point", YAMLNode.int(v))) }
        if let v = a.candidateListLayout { values.append(("candidate_list_layout", YAMLNode.text(v.rawValue))) }
        if let v = a.textOrientation { values.append(("text_orientation", YAMLNode.text(v.rawValue))) }
        if !values.isEmpty {
            let schemes = try effectiveColorSchemes(p)
            for (key, value) in values {
                p.set("style/\(key)", value)
                for scheme in schemes { p.set("preset_color_schemes/\(scheme)/\(key)", value) }
            }
        }
        if !p.isEmpty { patches["squirrel"] = p }
    }

    /// 实际生效的浅色、深色配色名（去重）：补丁里写的（设置里指定的已经写进补丁）> 包里的 squirrel.yaml 写的
    func effectiveColorSchemes(_ patch: Patch) throws -> [String] {
        let file = try readYAML("squirrel.yaml", label: "squirrel.yaml")
        var result: [String] = []
        for key in ["color_scheme", "color_scheme_dark"] {
            let name = patch["style/\(key)"]?.string
                ?? patch["style"]?[key]?.string
                ?? file?["style"]?[key]?.string
            if let name, !result.contains(name) { result.append(name) }
        }
        return result
    }
```

`ConfigGenerator.generate` 里，`context.applySchemaList()` 后面加一行：

```swift
        try context.applyAppearance()
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 6 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Config Tests/RimeKitTests/GeneratorAppearanceTests.swift
git commit -m "feat: 外观写进 squirrel.custom.yaml，同时改生效的配色

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 包选项（补丁 + 总词库）和个人词库

**Files:**
- Modify: `Sources/RimeKit/Config/GenerationContext.swift`（加 `applyOptions`、`renderDict`、`copyPersonalDicts`）
- Modify: `Sources/RimeKit/Config/ConfigGenerator.swift`
- Test: `Tests/RimeKitTests/GeneratorOptionsTests.swift`

**Interfaces:**
- Consumes: `Settings.choice`（任务 3）、`PersonalContent.hasDict`（任务 4）、`GenerationContext`（任务 5）。
- Produces: `GenerationContext.applyOptions() throws`、`GenerationContext.copyPersonalDicts() throws`、`GenerationContext.renderDict(_ dict: GeneratedDict) -> String`。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorOptionsTests {
    func personal(_ dir: TempDir, _ dicts: [String: String]) throws -> PersonalContent {
        let base = dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, text) in dicts.sorted(by: { $0.key < $1.key }) {
            let url = base.appending(path: name)
            try Data(text.utf8).write(to: url)
            urls.append(url)
        }
        return PersonalContent(dicts: urls, phrases: [])
    }

    @Test func 默认选大词库时生成总词库和补丁() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "wpy"]), packages: packages), into: out)

        #expect(GenFixtures.exists(out, "cn/a.dict.yaml"))   // 选项依赖的 words 包
        let dict = try GenFixtures.read(out, "py_ext.dict.yaml")
        #expect(dict.contains("name: py_ext"))
        #expect(dict.contains("  - cn/a\n"))
        #expect(!dict.contains("py_user"))   // 没有个人词库就不挂
        #expect(result.files.contains(GeneratedFile(path: "py_ext.dict.yaml", origin: .generated)))
        #expect(try GenFixtures.patch(out, "wb")["reverse_lookup/dictionary"]?.string == "py_ext")
        #expect(try GenFixtures.patch(out, "wpy")["translator/dictionary"]?.string == "py_ext")
        #expect(!GenFixtures.exists(out, "wb_py.custom.yaml"))   // wb_py 没启用，不写它的补丁
    }

    @Test func 有个人词库时挂到总词库最前面() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let mine = try personal(dir, ["py_user.dict.yaml": GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"])])
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wpy"]), packages: packages, personal: mine), into: out)
        let dict = try GenFixtures.read(out, "py_ext.dict.yaml")
        #expect(dict.contains("import_tables:\n  - py_user\n  - cn/a\n"))
        #expect(result.files.contains(GeneratedFile(path: "py_user.dict.yaml", origin: .personal)))
    }

    @Test func 个人词库和上游模板同名时用个人的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let mine = try personal(dir, ["wb_user.dict.yaml": GenFixtures.dict("wb_user", ["我的词\tqrrs\t1"])])
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb"]), packages: packages, personal: mine), into: out)
        #expect(try GenFixtures.read(out, "wb_user.dict.yaml").contains("我的词"))
        #expect(result.files.contains(GeneratedFile(path: "wb_user.dict.yaml", origin: .personal)))
    }

    @Test func 选自带词库时什么都不加() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["wb", "wpy"], options: ["wubi": ["pinyinDictionary": "builtin"]]),
                                  packages: packages), into: out)
        #expect(!GenFixtures.exists(out, "py_ext.dict.yaml"))
        #expect(!GenFixtures.exists(out, "wb.custom.yaml"))
        #expect(!GenFixtures.exists(out, "cn/a.dict.yaml"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter GeneratorOptionsTests 2>&1 | grep -E "Test run|✘ Test" | head -8`
Expected: 失败（没有 `py_ext.dict.yaml`，个人词库没复制）。

- [ ] **Step 3: 在 `GenerationContext.swift` 加**

```swift
    // MARK: 规则 5：包选项

    func applyOptions() throws {
        let enabled = Set(input.settings.schemas)
        for spec in required {
            for option in spec.options {
                let choice = input.settings.choice(option, of: spec)
                for (schema, values) in choice.patches.sorted(by: { $0.key < $1.key }) where enabled.contains(schema) {
                    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                        patches[schema, default: Patch()].set(key, YAMLNode.text(value))
                    }
                }
                for dict in choice.generatedDicts {
                    try write(renderDict(dict), to: "\(dict.name).dict.yaml", origin: .generated)
                }
            }
        }
    }

    func renderDict(_ dict: GeneratedDict) -> String {
        let tables = dict.importTables
            .filter { !$0.onlyIfPersonal || input.personal.hasDict(named: $0.name) }
            .map { "  - \($0.name)\n" }
            .joined()
        return Patch.header
            + "---\n"
            + "name: \(dict.name)\n"
            + "version: \"squirrel-macos\"\n"
            + "sort: by_weight\n"
            + "import_tables:\n"
            + tables
            + "...\n"
    }

    // MARK: 规则 6：个人词库（和上游同名时用个人的）

    func copyPersonalDicts() throws {
        for url in input.personal.dicts {
            try copy(url, to: url.lastPathComponent, origin: .personal)
        }
    }
```

`ConfigGenerator.generate` 改成：

```swift
    public func generate(_ input: GenerationInput, into output: URL) throws -> GenerationResult {
        try input.settings.validate(input.catalog)
        let context = try GenerationContext(input: input, output: output)
        try context.copyPackageFiles()
        try context.collectUpstreamPatches()
        try context.applyOptions()
        try context.copyPersonalDicts()
        try context.applyPreservedPatches()
        context.applySchemaList()
        try context.applyAppearance()
        try context.writePatches()
        return context.result()
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 4 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Config Tests/RimeKitTests/GeneratorOptionsTests.swift
git commit -m "feat: 生成包选项的补丁和总词库；个人词库优先于上游模板

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 短语

**Files:**
- Modify: `Sources/RimeKit/Config/GenerationContext.swift`（加 `applyPhrases`）
- Modify: `Sources/RimeKit/Config/ConfigGenerator.swift`
- Test: `Tests/RimeKitTests/GeneratorPhraseTests.swift`

**Interfaces:**
- Consumes: `PhraseFile`、`Phrase`（任务 4）、`GenerationContext.readYAML`（任务 5）。
- Produces: `GenerationContext.applyPhrases() throws`；注入的补丁键：`engine/translators/@before 0` = `table_translator@custom_phrase`，`custom_phrase` = `{dictionary: "", user_dict: custom_phrase, db_class: stabledb, enable_completion: false, enable_sentence: false, initial_quality: 100}`（和作者现在的配置一样）。

- [ ] **Step 1: 写失败的测试**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorPhraseTests {
    let mine = PersonalContent(dicts: [], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])

    func generate(_ schemas: [String], personal: PersonalContent, textReplacement: [Phrase] = [], _ dir: TempDir) throws -> (URL, GenerationResult) {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: schemas, options: ["wubi": ["pinyinDictionary": "builtin"]]),
                                  packages: packages, personal: personal, textReplacement: textReplacement), into: out)
        return (out, result)
    }

    @Test func 没有短语时不注入上游短语文件原样复制() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, result) = try generate(["py", "wb"], personal: .empty, dir)
        #expect(try GenFixtures.read(out, "custom_phrase.txt").hasSuffix("上游短语\tsy\t1\n"))
        #expect(result.files.contains(GeneratedFile(path: "custom_phrase.txt", origin: .package("pinyin"))))
        #expect(!GenFixtures.exists(out, "wb.custom.yaml"))
    }

    @Test func 自带短语翻译器的方案把短语接在上游文件后面() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, result) = try generate(["py"], personal: mine, dir)
        let text = try GenFixtures.read(out, "custom_phrase.txt")
        #expect(text.hasPrefix("# Rime table\n#@/db_name"))
        #expect(text.hasSuffix("上游短语\tsy\t1\n测试短语\ttstx\t1\n"))
        #expect(result.files.contains(GeneratedFile(path: "custom_phrase.txt", origin: .generated)))
        #expect(!GenFixtures.exists(out, "py.custom.yaml"))   // 不用注入
    }

    @Test func 双拼用它自己的短语文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, _) = try generate(["sp"], personal: mine, dir)
        let text = try GenFixtures.read(out, "custom_phrase_double.txt")
        #expect(text.hasPrefix(PhraseFile.header))
        #expect(text.hasSuffix("测试短语\ttstx\t1\n"))
    }

    @Test func 没有短语翻译器的方案注入一个() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, _) = try generate(["wb"], personal: mine, dir)
        let p = try GenFixtures.patch(out, "wb")
        #expect(p["engine/translators/@before 0"]?.string == "table_translator@custom_phrase")
        #expect(p["custom_phrase"]?["user_dict"]?.string == "custom_phrase")
        #expect(p["custom_phrase"]?["db_class"]?.string == "stabledb")
        #expect(p["custom_phrase"]?["initial_quality"]?.string == "100")
        #expect(try GenFixtures.read(out, "custom_phrase.txt") == PhraseFile.header + "测试短语\ttstx\t1\n")
    }

    @Test func 全拼双拼五笔一起启用时每个短语文件都有() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tr = [Phrase(text: "文本替换", code: "wbth", weight: 1)]
        let (out, _) = try generate(["py", "sp", "wb"], personal: mine, textReplacement: tr, dir)
        for file in ["custom_phrase.txt", "custom_phrase_double.txt"] {
            #expect(try GenFixtures.read(out, file).hasSuffix("测试短语\ttstx\t1\n文本替换\twbth\t1\n"), "\(file)")
        }
        #expect(GenFixtures.exists(out, "wb.custom.yaml"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter GeneratorPhraseTests 2>&1 | grep -E "Test run|✘ Test" | head -8`
Expected: 失败（短语没写进去）。

- [ ] **Step 3: 在 `GenerationContext.swift` 加**

```swift
    // MARK: 规则 7：短语

    func applyPhrases() throws {
        let phrases = input.personal.phrases + input.textReplacementPhrases
        guard !phrases.isEmpty else { return }
        var targets: [String] = []
        for schema in input.settings.schemas {
            guard let root = try readYAML("\(schema).schema.yaml", label: "\(schema).schema.yaml") else { continue }
            let translators = root["engine"]?["translators"]?.sequence?.compactMap(\.string) ?? []
            let file: String
            if translators.contains("table_translator@custom_phrase") {
                file = (root["custom_phrase"]?["user_dict"]?.string ?? "custom_phrase") + ".txt"
            } else {
                var p = patches[schema] ?? Patch()
                p.set("engine/translators/@before 0", YAMLNode.text("table_translator@custom_phrase"))
                p.set("custom_phrase", YAMLNode.map([
                    ("dictionary", YAMLNode.text("")),
                    ("user_dict", YAMLNode.text("custom_phrase")),
                    ("db_class", YAMLNode.text("stabledb")),
                    ("enable_completion", YAMLNode.bool(false)),
                    ("enable_sentence", YAMLNode.bool(false)),
                    ("initial_quality", YAMLNode.int(100)),
                ]))
                patches[schema] = p
                file = "custom_phrase.txt"
            }
            if !targets.contains(file) { targets.append(file) }
        }
        for file in targets {
            let url = output.appending(path: file)
            var text = fm.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : PhraseFile.header
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            try write(text + PhraseFile.render(phrases), to: file, origin: .generated)
        }
    }
```

（`fm` 在类里是 `private let`，同一个文件里的方法可以用。）

`ConfigGenerator.generate` 里，`try context.copyPersonalDicts()` 后面加：

```swift
        try context.applyPhrases()
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 5 个）。

- [ ] **Step 5: 提交**

```bash
git add Sources/RimeKit/Config Tests/RimeKitTests/GeneratorPhraseTests.swift
git commit -m "feat: 生成自定义短语：用方案自己的短语文件，没有就注入

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 生成结果能编译、能打字（宿主机，离线）

**Files:**
- Create: `Tests/RimeKitTests/Support/RimeTools.swift`
- Test: `Tests/RimeKitTests/GeneratedConfigCompileTests.swift`

**Interfaces:**
- Consumes: `ConfigGenerator`、`GenFixtures`、`Shell`。
- Produces: 测试辅助 `RimeTools`：`static var installed: Bool`（宿主机装了鼠须管）、`static func build(_ dir: URL) throws -> ShellResult`（`rime_deployer --build`）、`static func type(_ dir: URL, schema: String, _ codes: [String]) throws -> [String: [String]]`（调 `tools/vm/rime-type-probe`，返回 编码 → 候选列表，自动上屏的字放第一个）。

前提：先运行 `./tools/vm/build-probes.sh`，生成 `tools/vm/rime-type-probe`。

- [ ] **Step 1: 写 `Tests/RimeKitTests/Support/RimeTools.swift`**

```swift
import Foundation
@testable import RimeKit

/// 调用宿主机上鼠须管自带的 rime_deployer 和打字检查工具。只读使用鼠须管，只处理临时目录。
enum RimeTools {
    static let squirrel = "/Library/Input Methods/Squirrel.app/Contents"

    static var installed: Bool {
        FileManager.default.isExecutableFile(atPath: squirrel + "/MacOS/rime_deployer")
    }

    /// 仓库里的 tools/vm/rime-type-probe（./tools/vm/build-probes.sh 编译出来）
    static var probe: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support
            .deletingLastPathComponent()   // RimeKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根目录
            .appending(path: "tools/vm/rime-type-probe")
    }

    static func build(_ dir: URL) throws -> ShellResult {
        try Shell.run(squirrel + "/MacOS/rime_deployer",
                      ["--build", dir.path, squirrel + "/SharedSupport", dir.appending(path: "build").path])
    }

    struct ProbeMissing: Error, CustomStringConvertible {
        var description: String { "找不到 tools/vm/rime-type-probe，先运行 ./tools/vm/build-probes.sh" }
    }

    /// 编码 → 候选（自动上屏的字放在第一个）
    static func type(_ dir: URL, schema: String, _ codes: [String]) throws -> [String: [String]] {
        guard FileManager.default.isExecutableFile(atPath: probe.path) else { throw ProbeMissing() }
        let r = try Shell.run(probe.path, [dir.path, schema] + codes)
        var result: [String: [String]] = [:]
        for line in r.stdout.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            var rest = String(parts[1])
            var candidates: [String] = []
            let committed = "[上屏]"
            if rest.hasPrefix(committed) {
                let after = rest.dropFirst(committed.count)
                if let space = after.firstIndex(of: " ") {
                    candidates.append(String(after[..<space]))
                    rest = String(after[after.index(after: space)...])
                } else {
                    candidates.append(String(after))
                    rest = ""
                }
            }
            if !rest.isEmpty { candidates += rest.components(separatedBy: " | ") }
            result[String(parts[0])] = candidates
        }
        return result
    }
}
```

- [ ] **Step 2: 写测试 `Tests/RimeKitTests/GeneratedConfigCompileTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

/// 用宿主机上的鼠须管编译生成结果，再模拟打字。没装鼠须管时跳过。
@Suite(.enabled(if: RimeTools.installed))
struct GeneratedConfigCompileTests {
    @Test func 生成的配置能编译而且能打出字() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let personalDir = dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: personalDir, withIntermediateDirectories: true)
        let userDict = personalDir.appending(path: "py_user.dict.yaml")
        try Data(GenFixtures.dict("py_user", ["鲸鱼\tjing yu\t1"]).utf8).write(to: userDict)
        let personal = PersonalContent(dicts: [userDict], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])

        var settings = Settings(schemas: ["wb", "wpy", "py", "sp"])
        settings.appearance.fontPoint = 24
        let out = dir.url.appending(path: "out")
        _ = try ConfigGenerator().generate(try GenFixtures.input(settings, packages: packages, personal: personal), into: out)

        let build = try RimeTools.build(out)
        #expect(build.status == 0, "\(build.stderr)")
        for file in ["wb.prism.bin", "wb.table.bin", "py_ext.table.bin", "py.table.bin"] {
            #expect(GenFixtures.exists(out, "build/\(file)"), "缺少 build/\(file)")
        }
        let compiledWB = try GenFixtures.read(out, "build/wb.schema.yaml")
        #expect(compiledWB.contains("py_ext"))
        #expect(compiledWB.contains("table_translator@custom_phrase"))

        let wb = try RimeTools.type(out, schema: "wb", ["g", "tstx"])
        #expect(wb["g"]?.first == "一")
        #expect(wb["tstx"]?.first == "测试短语")

        let wpy = try RimeTools.type(out, schema: "wpy", ["daciku", "jingyu"])
        #expect(wpy["daciku"]?.first == "大词库")   // 选项生成的总词库生效
        #expect(wpy["jingyu"]?.first == "鲸鱼")     // 个人词库挂进去了

        let py = try RimeTools.type(out, schema: "py", ["nihao", "tstx", "sy"])
        #expect(py["nihao"]?.first == "你好")
        #expect(py["tstx"]?.first == "测试短语")
        #expect(py["sy"]?.first == "上游短语")      // 上游短语还在

        let sp = try RimeTools.type(out, schema: "sp", ["tstx"])
        #expect(sp["tstx"]?.first == "测试短语")     // 双拼用自己的短语文件也有
    }
}
```

- [ ] **Step 3: 编译打字检查工具，然后运行**

```bash
./tools/vm/build-probes.sh 2>&1 | tail -2
swift test --filter GeneratedConfigCompileTests 2>&1 | grep -E "error:|Test run|✘|Expectation failed" | head -15
```

Expected: 通过。这一步测的是前面任务写好的代码和真实的 Rime，**通常一次就过**；如果有失败，说明生成规则和 Rime 的实际行为不一致，用 superpowers:systematic-debugging 找原因（看 `out/build/*.schema.yaml` 和 `out/*.log`），修生成器或者修 fixture，并在执行记录里写 Ruling。

- [ ] **Step 4: 提交**

```bash
git add Tests/RimeKitTests/Support/RimeTools.swift Tests/RimeKitTests/GeneratedConfigCompileTests.swift
git commit -m "test: 生成结果用 rime_deployer 编译并模拟打字

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 防误写真实目录 + `rimectl settings` / `rimectl generate`

**Files:**
- Create: `Sources/RimeKit/Config/RimeDirectoryGuard.swift`
- Modify: `Sources/rimectl/Rimectl.swift`
- Test: `Tests/RimeKitTests/RimeDirectoryGuardTests.swift`
- Test: `Tests/RimeKitTests/RimectlGenerateTests.swift`

**Interfaces:**
- Consumes: `SettingsStore`、`Settings.starter`、`Settings.requiredPackages`、`PersonalContent.load`、`ConfigGenerator`、`PackageStore`。
- Produces:
  - `public enum RimeDirectoryGuard { static func defaultHomes() -> [String]; static func isInsideRealRimeDirectory(_ url: URL, homes: [String] = defaultHomes()) -> Bool }`：路径（可以还不存在）是某个家目录的 `Library/Rime` 或在它里面时返回 true；用设备号 + inode 比较，认得出 firmlink 和符号链接；判断不了（没有任何家目录）时也返回 true。
  - `rimectl settings init <rime-ice|flypy|wubi-pinyin> [--force]`、`rimectl settings show`、`rimectl generate --out 目录 [--cache-only]`。
  - `Rimectl.run` 的参数解析加 `--out`、`--force`。

- [ ] **Step 1: 写失败的测试 `Tests/RimeKitTests/RimeDirectoryGuardTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct RimeDirectoryGuardTests {
    func home(_ dir: TempDir, rime: Bool) throws -> URL {
        let home = dir.url.appending(path: "home", directoryHint: .isDirectory)
        let library = home.appending(path: "Library", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        if rime {
            try FileManager.default.createDirectory(at: library.appending(path: "Rime/build"), withIntermediateDirectories: true)
        }
        return home
    }

    @Test func 认出Rime目录和它里面的目录() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: true)
        let homes = [home.path]
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime"), homes: homes))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime/build"), homes: homes))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime/new/deep"), homes: homes))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/rime"), homes: homes))
    }

    @Test func Rime目录还不存在时也认得出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: false)
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Rime"), homes: [home.path]))
    }

    @Test func 符号链接指过去也认得出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: true)
        let link = dir.url.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: home.appending(path: "Library/Rime"))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(link.appending(path: "x"), homes: [home.path]))
    }

    @Test func 普通目录和别处叫Rime的目录不算() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let home = try home(dir, rime: true)
        let homes = [home.path]
        #expect(!RimeDirectoryGuard.isInsideRealRimeDirectory(dir.url.appending(path: "out"), homes: homes))
        #expect(!RimeDirectoryGuard.isInsideRealRimeDirectory(dir.url.appending(path: "copy/Rime"), homes: homes))
        #expect(!RimeDirectoryGuard.isInsideRealRimeDirectory(home.appending(path: "Library/Other"), homes: homes))
    }

    @Test func 没有家目录可比时当作是() {
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(URL(fileURLWithPath: "/tmp/x"), homes: []))
    }

    @Test func 真实家目录的firmlink写法也认得出() {
        // 只读判断，不写任何东西
        let real = NSHomeDirectory() + "/Library/Rime"
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(URL(fileURLWithPath: real)))
        #expect(RimeDirectoryGuard.isInsideRealRimeDirectory(URL(fileURLWithPath: "/System/Volumes/Data" + real)))
    }
}
```

- [ ] **Step 2: 写失败的测试 `Tests/RimeKitTests/RimectlGenerateTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlGenerateTests {
    func context(_ dir: TempDir, catalog: Catalog) -> (Rimectl.Context, Output) {
        let output = Output(echo: false)
        let ctx = Rimectl.Context(http: FakeHTTPClient(), retry: .immediate, catalog: { catalog },
                                  defaultPaths: Fixtures.paths(dir), output: output)
        return (ctx, output)
    }

    @Test func settings_init写起步方案() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(dir, catalog: try Catalog.builtIn())
        #expect(await Rimectl.run(["settings", "init", "wubi-pinyin"], ctx) == 0)
        #expect(try SettingsStore(paths: Fixtures.paths(dir)).load() == Settings.starter(.wubiPinyin))
        #expect(await Rimectl.run(["settings", "init", "rime-ice"], ctx) == 1)
        #expect(out.text.contains("已经有设置了"))
        #expect(await Rimectl.run(["settings", "init", "rime-ice", "--force"], ctx) == 0)
        #expect(try SettingsStore(paths: Fixtures.paths(dir)).load()?.schemas == ["rime_ice"])
        #expect(await Rimectl.run(["settings", "init", "nope"], ctx) == 2)
    }

    @Test func settings_show打印设置() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(dir, catalog: try Catalog.builtIn())
        #expect(await Rimectl.run(["settings", "show"], ctx) == 1)
        #expect(out.text.contains("还没有设置"))
        try SettingsStore(paths: Fixtures.paths(dir)).save(.starter(.flypy))
        #expect(await Rimectl.run(["settings", "show"], ctx) == 0)
        #expect(out.text.contains("double_pinyin_flypy"))
    }

    @Test func generate用缓存生成到输出目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb", "py"]))
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        let target = dir.url.appending(path: "out")
        #expect(await Rimectl.run(["generate", "--cache-only", "--out", target.path], ctx) == 0)
        #expect(GenFixtures.exists(target, "default.custom.yaml"))
        #expect(GenFixtures.exists(target, "py_ext.dict.yaml"))
        #expect(out.text.contains("个文件"))
    }

    @Test func generate拒绝写真实的Rime目录() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb"]))
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        let real = NSHomeDirectory() + "/Library/Rime/squirrel-macos-should-not-exist"
        #expect(await Rimectl.run(["generate", "--cache-only", "--out", real], ctx) == 1)
        #expect(out.text.contains("拒绝"))
        #expect(!FileManager.default.fileExists(atPath: real))
    }

    @Test func generate没有设置() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        #expect(await Rimectl.run(["generate", "--out", dir.url.appending(path: "o").path], ctx) == 1)
        #expect(out.text.contains("还没有设置"))
    }

    @Test func generate输出目录不空() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        _ = try GenFixtures.makePackages(in: paths.packages)
        try SettingsStore(paths: paths).save(Settings(schemas: ["wb"]))
        let target = dir.url.appending(path: "out")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: target.appending(path: "a.txt"))
        let (ctx, out) = context(dir, catalog: try GenFixtures.catalog())
        #expect(await Rimectl.run(["generate", "--cache-only", "--out", target.path], ctx) == 1)
        #expect(out.text.contains("输出目录不是空的"))
    }

    @Test func generate缺参数() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (ctx, _) = context(dir, catalog: try GenFixtures.catalog())
        #expect(await Rimectl.run(["generate"], ctx) == 2)
    }
}
```

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter "RimeDirectoryGuardTests|RimectlGenerateTests" 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'RimeDirectoryGuard' in scope`。

- [ ] **Step 4: 实现 `Sources/RimeKit/Config/RimeDirectoryGuard.swift`**

```swift
import Darwin
import Foundation

/// 判断一个路径是不是（或在）真实的 ~/Library/Rime。
/// 生成配置、模拟打字都只能用副本；这里宁可多拒绝，也不能放过。
public enum RimeDirectoryGuard {
    private struct FileID: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// 可能的家目录：当前进程的、$HOME、passwd 里的、sudo 之前的用户的
    public static func defaultHomes() -> [String] {
        var homes = [NSHomeDirectory()]
        if let home = ProcessInfo.processInfo.environment["HOME"] { homes.append(home) }
        if let pw = getpwuid(getuid()) { homes.append(String(cString: pw.pointee.pw_dir)) }
        if let sudo = ProcessInfo.processInfo.environment["SUDO_UID"], let uid = uid_t(sudo), let pw = getpwuid(uid) {
            homes.append(String(cString: pw.pointee.pw_dir))
        }
        return homes
    }

    public static func isInsideRealRimeDirectory(_ url: URL, homes: [String] = defaultHomes()) -> Bool {
        let libraries = Set(homes.compactMap { fileID(($0 as NSString).appendingPathComponent("Library")) })
        if libraries.isEmpty { return true }

        // 找到最近一个存在的上级目录，解析掉符号链接；不存在的部分原样接在后面
        let fm = FileManager.default
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !fm.fileExists(atPath: existing.path) {
            rest.insert(existing.lastPathComponent, at: 0)
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { return true }
            existing = parent
        }
        guard let resolved = realpath(existing.path, nil) else { return true }
        let base = String(cString: resolved)
        free(resolved)

        var current = "/"
        for component in URL(fileURLWithPath: base).pathComponents.dropFirst() + rest {
            let parent = current
            current = (current as NSString).appendingPathComponent(component)
            if component.caseInsensitiveCompare("Rime") == .orderedSame,
               let id = fileID(parent), libraries.contains(id) {
                return true
            }
        }
        return false
    }

    private static func fileID(_ path: String) -> FileID? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileID(device: info.st_dev, inode: info.st_ino)
    }
}
```

- [ ] **Step 5: 改 `Sources/rimectl/Rimectl.swift`**

`usage` 改成：

```swift
    static let usage = """
    用法：
      rimectl catalog                                          列出内置方案清单
      rimectl fetch [--data-dir 目录] [--cache-only] 包名...      下载（或从缓存取）这些包和它们的依赖
      rimectl settings init <rime-ice|flypy|wubi-pinyin> [--force]   写入起步设置
      rimectl settings show                                    打印当前设置
      rimectl generate --out 目录 [--data-dir 目录] [--cache-only]   按设置生成一份 Rime 配置（只往空目录写）
    """
```

`run` 里的参数解析加两个分支（放在 `case "--cache-only":` 前面）：

```swift
            case "--out":
                guard i + 1 < args.count else { out.error(usage); return 2 }
                outDir = args[i + 1]
                i += 2
            case "--force":
                force = true
                i += 1
```

并在 `var cacheOnly = false` 后面声明：

```swift
        var outDir: String?
        var force = false
```

`switch command` 里加两个分支（放在 `case "fetch":` 前面）：

```swift
            case "settings":
                return try settingsCommand(Array(positional.dropFirst()), force: force, paths: paths, context)
            case "generate":
                guard let outDir else { out.error(usage); return 2 }
                return try await generate(out: URL(fileURLWithPath: outDir, isDirectory: true),
                                          cacheOnly: cacheOnly, paths: paths, context)
```

把原来 `fetch` 里「取一个包、失败时提示旧版本」的部分抽成一个函数，`fetch` 和 `generate` 都用。整个 `fetch` 函数换成下面这样，并加上 `settings`、`generate`：

```swift
    /// 取一个包：cacheOnly 时只用本地缓存；下载失败时提示可以用旧版本。失败返回 nil（已经输出了错误）。
    private static func obtain(_ spec: PackageSpec, cacheOnly: Bool, store: PackageStore, _ out: Output) async throws -> CachedPackage? {
        if cacheOnly {
            guard let pkg = store.latestCached(for: spec) else {
                out.error("\(spec.id)：本地没有缓存")
                return nil
            }
            return pkg
        }
        do {
            return try await store.fetch(spec)
        } catch where PackageStore.isDownloadFailure(error) {
            var message = "\(spec.id)：下载失败。\(error)"
            if let old = store.latestCached(for: spec) {
                message += "\n本地有缓存的旧版本 \(old.info.version)，可以加 --cache-only 先用它"
            }
            out.error(message)
            return nil
        }
    }

    private static func fetch(_ ids: [String], cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        let catalog = try context.catalog()
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        for spec in try catalog.installOrder(for: ids) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            report(pkg, out)
        }
        return 0
    }

    private static func settingsCommand(_ args: [String], force: Bool, paths: AppPaths, _ context: Context) throws -> Int32 {
        let out = context.output
        let store = SettingsStore(paths: paths)
        switch args.first {
        case "init":
            guard args.count == 2, let starter = Starter(rawValue: args[1]) else { out.error(usage); return 2 }
            if try store.load() != nil, !force {
                out.error("已经有设置了：\(paths.settingsFile.path)。要覆盖就加 --force")
                return 1
            }
            let settings = Settings.starter(starter)
            try settings.validate(try context.catalog())
            try store.save(settings)
            out.line("已写入起步设置「\(starter.displayName)」：\(paths.settingsFile.path)")
            return 0
        case "show":
            guard let settings = try store.load() else {
                out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
                return 1
            }
            out.line(String(decoding: try JSONCoding.encoder.encode(settings), as: UTF8.self))
            return 0
        default:
            out.error(usage)
            return 2
        }
    }

    private static func generate(out target: URL, cacheOnly: Bool, paths: AppPaths, _ context: Context) async throws -> Int32 {
        let out = context.output
        if RimeDirectoryGuard.isInsideRealRimeDirectory(target) {
            out.error("拒绝：--out 指向真实的 ~/Library/Rime（\(target.path)）。generate 只往别的空目录里写")
            return 1
        }
        guard let settings = try SettingsStore(paths: paths).load() else {
            out.error("还没有设置，先运行 rimectl settings init rime-ice|flypy|wubi-pinyin")
            return 1
        }
        let catalog = try context.catalog()
        try settings.validate(catalog)
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: try PersonalContent.load(from: paths), textReplacementPhrases: [])
        let result = try ConfigGenerator().generate(input, into: target)
        for warning in result.warnings { out.line("注意：\(warning)") }
        out.line("已生成 \(result.files.count) 个文件到 \(target.path)")
        return 0
    }
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test 2>&1 | grep -E "error:|Test run|✘ Test" | head -5`
Expected: 全部通过（新增 13 个）。

- [ ] **Step 7: 提交**

```bash
git add Sources Tests
git commit -m "feat: rimectl settings / generate；生成前防止误写真实 Rime 目录

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 用真实上游包端到端跑一遍，更新文档

**Files:**
- Create: `Tests/RimeKitTests/OnlineGenerateTests.swift`
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（第 5 节后加「5.1 生成规则」）
- Modify: `docs/verified-facts.md`（第 3 节加两条）
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`、`CLAUDE.md`、`README.md`

**Interfaces:**
- Consumes: 前面所有任务。

- [ ] **Step 1: 写联网测试 `Tests/RimeKitTests/OnlineGenerateTests.swift`**

```swift
import Foundation
import Testing
@testable import RimeKit

/// 用真实上游包生成、编译、打字。要联网，要宿主机装了鼠须管：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1" && RimeTools.installed))
struct OnlineGenerateTests {
    func run(_ starter: Starter, _ dir: TempDir) async throws -> URL {
        let catalog = try Catalog.builtIn()
        var settings = Settings.starter(starter)
        settings.appearance.fontPoint = 24
        let store = PackageStore(paths: Fixtures.paths(dir))
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) { packages[spec.id] = try await store.fetch(spec) }
        let personal = PersonalContent(dicts: [], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            GenerationInput(settings: settings, catalog: catalog, packages: packages, personal: personal, textReplacementPhrases: []),
            into: out)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let build = try RimeTools.build(out)
        #expect(build.status == 0)
        return out
    }

    @Test func 五笔加拼音混输() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try await run(.wubiPinyin, dir)
        let r = try RimeTools.type(out, schema: "wubi86_jidian_pinyin", ["g", "weixin", "qukuailian", "tstx"])
        #expect(r["g"]?.first == "一")
        #expect(r["weixin"]?.first == "微信")
        #expect(r["qukuailian"]?.first == "区块链")   // 雾凇大词库生效
        #expect(r["tstx"]?.first == "测试短语")
        let squirrel = try GenFixtures.patch(out, "squirrel")
        #expect(squirrel["preset_color_schemes/roseo_maple/font_point"]?.string == "24")
        #expect(squirrel["preset_color_schemes/roseo_maple_dark/font_point"]?.string == "24")
    }

    @Test func 雾凇全拼() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try await run(.rimeIce, dir)
        let r = try RimeTools.type(out, schema: "rime_ice", ["nihao", "tstx"])
        #expect(r["nihao"]?.first == "你好")
        #expect(r["tstx"]?.first == "测试短语")
        #expect(try GenFixtures.patch(out, "squirrel")["preset_color_schemes/purity_of_form_custom/font_point"]?.string == "24")
    }

    @Test func 小鹤双拼() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try await run(.flypy, dir)
        let r = try RimeTools.type(out, schema: "double_pinyin_flypy", ["nihc", "tstx"])
        #expect(r["nihc"]?.first == "你好")
        #expect(r["tstx"]?.first == "测试短语")
    }
}
```

- [ ] **Step 2: 联网跑**

Run: `RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests 2>&1 | grep -E "error:|Test run|✘|Expectation failed" | head -15`
Expected: 3 个测试全部通过。失败时用 superpowers:systematic-debugging：看 `out/build/<方案>.schema.yaml`、Yams 能不能读上游方案文件、候选顺序；修生成器或清单，写 Ruling。

- [ ] **Step 3: 宿主机上用 rimectl 试一次（临时目录）**

```bash
swift build 2>&1 | tail -1
D=$(mktemp -d)
.build/debug/rimectl settings init wubi-pinyin --data-dir "$D"
.build/debug/rimectl generate --data-dir "$D" --out "$D/rime"
ls "$D/rime" | head -40
"/Library/Input Methods/Squirrel.app/Contents/MacOS/rime_deployer" --build "$D/rime" "/Library/Input Methods/Squirrel.app/Contents/SharedSupport" "$D/rime/build" > /dev/null 2>&1; echo "build exit=$?"
./tools/vm/rime-type-probe "$D/rime" wubi86_jidian_pinyin g weixin qukuailian 2>/dev/null
.build/debug/rimectl generate --data-dir "$D" --out ~/Library/Rime; echo "exit=$?"
rm -rf "$D"
```

Expected：`generate` 输出「已生成 N 个文件」；编译成功；打出 一、微信、区块链；最后一条输出「拒绝：…」和 `exit=1`。

- [ ] **Step 4: 更新文档**

设计文档第 5 节「数据和文件」末尾（第 6 节之前）加一节「5.1 生成规则」，内容照抄本计划的「生成规则」一节（8 条），开头写一句「阶段 2 定下、经 rime_deployer 编译和模拟打字验证」。

`docs/verified-facts.md` 第 3 节「配置目录、部署和日志」的表格末尾加三行：

```markdown
| 补丁按顺序生效：同一个 `patch` 里先整体替换 `preset_color_schemes`，后面再写 `"preset_color_schemes/<配色>/font_point": 24`，最终是 24；整体替换会删掉原来的其它配色 | 实测（rime_deployer --compile，2026-10-15） |
| `rime_deployer --build` 只编译方案和 `default.yaml`，**不编译 `squirrel.yaml`**；`--compile` 也只接受方案文件。外观补丁有没有生效，宿主机上只能看生成的补丁，真实效果要在测试机里看 | 实测（2026-10-15） |
| 雾凇的小鹤双拼方案用 `custom_phrase_double.txt` 当短语文件（全拼用 `custom_phrase.txt`），上游不提供这个文件 | 查看（double_pinyin_flypy.schema.yaml） |
```

`roadmap.md` 阶段 2 那一行「成果」末尾加「（已完成，2026-10-15）」。

`CLAUDE.md` 开头的阶段说明改成「阶段 0、1、2 已完成，下一步写阶段 3 的计划」；「Swift 工程」那一行后面加：`联网的端到端测试（真实上游包生成、编译、打字）：RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests`。

`README.md` 的阶段说明改成「阶段 0–2 已完成（方案清单、下载缓存、生成配置）。下一步是阶段 3（写入真实配置、部署、备份还原）」；「开发」一节加一行：`- 试生成配置：rimectl settings init wubi-pinyin --data-dir D，再 rimectl generate --data-dir D --out D/rime`。

- [ ] **Step 5: 跑全部测试，提交，推送**

Run: `swift test 2>&1 | grep -E "error:|Test run" | tail -2`
Expected: 全部通过（联网的跳过）。

```bash
git add Tests/RimeKitTests/OnlineGenerateTests.swift docs CLAUDE.md README.md
git commit -m "test: 真实上游包端到端生成、编译、打字；文档写入生成规则

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```

# 阶段 5：接管已有配置 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 第一次打开时，认出用户已有的 `~/Library/Rime`：方案和顺序、包选项、外观、用户自己改过的补丁、个人词库、短语。先给用户看「认出了什么、接管后哪些文件会变」，用户确认后才保存成应用的设置和个人内容，再按 6.1 写入（设计 6.2 第 2 步）。命令行是 `rimectl takeover`（预览）和 `rimectl takeover --confirm`（真的接管）。

**Architecture:** 新增 `Takeover/` 目录。`TakeoverSurvey` 只看 Rime 目录，判断有没有配置、方案列表里有哪些方案、要下载哪些包做对照。`TakeoverAnalyzer` 拿用户的补丁和「不接管时生成器会写的默认补丁」逐项比对，得出设置、个人词库、短语和提示。`TakeoverPreview` 在暂存区按识别结果生成一遍，逐个文件和现在的目录比。`TakeoverApplier` 走 `Deployer.apply`，写入成功后才保存设置和个人内容。逐项比对靠新的 `PatchLeaves`：把补丁拆成「路径 → 值」的叶子。

另外两处配套改动：
- 清单的每个包可以标出「个人词库模板」（`userDicts`）。
- macOS 文本替换的**读取**提前到这一阶段做（`TextReplacementReader`）：拆分短语要用它。阶段 7 只剩「有变化时提示、同步」。

**Tech Stack:** Swift 6.4、Swift Testing、Yams 6.2.2、系统自带的 SQLite（`import SQLite3`，只读打开）、鼠须管自带的 `rime_deployer` 和打字检查工具（联网测试用）。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 4、5、6.1、6.2、7 节）；需求 [docs/requirements-draft.md](../../requirements-draft.md) 第 3b 条；样本 [docs/reference-wubi-profile.md](../../reference-wubi-profile.md)；事实 [docs/verified-facts.md](../../verified-facts.md) 第 5 节（文本替换）；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)

## 本阶段要定的事（计划里的做法，请确认）

| # | 问题 | 计划里的做法 | 理由 |
|---|---|---|---|
| 1 | 怎么认出用户改过哪些补丁 | 把用户的补丁和「上游自带补丁 + 认出的选项补丁」都拆成叶子（`menu: {page_size: 5}` → `menu/page_size = 5`），逐项比：一样的丢掉（生成时会再写）、应用管理的键变成设置、不一样的存成「保留的补丁」。和上游默认、应用管理的键都没关系的补丁项，整项原样保留 | 作者的配置是「复制上游补丁再改几行」的整段写法，只能逐项比才知道改了哪几行 |
| 2 | 哪些文件算个人词库 | 清单里给包标出「个人词库模板」（极点五笔：`wubi86_jidian_user.dict.yaml`、`wubi86_jidian_user_hamster.dict.yaml`），和上游不一样就是个人的；另外，所选选项的总词库里标了「只在有个人词库时」导入的词库（`pinyin_user.dict.yaml`）也算 | 上游的 `wubi86_jidian_user.dict.yaml` 自带一条「分组词条」，没法靠「空模板」判断；明确写在清单里最可靠。设计第 4 节加一个字段 |
| 3 | `custom_phrase.txt` 怎么拆成「文本替换生成」和「手动短语」 | 把文本替换的**读取**提前到本阶段：和当前文本替换对得上的算文本替换（接管后打开同步），其余算手动短语；上游自带的默认短语去掉 | 阶段 6（导出）在阶段 7 前面，不先拆开，文本替换的内容会被当成手动短语导出去（设计说文本替换默认不导出） |
| 4 | 用户自己写的简短 `default.custom.yaml`（没有上游补丁里的那些项） | 接管后按上游默认补起来，并提示「这些项会按上游默认加上」 | 生成规则一直会带上上游补丁（设计 5.1 第 3 条），这里只是如实告诉用户 |
| 5 | 浅色、深色配色字号不一样 | 用浅色的，并提示 | 设置里字号浅色深色一起改（设计第 5 节） |
| 6 | 上游文件被用户直接改过，或者是旧版本 | 换成最新版，在预览里列出来；原文件在备份里 | 设计 6.1 第 4 步：覆盖应用不管的文件前先问、先备份 |
| 7 | 同时启用雾凇和极点 | 接管时照原样认出来，不加额外规则 | 你说过这个规则留到以后再定 |
| 8 | 宿主机上你真实配置的检查 | 第 10 个任务里，**先问你**：复制一份 `~/Library/Rime` 到临时目录，只做预览（不确认、不写入、不通知鼠须管），只打印认出的设置、文件名和条数，不打印词库和短语内容。你不同意就跳过，或者把命令给你自己跑 | 路线图说「以作者的五笔配置为样本」；只读一份副本不碰真实配置 |

## Global Constraints

- 宿主机**不碰** `~/Library/Rime`、`/Library/Input Methods`、输入法启用状态。宿主机测试只用临时目录和自造数据；联网测试只下载上游包到临时目录。读宿主机的真实配置（哪怕是复制一份）要先问用户。
- 接管分两步：**预览只读，不改任何文件**；用户确认后才走 6.1 写入。写入前完整备份 Rime 目录，第一次的这份永久保留（`Deployer.apply` 已经这样做）。写入成功后才保存 `settings.json` 和 `personal/`；编译失败、出错时什么都不保存。
- 已经由应用管理的目录（`ledger.json` 里有记录）不再接管；已经有 `settings.json` 时要加 `--force` 才覆盖。
- 应用不认识的文件（例如 `weasel.custom.yaml`、`*.bak`、用户自己的笔记）**原样保留**，在预览里列出来。
- 第一版只认清单里的包和方案；认不出的方案不启用，文件原样保留，告诉用户。
- 隐私：输出、日志、错误信息只写条数和文件名，**不写**个人词库、短语、文本替换的内容。读文本替换数据库只用只读方式。测试里的个人内容全部是编的。
- 外观只用真正生效的键名：`font_point`、`label_font_point`、`comment_font_point`、`candidate_list_layout`、`text_orientation`；不用 `candidate_font_point`。
- 第三方依赖只有 Yams；SQLite 用系统自带的库。
- 测试机：只用长期测试机 `squirrel-dev`，同时最多两台。在测试机里跑会通知鼠须管的命令要用桌面会话：`sudo launchctl asuser $(id -u) sudo -u tester …`。
- 用简单直白的中文写错误信息和命令行输出。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 用户用整段写法改过的补丁项（例如在上游 `key_binder/bindings` 里打开了 `-` `=` 翻页）接管后不能丢（任务 5 的手写样本、任务 9 的真实上游样本都有测试）。
2. 应用不认识的文件（`weasel.custom.yaml`、`*.bak`、笔记）接管后原样保留，不进设置（任务 6、9 有测试）。
3. 个人词库、手动短语接管后不能丢；和文本替换一样的短语不能存成手动短语（任务 5、6、7 有测试）。
4. 确认接管后编译失败 → 真实目录不动，`settings.json`、`personal/` 都不写（任务 7 有测试）。
5. 接管一份应用自己生成的配置 → 认出的设置和原来一样，预览里没有任何文件会变；接管后再应用一次，一个文件都不写（任务 6、7、9 有测试）。

---

## 文件结构

```
Sources/RimeKit/
  Config/PatchLeaves.swift              # 新：补丁拆成叶子；比较两个 YAML 值
  Config/Settings.swift                 # 字号、每页候选数的范围改成公开常量
  Config/GenerationContext.swift        # 短语翻译器的配置提出来共用
  Catalog/Catalog.swift                 # PackageSpec 加 userDicts；校验
  Catalog/CatalogError.swift            # 加 badUserDict
  Resources/catalog.json                # 极点五笔标出个人词库模板
  TextReplacement/TextReplacementReader.swift  # 新：读 macOS 文本替换
  Takeover/TakeoverFiles.swift          # 新：读文件、解析 YAML、读词库头
  Takeover/TakeoverSurvey.swift         # 新：TakeoverError、TakeoverSurvey
  Takeover/TakeoverAnalyzer.swift       # 新：TakeoverProposal、识别
  Takeover/TakeoverPreview.swift        # 新：预览
  Takeover/TakeoverApplier.swift        # 新：确认接管
Sources/rimectl/Rimectl.swift           # takeover 命令；apply 时同步文本替换
Tests/RimeKitTests/
  Support/GenFixtures.swift             # wubi 包标出 userDicts
  Support/TakeoverFixtures.swift        # 新：手写的五笔样本
  Support/TextReplacementFixtures.swift # 新：自造文本替换数据库
  Support/WubiSample.swift              # 新：用真实上游造脱敏样本
  PatchLeavesTests.swift
  CatalogTests.swift、BuiltInCatalogTests.swift
  TextReplacementReaderTests.swift
  TakeoverSurveyTests.swift
  TakeoverAnalyzerTests.swift
  TakeoverPreviewTests.swift
  TakeoverApplierTests.swift
  RimectlTakeoverTests.swift
  OnlineTakeoverTests.swift
docs/phase5-vm-log.md
```

---

### Task 1: 把补丁拆成叶子，比较两个 YAML 值

**Files:**
- Create: `Sources/RimeKit/Config/PatchLeaves.swift`
- Test: `Tests/RimeKitTests/PatchLeavesTests.swift`

**Interfaces:**
- Produces:
  - `public struct PatchLeaves: Equatable`：`init()`、`init(_ patch: Patch)`、`mutating func set(_ key: String, _ value: Node)`、`subscript(path: String) -> Node?`、`var paths: [String]`（按第一次出现的顺序）、`static func flatten(_ key: String, _ value: Node) -> [(path: String, value: Node)]`、`static func overlaps(_ a: String, _ b: String) -> Bool`
  - `extension YAMLNode`：`static func same(_ a: Node, _ b: Node) -> Bool`、`static func canonical(_ node: Node) -> String`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/PatchLeavesTests.swift`：

```swift
import Foundation
import Testing
import Yams
@testable import RimeKit

@Suite struct PatchLeavesTests {
    func node(_ yaml: String) throws -> Node { try #require(try YAMLNode.parse(yaml)) }

    @Test func 整段写法拆成叶子() throws {
        let leaves = PatchLeaves.flatten("menu", try node("page_size: 5\nalternative_select_keys: \"123\"\n"))
        #expect(leaves.map(\.path) == ["menu/page_size", "menu/alternative_select_keys"])
        #expect(leaves.first?.value.string == "5")
    }

    @Test func 列表和空映射是叶子() throws {
        #expect(PatchLeaves.flatten("key_binder/bindings", try node("- a\n- b\n")).map(\.path) == ["key_binder/bindings"])
        #expect(PatchLeaves.flatten("x", try node("{}")).map(\.path) == ["x"])
    }

    @Test func 键里有斜杠的映射不拆() throws {
        // 标点映射的键就是 "/"：拆开会得到 Rime 认不出的路径，所以整个映射当一个叶子
        let leaves = PatchLeaves.flatten("punctuator/full_shape", try node("\"/\": [\"／\", \"÷\"]\n\",\": \"，\"\n"))
        #expect(leaves.map(\.path) == ["punctuator/full_shape"])
    }

    @Test func 后写的覆盖先写的() throws {
        var p = Patch()
        p.set("menu/page_size", YAMLNode.int(7))
        p.set("menu", try node("page_size: 5\nfoo: 1\n"))   // 整段写入：清掉原来这一段下面的
        p.set("menu/foo", YAMLNode.int(2))
        let leaves = PatchLeaves(p)
        #expect(leaves.paths == ["menu/page_size", "menu/foo"])
        #expect(leaves["menu/page_size"]?.string == "5")
        #expect(leaves["menu/foo"]?.string == "2")
    }

    @Test func 写下层路径时清掉上层原来的值() throws {
        var leaves = PatchLeaves()
        leaves.set("a", YAMLNode.int(1))
        leaves.set("a/b", YAMLNode.int(2))
        #expect(leaves.paths == ["a/b"])
        #expect(leaves["a"] == nil)
    }

    @Test func 比较值时不管引号和键的顺序() throws {
        #expect(YAMLNode.same(try node("\"5\""), try node("5")))
        #expect(YAMLNode.same(try node("a: 1\nb: [x, y]\n"), try node("b:\n  - x\n  - y\na: '1'\n")))
        #expect(!YAMLNode.same(try node("[1, 2]"), try node("[2, 1]")))
        #expect(!YAMLNode.same(try node("a"), try node("b")))
    }

    @Test func 路径有没有上下级关系() {
        #expect(PatchLeaves.overlaps("menu", "menu/page_size"))
        #expect(PatchLeaves.overlaps("menu/page_size", "menu"))
        #expect(PatchLeaves.overlaps("a", "a"))
        #expect(!PatchLeaves.overlaps("menu/page", "menu/page_size"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter PatchLeavesTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`cannot find 'PatchLeaves' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Config/PatchLeaves.swift`：

```swift
import Foundation
import Yams

/// 补丁的「叶子」：把映射一层层拆开，得到 路径 → 值（列表、标量、空映射是叶子）。
/// 例：`menu: {page_size: 5}` 拆成 `menu/page_size = 5`。
/// 接管已有配置时，用它逐项比对用户的补丁和上游默认补丁（整段写法和路径写法都能比）。
public struct PatchLeaves: Equatable {
    /// 按第一次出现的顺序
    public private(set) var paths: [String] = []
    private var values: [String: Node] = [:]

    public init() {}

    /// 按顺序应用补丁里的每一项（和 Rime 一样，后面的覆盖前面的）
    public init(_ patch: Patch) {
        for entry in patch.entries { set(entry.key, entry.value) }
    }

    public subscript(path: String) -> Node? { values[path] }

    /// 写入一项：整段写入时先清掉这一段下面原来的叶子；写下层路径时清掉上层原来的值
    public mutating func set(_ key: String, _ value: Node) {
        let stale = paths.filter { $0 == key || $0.hasPrefix(key + "/") || key.hasPrefix($0 + "/") }
        for path in stale { values[path] = nil }
        paths.removeAll { stale.contains($0) }
        for (path, leaf) in Self.flatten(key, value) {
            if values[path] == nil { paths.append(path) }
            values[path] = leaf
        }
    }

    /// 拆一项。映射的键里有 "/"（例如标点映射）或是空的、不是字符串时，整个映射当一个叶子：拆开的路径 Rime 认不出来
    public static func flatten(_ key: String, _ value: Node) -> [(path: String, value: Node)] {
        guard case .mapping(let mapping) = value, !mapping.isEmpty else { return [(key, value)] }
        var names: [(String, Node)] = []
        for (k, v) in mapping {
            guard let name = k.string, !name.isEmpty, !name.contains("/") else { return [(key, value)] }
            names.append((name, v))
        }
        return names.flatMap { flatten("\(key)/\($0.0)", $0.1) }
    }

    /// 两个路径是同一个，或者一个在另一个下面
    public static func overlaps(_ a: String, _ b: String) -> Bool {
        a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }
}

extension YAMLNode {
    /// 两个值是不是一样：不管引号风格、映射里键的顺序；列表要顺序一样
    public static func same(_ a: Node, _ b: Node) -> Bool {
        canonical(a) == canonical(b)
    }

    static func canonical(_ node: Node) -> String {
        switch node {
        case .scalar(let scalar):
            return scalar.string.debugDescription
        case .sequence(let sequence):
            return "[" + sequence.map(canonical).joined(separator: ",") + "]"
        case .mapping(let mapping):
            return "{" + mapping.map { canonical($0.key) + ":" + canonical($0.value) }.sorted().joined(separator: ",") + "}"
        case .alias:
            return String(describing: node)
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter PatchLeavesTests 2>&1 | grep -E "error:|warning:|passed|failed" | tail -3`
Expected: `Suite PatchLeavesTests passed`，7 个测试通过，没有 warning

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Config/PatchLeaves.swift Tests/RimeKitTests/PatchLeavesTests.swift
git commit -m "feat: 补丁拆成叶子、比较两个 YAML 值（接管时逐项比对用）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 清单标出个人词库模板

**Files:**
- Modify: `Sources/RimeKit/Catalog/Catalog.swift`（`PackageSpec` 加 `userDicts`；`validate()` 检查）
- Modify: `Sources/RimeKit/Catalog/CatalogError.swift`（加 `badUserDict`）
- Modify: `Sources/RimeKit/Resources/catalog.json`
- Modify: `Tests/RimeKitTests/Support/GenFixtures.swift`（wubi 包加 `"userDicts":["wb_user.dict.yaml"]`）
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（第 4 节字段表加一行）
- Test: `Tests/RimeKitTests/CatalogTests.swift`、`Tests/RimeKitTests/BuiltInCatalogTests.swift`

**Interfaces:**
- Produces: `PackageSpec.userDicts: [String]`（包根目录下的 `.dict.yaml`，JSON 里可以不写，默认空）；`CatalogError.badUserDict(package: String, file: String)`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/CatalogTests.swift` 里，`@Test func 安装顺序依赖在前而且不重复()` 前面加：

```swift
    @Test func 个人词库模板要在包根目录而且在安装规则里() {
        let notIncluded = Fixtures.catalogData(
            replacing: #""requiredFiles":["app.schema.yaml"],"#,
            with: #""requiredFiles":["app.schema.yaml"],"userDicts":["app_user.dict.yaml"],"#)
        #expect(throws: CatalogError.badUserDict(package: "app", file: "app_user.dict.yaml")) {
            try Catalog.decode(notIncluded)
        }
        let inSubdirectory = Fixtures.catalogData(
            replacing: #""requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"],"#,
            with: #""requiredFiles":["base.schema.yaml","dicts/a.dict.yaml"],"userDicts":["dicts/a.dict.yaml"],"#)
        #expect(throws: CatalogError.badUserDict(package: "base", file: "dicts/a.dict.yaml")) {
            try Catalog.decode(inSubdirectory)
        }
    }

    @Test func 没写个人词库模板时是空的() throws {
        #expect(try Fixtures.catalog().package("app")?.userDicts == [])
    }
```

`Tests/RimeKitTests/BuiltInCatalogTests.swift` 里，`@Test func GPL的包都标了许可证()` 前面加：

```swift
    @Test func 极点五笔标出了个人词库模板() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.package("wubi86-jidian")?.userDicts == ["wubi86_jidian_user.dict.yaml", "wubi86_jidian_user_hamster.dict.yaml"])
        #expect(catalog.package("rime-ice")?.userDicts == [])
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter "CatalogTests" 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`has no member 'badUserDict'` / `has no member 'userDicts'`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Catalog/CatalogError.swift`：在 `case patchForUnknownSchema(package: String, schema: String)` 后面加一行

```swift
    case badUserDict(package: String, file: String)
```

在 `description` 的 `switch` 最后（`patchForUnknownSchema` 那个 case 后面）加：

```swift
        case let .badUserDict(package, file):
            return "包 \(package) 的个人词库模板 \(file) 必须是包根目录下、安装规则里有的 .dict.yaml"
```

`Sources/RimeKit/Catalog/Catalog.swift`：
1. `PackageSpec` 里 `public let options: [PackageOption]` 后面加：

```swift
    /// 上游自带的个人词库模板（包根目录下的 .dict.yaml）：用户会往里加词。
    /// 接管已有配置时，和上游不一样的就当个人词库收进 personal/；JSON 里可以不写
    public let userDicts: [String]
```

2. `CodingKeys` 改成 `case id, name, summary, license, homepage, source, anchor, include, exclude, requiredFiles, schemas, dependencies, options, userDicts`
3. `init(from:)` 最后加 `userDicts = try c.decodeIfPresent([String].self, forKey: .userDicts) ?? []`
4. `validate()` 里检查必需文件的循环后面加：

```swift
        for p in packages {
            for file in p.userDicts {
                let included = p.include.contains { $0.matches(file) } && !p.exclude.contains { $0.matches(file) }
                guard included, !file.contains("/"), file.hasSuffix(".dict.yaml") else {
                    throw CatalogError.badUserDict(package: p.id, file: file)
                }
            }
        }
```

`Sources/RimeKit/Resources/catalog.json`：`wubi86-jidian` 的 `"dependencies": [],` 后面加一行

```json
      "userDicts": ["wubi86_jidian_user.dict.yaml", "wubi86_jidian_user_hamster.dict.yaml"],
```

`Tests/RimeKitTests/Support/GenFixtures.swift`：wubi 包里单独占一行的 `      "dependencies":[],`（下一行是 `      "options":[{"id":"pinyinDictionary",…`）改成 `      "dependencies":[],"userDicts":["wb_user.dict.yaml"],`。注意不要改选项里 `{"id":"builtin",…,"dependencies":[],"generatedDicts":[]…}` 那一处。

`docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md` 第 4 节字段表，`| 字号写在哪里 | … |` 那一行后面加：

```markdown
| 个人词库模板 | 上游自带、用户会往里加词的词库（极点五笔的 `wubi86_jidian_user.dict.yaml`、`wubi86_jidian_user_hamster.dict.yaml`）。接管已有配置时，和上游不一样的就收进 `personal/` |
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "CatalogTests" 2>&1 | grep -E "error:|warning:|Test run" | tail -2`
Expected: 全部通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Catalog Sources/RimeKit/Resources/catalog.json Tests/RimeKitTests docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md
git commit -m "feat: 清单可以标出个人词库模板（极点五笔的 user 词库）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 读 macOS 文本替换

**Files:**
- Create: `Sources/RimeKit/TextReplacement/TextReplacementReader.swift`
- Create: `Tests/RimeKitTests/Support/TextReplacementFixtures.swift`
- Test: `Tests/RimeKitTests/TextReplacementReaderTests.swift`

**Interfaces:**
- Produces: `public struct TextReplacementReader: Sendable`：`static var defaultDatabase: URL`、`init(database: URL = defaultDatabase)`、`func read() throws -> [Phrase]`（权重都是 1，编码是小写的快捷码；没有数据库文件时返回空）；`public enum TextReplacementError: Error, Equatable, Sendable, CustomStringConvertible { case cannotOpen(String), queryFailed(String) }`
- 测试辅助：`TextReplacementFixtures.makeDatabase(_ url: URL, _ rows: [(shortcut: String?, phrase: String?, deleted: Int?)]) throws`

- [ ] **Step 1: 写测试辅助和失败的测试**

`Tests/RimeKitTests/Support/TextReplacementFixtures.swift`：

```swift
import Foundation
import SQLite3

/// 自造一个和系统 TextReplacements.db 同样表结构的数据库（只有用到的字段）
enum TextReplacementFixtures {
    struct SQLiteError: Error, CustomStringConvertible {
        let description: String
    }

    static func makeDatabase(_ url: URL, _ rows: [(shortcut: String?, phrase: String?, deleted: Int?)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteError(description: "建不了数据库") }
        defer { sqlite3_close(db) }
        let create = "CREATE TABLE ZTEXTREPLACEMENTENTRY (Z_PK INTEGER PRIMARY KEY, ZSHORTCUT VARCHAR, ZPHRASE VARCHAR, ZWASDELETED INTEGER)"
        guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else { throw SQLiteError(description: String(cString: sqlite3_errmsg(db))) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT INTO ZTEXTREPLACEMENTENTRY (ZSHORTCUT, ZPHRASE, ZWASDELETED) VALUES (?, ?, ?)", -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteError(description: String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(statement) }
            if let s = row.shortcut { sqlite3_bind_text(statement, 1, s, -1, transient) } else { sqlite3_bind_null(statement, 1) }
            if let p = row.phrase { sqlite3_bind_text(statement, 2, p, -1, transient) } else { sqlite3_bind_null(statement, 2) }
            if let d = row.deleted { sqlite3_bind_int(statement, 3, Int32(d)) } else { sqlite3_bind_null(statement, 3) }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteError(description: String(cString: sqlite3_errmsg(db))) }
        }
    }
}
```

`Tests/RimeKitTests/TextReplacementReaderTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TextReplacementReaderTests {
    @Test func 只读出能在Rime里打出来的条目() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try TextReplacementFixtures.makeDatabase(db, [
            ("Wx", "微信", 0),            // 快捷码转成小写
            ("abc1", "带数字", 0),         // 快捷码不只是字母：打不出来
            ("hh", "换\n行", 0),
            ("hc", "回\r车", 0),
            ("tb", "制\t表", 0),
            ("sc", "删掉了", 1),
            ("nl", "删除标记是空的", nil),  // 空的删除标记算没删
            (nil, "没有快捷码", 0),
            ("", "快捷码是空的", 0),
            ("xy", nil, 0),
        ])
        let phrases = try TextReplacementReader(database: db).read()
        #expect(phrases == [
            Phrase(text: "删除标记是空的", code: "nl", weight: 1),
            Phrase(text: "微信", code: "wx", weight: 1),
        ])
    }

    @Test func 没有数据库文件就当没有文本替换() throws {
        let dir = try TempDir(); defer { dir.remove() }
        #expect(try TextReplacementReader(database: dir.url.appending(path: "none.db")).read() == [])
    }

    @Test func 数据库坏了会报错() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let db = dir.url.appending(path: "TextReplacements.db")
        try Data("这不是数据库".utf8).write(to: db)
        #expect(throws: TextReplacementError.self) { try TextReplacementReader(database: db).read() }
    }

    @Test func 默认读系统的数据库() {
        #expect(TextReplacementReader.defaultDatabase.path.hasSuffix("/Library/KeyboardServices/TextReplacements.db"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TextReplacementReaderTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`cannot find 'TextReplacementReader' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/TextReplacement/TextReplacementReader.swift`：

```swift
import Foundation
import SQLite3

public enum TextReplacementError: Error, Equatable, Sendable, CustomStringConvertible {
    case cannotOpen(String)
    case queryFailed(String)

    public var description: String {
        switch self {
        case .cannotOpen(let message):
            return "读不了 macOS 的文本替换（\(message)）。可以去「系统设置 → 隐私与安全性」检查权限"
        case .queryFailed(let message):
            return "读 macOS 的文本替换失败：\(message)"
        }
    }
}

/// 读 macOS「文本替换」（~/Library/KeyboardServices/TextReplacements.db），只读打开。
/// 只要能在 Rime 里直接打出来的条目：快捷码只有字母（转成小写），内容不含换行和 Tab（verified-facts 第 5 节）。
public struct TextReplacementReader: Sendable {
    public static var defaultDatabase: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/KeyboardServices/TextReplacements.db")
    }

    static let query = """
        SELECT ZPHRASE, lower(ZSHORTCUT)
        FROM ZTEXTREPLACEMENTENTRY
        WHERE (ZWASDELETED = 0 OR ZWASDELETED IS NULL)
          AND ZSHORTCUT IS NOT NULL AND ZPHRASE IS NOT NULL AND ZSHORTCUT <> ''
          AND ZSHORTCUT NOT GLOB '*[^A-Za-z]*'
          AND instr(ZPHRASE, char(9)) = 0 AND instr(ZPHRASE, char(10)) = 0 AND instr(ZPHRASE, char(13)) = 0
        ORDER BY lower(ZSHORTCUT), ZPHRASE
        """

    public let database: URL

    public init(database: URL = Self.defaultDatabase) {
        self.database = database
    }

    /// 没有数据库文件时返回空（当作没有文本替换）
    public func read() throws -> [Phrase] {
        guard FileManager.default.fileExists(atPath: database.path) else { return [] }
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
        var phrases: [Phrase] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw TextReplacementError.queryFailed(String(cString: sqlite3_errmsg(db))) }
            guard let text = sqlite3_column_text(statement, 0), let code = sqlite3_column_text(statement, 1) else { continue }
            phrases.append(Phrase(text: String(cString: text), code: String(cString: code), weight: 1))
        }
        return phrases
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TextReplacementReaderTests 2>&1 | grep -E "error:|warning:|passed|failed" | tail -3`
Expected: 4 个测试通过，没有 warning

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/TextReplacement Tests/RimeKitTests/Support/TextReplacementFixtures.swift Tests/RimeKitTests/TextReplacementReaderTests.swift
git commit -m "feat: 只读方式读 macOS 文本替换（接管时拆分短语用）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 看一眼 Rime 目录：有没有配置、有哪些方案

**Files:**
- Create: `Sources/RimeKit/Takeover/TakeoverFiles.swift`
- Create: `Sources/RimeKit/Takeover/TakeoverSurvey.swift`
- Test: `Tests/RimeKitTests/TakeoverSurveyTests.swift`

**Interfaces:**
- Consumes: `RimeFiles.configFiles(in:)`、`Patch.parse(customYAML:)`、`PatchLeaves`（任务 1）
- Produces:
  - `public enum TakeoverError: Error, Equatable, Sendable, CustomStringConvertible { case alreadyManaged, settingsExist(String), nothingRecognized, badYAML(file: String, message: String), missingPackage(String) }`
  - `public struct TakeoverSurvey: Sendable, Equatable { isEmpty: Bool; schemas: [String]; unknownSchemas: [String]; packages: [String]; static func scan(_ rime: URL, catalog: Catalog) throws -> TakeoverSurvey }`
  - `enum TakeoverFiles`（内部）：`read(_ dir: URL, _ path: String) throws -> String?`、`patch(_ text: String, file: String) throws -> Patch`、`yaml(_ text: String, file: String) throws -> Node?`、`importTables(_ dictText: String) -> [String]?`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/TakeoverSurveyTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverSurveyTests {
    func write(_ text: String, _ path: String, in dir: URL) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func 目录不存在或者只有Rime自己的文件算空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        #expect(try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog()).isEmpty)
        try write("var: {}\n", "user.yaml", in: rime)
        try write("installation_id: x\n", "installation.yaml", in: rime)
        try write("x", "build/py.prism.bin", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey == TakeoverSurvey(isEmpty: true, schemas: [], unknownSchemas: [], packages: []))
    }

    @Test func 方案列表从default补丁里读_认不出的单独列出() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  schema_list:\n    - schema: wb_py\n    - schema: luna_pinyin\n    - schema: wb\n    - schema: wb\n", "default.custom.yaml", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey == TakeoverSurvey(isEmpty: false, schemas: ["wb_py", "wb"], unknownSchemas: ["luna_pinyin"], packages: ["wubi"]))
    }

    @Test func 补丁里没有方案列表时看default_yaml() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  menu/page_size: 7\n", "default.custom.yaml", in: rime)
        try write("schema_list:\n  - schema: sp\n  - schema: py\nmenu:\n  page_size: 5\n", "default.yaml", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey.schemas == ["sp", "py"])
        #expect(survey.packages == ["pinyin"])
    }

    @Test func 有配置但认不出方案() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("随手记\n", "notes.txt", in: rime)
        let survey = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
        #expect(survey == TakeoverSurvey(isEmpty: false, schemas: [], unknownSchemas: [], packages: []))
    }

    @Test func 补丁写坏了会说是哪个文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try write("patch:\n  schema_list: [\n", "default.custom.yaml", in: rime)
        do {
            _ = try TakeoverSurvey.scan(rime, catalog: try GenFixtures.catalog())
            Issue.record("应该报错")
        } catch let TakeoverError.badYAML(file, _) {
            #expect(file == "default.custom.yaml")
        }
    }

    @Test func 读词库头里的import_tables() {
        let text = "# 注释\n---\nname: py_ext\nimport_tables:\n  - py_user\n  - cn/a\n...\n你好\tni hao\t1\n"
        #expect(TakeoverFiles.importTables(text) == ["py_user", "cn/a"])
        #expect(TakeoverFiles.importTables("---\nname: x\n...\n") == [])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TakeoverSurveyTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`cannot find 'TakeoverSurvey' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Takeover/TakeoverFiles.swift`：

```swift
import Foundation
import Yams

/// 接管时读 Rime 目录里的文件
enum TakeoverFiles {
    /// 文件不存在时返回 nil
    static func read(_ dir: URL, _ path: String) throws -> String? {
        let url = dir.appending(path: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func patch(_ text: String, file: String) throws -> Patch {
        do {
            return try Patch.parse(customYAML: text)
        } catch {
            throw TakeoverError.badYAML(file: file, message: String(describing: error))
        }
    }

    static func yaml(_ text: String, file: String) throws -> Node? {
        do {
            return try YAMLNode.parse(text)
        } catch {
            throw TakeoverError.badYAML(file: file, message: String(describing: error))
        }
    }

    /// 词库文件头里的 import_tables（头在第一行 "..." 之前）；读不懂时返回 nil
    static func importTables(_ dictText: String) -> [String]? {
        var header: [Substring] = []
        for line in dictText.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "..." { break }
            header.append(line)
        }
        guard let root = try? YAMLNode.parse(header.joined(separator: "\n")) else { return nil }
        return root["import_tables"]?.sequence?.compactMap(\.string) ?? []
    }
}
```

`Sources/RimeKit/Takeover/TakeoverSurvey.swift`：

```swift
import Foundation
import Yams

public enum TakeoverError: Error, Equatable, Sendable, CustomStringConvertible {
    case alreadyManaged
    case settingsExist(String)
    case nothingRecognized
    case badYAML(file: String, message: String)
    case missingPackage(String)

    public var description: String {
        switch self {
        case .alreadyManaged:
            return "这个 Rime 目录已经由应用管理了（ledger.json 里有记录），不用再接管"
        case .settingsExist(let path):
            return "已经有设置了：\(path)。接管会覆盖设置和个人内容，要覆盖就加 --force"
        case .nothingRecognized:
            return "Rime 目录里的配置没有一个方案在方案清单里，认不出来。可以选一个起步方案（rimectl settings init …）再应用，原来的文件会先备份"
        case let .badYAML(file, message):
            return "读不懂 \(file)：\(message)"
        case .missingPackage(let id):
            return "缺少包 \(id)，请先下载"
        }
    }
}

/// 第一眼：Rime 目录里有没有配置、方案列表里有哪些方案、要下载哪些包做对照（设计 6.2）。不需要上游包。
public struct TakeoverSurvey: Sendable, Equatable {
    /// 没有配置文件（目录不存在，或者只有 Rime 自己的运行文件）
    public let isEmpty: Bool
    /// 方案列表里清单认识的方案，按原来的顺序（去重）
    public let schemas: [String]
    /// 方案列表里清单不认识的方案：接管后不启用，文件原样保留
    public let unknownSchemas: [String]
    /// 认识的方案所属的包，按第一次出现的顺序
    public let packages: [String]

    public init(isEmpty: Bool, schemas: [String], unknownSchemas: [String], packages: [String]) {
        self.isEmpty = isEmpty
        self.schemas = schemas
        self.unknownSchemas = unknownSchemas
        self.packages = packages
    }

    public static func scan(_ rime: URL, catalog: Catalog) throws -> TakeoverSurvey {
        guard !(try RimeFiles.configFiles(in: rime)).isEmpty else {
            return TakeoverSurvey(isEmpty: true, schemas: [], unknownSchemas: [], packages: [])
        }
        var schemas: [String] = []
        var unknown: [String] = []
        var packages: [String] = []
        for id in try schemaList(rime.resolvingSymlinksInPath()) {
            if let package = catalog.packageOwning(schema: id) {
                if !schemas.contains(id) { schemas.append(id) }
                if !packages.contains(package.id) { packages.append(package.id) }
            } else if !unknown.contains(id) {
                unknown.append(id)
            }
        }
        return TakeoverSurvey(isEmpty: false, schemas: schemas, unknownSchemas: unknown, packages: packages)
    }

    /// 方案列表：default.custom.yaml 补丁里的 schema_list 优先，没有就看 default.yaml
    static func schemaList(_ dir: URL) throws -> [String] {
        if let text = try TakeoverFiles.read(dir, "default.custom.yaml"),
           let list = PatchLeaves(try TakeoverFiles.patch(text, file: "default.custom.yaml"))["schema_list"] {
            return ids(list)
        }
        if let text = try TakeoverFiles.read(dir, "default.yaml"),
           let list = try TakeoverFiles.yaml(text, file: "default.yaml")?["schema_list"] {
            return ids(list)
        }
        return []
    }

    static func ids(_ list: Node) -> [String] {
        (list.sequence ?? []).compactMap { $0["schema"]?.string }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TakeoverSurveyTests 2>&1 | grep -E "error:|warning:|passed|failed" | tail -3`
Expected: 6 个测试通过，没有 warning

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Takeover Tests/RimeKitTests/TakeoverSurveyTests.swift
git commit -m "feat: 接管第一步：看 Rime 目录里有没有配置、有哪些方案

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 认出设置、个人词库和短语

**Files:**
- Create: `Sources/RimeKit/Takeover/TakeoverAnalyzer.swift`
- Create: `Tests/RimeKitTests/Support/TakeoverFixtures.swift`
- Modify: `Sources/RimeKit/Config/Settings.swift`（字号、每页候选数的范围改成公开常量）
- Modify: `Sources/RimeKit/Config/GenerationContext.swift`（注入短语翻译器的配置提成 `static func phraseConfig() -> Node`）
- Test: `Tests/RimeKitTests/TakeoverAnalyzerTests.swift`

**Interfaces:**
- Consumes: `TakeoverSurvey`、`TakeoverFiles`、`TakeoverError`（任务 4）；`PatchLeaves`、`YAMLNode.same`（任务 1）；`PackageSpec.userDicts`（任务 2）；`GenerationContext.isUpstreamPatch`
- Produces:
  - `public struct TakeoverProposal: Sendable, Equatable { settings: Settings; personalDicts: [URL]; manualPhrases: [Phrase]; textReplacementMatches: Int; notes: [String]; func generationInput(catalog:packages:textReplacement:) -> GenerationInput }`
  - `public enum TakeoverAnalyzer { static func analyze(_ rime: URL, catalog: Catalog, survey: TakeoverSurvey, packages: [String: CachedPackage], textReplacement: [Phrase]) throws -> TakeoverProposal }`（`packages` 至少要有 `survey.packages` 里的包）
  - `Settings.fontPointRange`、`Settings.pageSizeRange`（`ClosedRange<Int>`）
  - `GenerationContext.phraseConfig() -> Node`
  - 测试辅助 `TakeoverFixtures`：`Env`、`env()`、`analyze(_:textReplacement:)`、`install(_:from:into:)`、`put(_:_:in:)`、`wubiSample(_:into:)`、`manual`、`fromTR`、`upstream(_:_:)`

识别规则（写进设计 5.2，见任务 11）：

1. 对照用的「默认补丁」= 包里自带的 `<名字>.custom.yaml` + 认出的选项的补丁。只看 `default`、`squirrel`、这些包的方案、这些包自带补丁对应的 `.custom.yaml`；别的（如 `weasel.custom.yaml`）不看，原样保留。
2. 选项：某个选择的补丁全都在、要生成的总词库文件也在，就算选了它；几个都对得上时选条件最多的。一个都对不上就用默认值并提示；只对上一部分时提示。
3. 用户补丁的每一项：和默认补丁、应用管理的键有上下级关系的（或者和这样的项有关系的），拆成叶子逐个比：应用管理的跳过（变成设置）、和默认一样的丢掉、不一样的存成保留的补丁；其余的项整项原样保留。注入短语翻译器的两项（和应用注入的一样时）跳过。默认补丁有、用户补丁里没有的叶子，提示「接管后会按上游默认加上」。
4. 应用管理的键：`default` 的 `schema_list`、`menu/page_size`；`squirrel` 的 `style/color_scheme`、`style/color_scheme_dark`、`style/<外观键>`、实际生效的浅色和深色配色的 `preset_color_schemes/<配色>/<外观键>`。
5. 外观：实际生效的值（配色里的优先于全局 `style`，补丁优先于包里的 `squirrel.yaml`）和不接管时的默认值比，不一样才写进设置；浅色深色不一样时用浅色的并提示；值认不出或超出范围时提示、用方案默认值。每页候选数同理。
6. 个人词库：清单标出的个人词库模板和上游不一样的；所选选项总词库里「只在有个人词库时」导入、目录里也有的。总词库现在导入的词库和应用会生成的不一样时提示。
7. 短语：启用的方案用到的短语文件（规则同生成，设计 5.1 第 7 条）里，去掉上游同名文件里有的；和文本替换对得上的只计数（打开同步）；其余去重后是手动短语。

- [ ] **Step 1: 写测试辅助**

`Tests/RimeKitTests/Support/TakeoverFixtures.swift`：

```swift
import Foundation
@testable import RimeKit

/// 接管测试用的样本：用 GenFixtures 的三个自造包，照作者五笔配置的写法改（整段改写上游补丁）
enum TakeoverFixtures {
    struct Env {
        let dir: TempDir
        let rime: URL
        let catalog: Catalog
        let packages: [String: CachedPackage]
    }

    static func env() throws -> Env {
        let dir = try TempDir()
        return Env(dir: dir, rime: dir.url.appending(path: "Rime", directoryHint: .isDirectory),
                   catalog: try GenFixtures.catalog(),
                   packages: try GenFixtures.makePackages(in: dir.url.appending(path: "packages", directoryHint: .isDirectory)))
    }

    static func analyze(_ e: Env, textReplacement: [Phrase] = [fromTR]) throws -> TakeoverProposal {
        let survey = try TakeoverSurvey.scan(e.rime, catalog: e.catalog)
        return try TakeoverAnalyzer.analyze(e.rime, catalog: e.catalog, survey: survey, packages: e.packages,
                                            textReplacement: textReplacement)
    }

    static let manual = Phrase(text: "私人短语", code: "srdy", weight: 1)
    static let fromTR = Phrase(text: "替换短语", code: "thdy", weight: 1)

    static func put(_ text: String, _ path: String, in dir: URL) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// 包里的某个文件的内容
    static func upstream(_ id: String, _ path: String) -> String {
        GenFixtures.files[id]![path]!
    }

    /// 把包里的文件（不含上游补丁和 LICENSE）放进 Rime 目录，模拟用户照着上游说明装好的配置
    static func install(_ ids: [String], from packages: [String: CachedPackage], into rime: URL) throws {
        for id in ids {
            let package = packages[id]!
            for path in package.info.files where !GenerationContext.isUpstreamPatch(path) && path != "LICENSE" {
                try put(try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8), path, in: rime)
            }
        }
    }

    /// 上游 default.custom.yaml 改了方案顺序、多了一个翻页键
    static let wubiDefault = """
        patch:
          schema_list:
            - schema: wb_py
            - schema: wb
          menu:
            page_size: 5
          key_binder:
            bindings:
              - { when: has_menu, accept: bracketleft, send: Page_Up }
              - { when: has_menu, accept: minus, send: Page_Up }

        """

    /// 上游 squirrel.custom.yaml 改了字号：候选字浅色深色都是 24，序号只有浅色配色里有，改成 20
    static let wubiSquirrel = """
        patch:
          style:
            color_scheme: roseo
            color_scheme_dark: roseo_dark
          preset_color_schemes:
            roseo:
              name: 玫枫
              font_point: 24
              label_font_point: 20
            roseo_dark:
              name: 玫枫暗
              font_point: 24

        """

    /// 和应用注入的一样的短语翻译器补丁
    static let phraseInjection = """
          "engine/translators/@before 0": table_translator@custom_phrase
          custom_phrase:
            dictionary: ""
            user_dict: custom_phrase
            db_class: stabledb
            enable_completion: false
            enable_sentence: false
            initial_quality: 100

        """

    /// 五笔 + 大词库 + 两个个人词库 + 短语 + 两个应用不认识的文件
    static func wubiSample(_ packages: [String: CachedPackage], into rime: URL) throws {
        try install(["wubi", "words"], from: packages, into: rime)
        try put(wubiDefault, "default.custom.yaml", in: rime)
        try put(wubiSquirrel, "squirrel.custom.yaml", in: rime)
        try put("patch:\n  translator/dictionary: py_ext\n", "wpy.custom.yaml", in: rime)
        try put("patch:\n  reverse_lookup/dictionary: py_ext\n" + phraseInjection, "wb.custom.yaml", in: rime)
        try put("patch:\n  reverse_lookup/dictionary: py_ext\n" + phraseInjection, "wb_py.custom.yaml", in: rime)
        try put("---\nname: py_ext\nversion: \"1\"\nsort: by_weight\nimport_tables:\n  - py_user\n  - cn/a\n...\n",
                "py_ext.dict.yaml", in: rime)
        try put(GenFixtures.dict("py_user", ["私人词条\tsi ren ci tiao\t100"]), "py_user.dict.yaml", in: rime)
        try put(GenFixtures.dict("wb_user", ["私人五笔词\taaaa"]), "wb_user.dict.yaml", in: rime)
        try put(PhraseFile.header + PhraseFile.render([fromTR, manual]), "custom_phrase.txt", in: rime)
        try put("patch:\n  style/font_point: 20\n", "weasel.custom.yaml", in: rime)
        try put("随手记的东西\n", "notes.txt", in: rime)
        try put("var: {}\n", "user.yaml", in: rime)
    }
}
```

- [ ] **Step 2: 写失败的测试**

`Tests/RimeKitTests/TakeoverAnalyzerTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverAnalyzerTests {
    typealias F = TakeoverFixtures

    @Test func 手写的五笔配置() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb_py", "wb"])
        #expect(p.settings.options == ["wubi": ["pinyinDictionary": "ext"]])
        #expect(p.settings.appearance == Appearance(fontPoint: 24, labelFontPoint: 20))
        #expect(p.settings.textReplacement == TextReplacementSettings(sync: true))
        #expect(p.settings.preservedPatches.keys.sorted() == ["default"])
        let bindings = try #require(p.settings.preservedPatches["default"]?.first)
        #expect(p.settings.preservedPatches["default"]?.count == 1)
        #expect(bindings.key == "key_binder/bindings")
        #expect(bindings.yaml.contains("minus"))
        #expect(p.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(p.manualPhrases == [F.manual])
        #expect(p.textReplacementMatches == 1)
        #expect(p.notes.isEmpty, "\(p.notes)")
    }

    @Test func 没有文本替换时短语都是手动的() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e, textReplacement: [])
        #expect(p.manualPhrases == [F.fromTR, F.manual])
        #expect(p.textReplacementMatches == 0)
        #expect(p.settings.textReplacement == TextReplacementSettings(sync: false))
    }

    @Test func 没有选项补丁时是自带词库() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb", "wb_py"])
        #expect(p.settings.options == ["wubi": ["pinyinDictionary": "builtin"]])
        #expect(p.settings.appearance == Appearance())
        #expect(p.settings.preservedPatches.isEmpty)
        #expect(p.personalDicts.isEmpty)
        #expect(p.notes.isEmpty, "\(p.notes)")
    }

    @Test func 只认出一部分选项补丁时提示_认不出的原样保留() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        try F.put("patch:\n  translator/dictionary: py_ext\n", "wpy.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.options == ["wubi": ["pinyinDictionary": "builtin"]])
        #expect(p.notes.contains { $0.contains("只认出一部分") })
        #expect(p.settings.preservedPatches["wpy"]?.map(\.key) == ["translator/dictionary"])
    }

    @Test func 深色字号和浅色不一样时用浅色的() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        try F.put(F.upstream("wubi", "squirrel.custom.yaml")
                    .replacingOccurrences(of: "      font_point: 18\n      label_font_point: 17", with: "      font_point: 24\n      label_font_point: 17")
                    .replacingOccurrences(of: "      name: 玫枫暗\n      font_point: 18", with: "      name: 玫枫暗\n      font_point: 22"),
                  "squirrel.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.appearance == Appearance(fontPoint: 24))
        #expect(p.notes.contains { $0.contains("深色") && $0.contains("font_point") })
        #expect(p.settings.preservedPatches.isEmpty)
    }

    @Test func 自己写的简短default补丁会提示上游默认项() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put("patch:\n  schema_list:\n    - schema: wb\n", "default.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb"])
        #expect(p.notes.contains { $0.contains("default.custom.yaml") && $0.contains("key_binder/bindings") })
        #expect(p.settings.preservedPatches["default"] == nil)
    }

    @Test func 和默认无关的整段补丁原样保留_含外观键的整段拆开() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["pinyin"], from: e.packages, into: e.rime)
        try F.put("patch:\n  schema_list:\n    - schema: py\n", "default.custom.yaml", in: e.rime)
        try F.put("""
            patch:
              style:
                font_point: 20
                corner_radius: 5
              app_options:
                com.example.app:
                  ascii_mode: true

            """, "squirrel.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.appearance == Appearance(fontPoint: 20))
        #expect(p.settings.preservedPatches["squirrel"]?.map(\.key) == ["app_options", "style/corner_radius"])
        #expect(p.notes.isEmpty, "\(p.notes)")
    }

    @Test func 每页候选数和上游默认不一样才写进设置() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml").replacingOccurrences(of: "page_size: 5", with: "page_size: 7"),
                  "default.custom.yaml", in: e.rime)
        #expect(try F.analyze(e).settings.appearance == Appearance(pageSize: 7))
    }

    @Test func 认不出的方案会提示() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml").replacingOccurrences(of: "    - schema: wb_py\n", with: "    - schema: wb_py\n    - schema: luna_pinyin\n"),
                  "default.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb", "wb_py"])
        #expect(p.notes.contains { $0.contains("luna_pinyin") })
    }

    @Test func 一个方案都认不出() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.put("随手记\n", "notes.txt", in: e.rime)
        #expect(throws: TakeoverError.nothingRecognized) { try F.analyze(e) }
    }

    @Test func 用户改过的上游个人词库模板才算个人词库() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)   // wb_user.dict.yaml 和上游一样
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        #expect(try F.analyze(e).personalDicts.isEmpty)
    }

    @Test func 总词库导入的词库和应用生成的不一样时提示() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        try F.put("---\nname: py_ext\nimport_tables:\n  - py_user\n  - cn/a\n  - my_extra\n...\n", "py_ext.dict.yaml", in: e.rime)
        #expect(try F.analyze(e).notes.contains { $0.contains("py_ext.dict.yaml") && $0.contains("my_extra") })
    }

    @Test func 包没给全时报错() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let survey = try TakeoverSurvey.scan(e.rime, catalog: e.catalog)
        #expect(throws: TakeoverError.missingPackage("wubi")) {
            try TakeoverAnalyzer.analyze(e.rime, catalog: e.catalog, survey: survey, packages: [:], textReplacement: [])
        }
    }
}
```

> 注：`GenFixtures.files["wubi"]` 里 `squirrel.custom.yaml` 的浅色配色是 `      font_point: 18\n      label_font_point: 17`，深色是 `      name: 玫枫暗\n      font_point: 18`；`default.custom.yaml` 里有 `    - schema: wb_py\n` 和 `page_size: 5`。上面的替换依赖这些原文。

- [ ] **Step 3: 运行，确认失败**

Run: `swift test --filter TakeoverAnalyzerTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`cannot find 'TakeoverAnalyzer' in scope`

- [ ] **Step 4: 两处小重构**

`Sources/RimeKit/Config/Settings.swift`：
1. `public static let currentFormatVersion = 1` 后面加：

```swift
    /// 字号的范围（候选字、序号、注释）
    public static let fontPointRange = 8...72
    /// 每页候选数的范围
    public static let pageSizeRange = 1...10
```

2. `validate` 里四行 `try Self.check(...)` 改成用这两个常量：

```swift
        try Self.check("候选字字号", appearance.fontPoint, Self.fontPointRange)
        try Self.check("序号字号", appearance.labelFontPoint, Self.fontPointRange)
        try Self.check("注释字号", appearance.commentFontPoint, Self.fontPointRange)
        try Self.check("每页候选数", appearance.pageSize, Self.pageSizeRange)
```

`Sources/RimeKit/Config/GenerationContext.swift`：
1. 在 `// MARK: 规则 7：短语` 下面、`func applyPhrases()` 前面加：

```swift
    /// 注入短语翻译器时写的 custom_phrase 配置（接管时也用它认出这段补丁）
    static func phraseConfig() -> Node {
        YAMLNode.map([
            ("dictionary", YAMLNode.text("")),
            ("user_dict", YAMLNode.text("custom_phrase")),
            ("db_class", YAMLNode.text("stabledb")),
            ("enable_completion", YAMLNode.bool(false)),
            ("enable_sentence", YAMLNode.bool(false)),
            ("initial_quality", YAMLNode.int(100)),
        ])
    }
```

2. `applyPhrases()` 里 `p.set("custom_phrase", YAMLNode.map([ … ]))` 那整段改成 `p.set("custom_phrase", Self.phraseConfig())`。

Run: `swift test --filter "Generator|Settings" 2>&1 | grep -E "error:|Test run" | tail -2`
Expected: 通过（重构不改行为）

- [ ] **Step 5: 实现识别**

`Sources/RimeKit/Takeover/TakeoverAnalyzer.swift`：

```swift
import Foundation
import Yams

/// 认出来的东西（设计 6.2）：用户确认后保存成设置和个人内容，再按 6.1 应用
public struct TakeoverProposal: Sendable, Equatable {
    public var settings: Settings
    /// 要收进 personal/dicts 的个人词库（现在在 Rime 目录里的位置），按文件名排序
    public var personalDicts: [URL]
    /// 要收进 personal/phrases.txt 的手动短语
    public var manualPhrases: [Phrase]
    /// 短语文件里和 macOS 文本替换一样的条数：这些不算手动短语，接管后由文本替换同步生成
    public var textReplacementMatches: Int
    /// 要告诉用户的地方：认不出的、接管后会变的
    public var notes: [String]

    public init(settings: Settings, personalDicts: [URL], manualPhrases: [Phrase], textReplacementMatches: Int, notes: [String]) {
        self.settings = settings
        self.personalDicts = personalDicts
        self.manualPhrases = manualPhrases
        self.textReplacementMatches = textReplacementMatches
        self.notes = notes
    }

    /// 按识别结果生成配置用的输入（文本替换同步打开时才带上文本替换）
    public func generationInput(catalog: Catalog, packages: [String: CachedPackage], textReplacement: [Phrase]) -> GenerationInput {
        GenerationInput(settings: settings, catalog: catalog, packages: packages,
                        personal: PersonalContent(dicts: personalDicts, phrases: manualPhrases),
                        textReplacementPhrases: settings.textReplacement.sync ? textReplacement : [])
    }
}

/// 认出已有 Rime 目录里的配置。只读，不改任何文件。规则见设计 5.2。
public enum TakeoverAnalyzer {
    public static func analyze(_ rime: URL, catalog: Catalog, survey: TakeoverSurvey,
                               packages: [String: CachedPackage], textReplacement: [Phrase]) throws -> TakeoverProposal {
        guard !survey.schemas.isEmpty else { throw TakeoverError.nothingRecognized }
        return try TakeoverAnalysis(rime: rime, catalog: catalog, survey: survey, packages: packages,
                                    textReplacement: textReplacement).run()
    }
}

/// 一次识别的过程和中间状态
final class TakeoverAnalysis {
    static let appearanceKeys = ["font_point", "label_font_point", "comment_font_point", "candidate_list_layout", "text_orientation"]
    static let phraseTranslator = "table_translator@custom_phrase"

    struct Schemes {
        var light: String?
        var dark: String?
        var baseLight: String?
        var baseDark: String?
    }

    let rime: URL
    let catalog: Catalog
    let survey: TakeoverSurvey
    let packages: [String: CachedPackage]
    let textReplacement: [Phrase]
    let specs: [PackageSpec]
    let files: Set<String>
    /// 配置名 → Rime 目录里现在的补丁
    var existing: [String: Patch] = [:]
    /// 配置名 → 不接管时生成器会写的默认补丁：上游自带的 + 所选选项的
    var expected: [String: Patch] = [:]
    var chosen: [OptionChoice] = []
    var schemes = Schemes()
    var notes: [String] = []

    init(rime: URL, catalog: Catalog, survey: TakeoverSurvey, packages: [String: CachedPackage], textReplacement: [Phrase]) throws {
        self.rime = rime.resolvingSymlinksInPath()
        self.catalog = catalog
        self.survey = survey
        self.packages = packages
        self.textReplacement = textReplacement
        specs = try catalog.installOrder(for: survey.packages)
        for spec in specs where packages[spec.id] == nil { throw TakeoverError.missingPackage(spec.id) }
        files = Set(try RimeFiles.configFiles(in: rime))
    }

    func run() throws -> TakeoverProposal {
        try loadPatches()
        let options = detectOptions()
        let personalDicts = detectPersonalDicts()
        try checkGeneratedDicts(personal: personalDicts)
        let appearance = try detectAppearance()
        var preserved: [String: [PreservedPatch]] = [:]
        for name in existing.keys.sorted() {
            let items = try preservedItems(name)
            if !items.isEmpty { preserved[name] = items }
        }
        let (manual, matches) = try detectPhrases()
        if !survey.unknownSchemas.isEmpty {
            notes.append("方案列表里的 \(survey.unknownSchemas.joined(separator: "、")) 不在方案清单里，接管后不会出现在方案列表里（文件原样保留）")
        }
        let settings = Settings(schemas: survey.schemas, options: options, appearance: appearance,
                                textReplacement: TextReplacementSettings(sync: matches > 0), preservedPatches: preserved)
        try settings.validate(catalog)
        return TakeoverProposal(settings: settings, personalDicts: personalDicts, manualPhrases: manual,
                                textReplacementMatches: matches, notes: notes)
    }

    // MARK: 读补丁（规则 1）

    func loadPatches() throws {
        var names = ["default", "squirrel"]
        for spec in specs {
            names += spec.schemas.map(\.id)
            names += upstreamPatchNames(spec)
        }
        for name in names where existing[name] == nil {
            let file = "\(name).custom.yaml"
            guard files.contains(file), let text = try TakeoverFiles.read(rime, file) else { continue }
            existing[name] = try TakeoverFiles.patch(text, file: file)
        }
        for spec in specs {
            let package = packages[spec.id]!
            for name in upstreamPatchNames(spec) {
                let path = "\(name).custom.yaml"
                let text = try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8)
                expected[name, default: Patch()].merge(try TakeoverFiles.patch(text, file: "\(spec.id)/\(path)"))
            }
        }
    }

    func upstreamPatchNames(_ spec: PackageSpec) -> [String] {
        packages[spec.id]!.info.files.filter(GenerationContext.isUpstreamPatch).map { String($0.dropLast(".custom.yaml".count)) }
    }

    /// 包里的文件：生成时后复制的包覆盖先复制的，所以从后往前找
    func upstreamURL(_ path: String) -> URL? {
        for spec in specs.reversed() {
            let package = packages[spec.id]!
            if package.info.files.contains(path) { return package.filesDirectory.appending(path: path) }
        }
        return nil
    }

    func upstreamYAML(_ path: String) throws -> Node? {
        guard let url = upstreamURL(path) else { return nil }
        return try TakeoverFiles.yaml(try String(contentsOf: url, encoding: .utf8), file: path)
    }

    // MARK: 选项（规则 2）

    func detectOptions() -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for spec in specs {
            for option in spec.options {
                var best: (choice: OptionChoice, size: Int)?
                var partial = false
                for choice in option.choices {
                    let (matched, total) = score(choice)
                    if matched == total {
                        if best == nil || total > best!.size { best = (choice, total) }
                    } else if matched > 0 {
                        partial = true
                    }
                }
                let choice = best?.choice ?? option.choice(option.defaultChoice) ?? option.choices[0]
                if best == nil {
                    notes.append("认不出「\(spec.name)」的「\(option.name)」，接管后用「\(choice.name)」")
                } else if partial {
                    notes.append("「\(spec.name)」的「\(option.name)」只认出一部分设置，接管后用「\(choice.name)」，认不出的补丁原样保留")
                }
                result[spec.id, default: [:]][option.id] = choice.id
                chosen.append(choice)
                for (schema, values) in choice.patches.sorted(by: { $0.key < $1.key }) {
                    for (key, value) in values.sorted(by: { $0.key < $1.key }) {
                        expected[schema, default: Patch()].set(key, YAMLNode.text(value))
                    }
                }
            }
        }
        return result
    }

    /// 这个选择的条件（补丁项 + 要生成的总词库）对上了几条、一共几条
    func score(_ choice: OptionChoice) -> (matched: Int, total: Int) {
        var matched = 0
        var total = 0
        for (schema, values) in choice.patches {
            let leaves = PatchLeaves(existing[schema] ?? Patch())
            for (key, value) in values {
                total += 1
                if leaves[key]?.string == value { matched += 1 }
            }
        }
        for dict in choice.generatedDicts {
            total += 1
            if files.contains("\(dict.name).dict.yaml") { matched += 1 }
        }
        return (matched, total)
    }

    // MARK: 个人词库（规则 6）

    func detectPersonalDicts() -> [URL] {
        var names: [String] = []
        for spec in specs {
            let package = packages[spec.id]!
            for file in spec.userDicts where files.contains(file) {
                let upstream = package.filesDirectory.appending(path: file)
                if FileManager.default.contentsEqual(atPath: rime.appending(path: file).path, andPath: upstream.path) { continue }
                names.append(file)
            }
        }
        for choice in chosen {
            for dict in choice.generatedDicts {
                for table in dict.importTables where table.onlyIfPersonal {
                    let file = "\(table.name).dict.yaml"
                    if files.contains(file), !names.contains(file) { names.append(file) }
                }
            }
        }
        return names.sorted().map { rime.appending(path: $0) }
    }

    func checkGeneratedDicts(personal: [URL]) throws {
        let personalNames = Set(personal.map(\.lastPathComponent))
        for choice in chosen {
            for dict in choice.generatedDicts {
                let file = "\(dict.name).dict.yaml"
                guard files.contains(file), let text = try TakeoverFiles.read(rime, file) else { continue }
                let want = dict.importTables
                    .filter { !$0.onlyIfPersonal || personalNames.contains("\($0.name).dict.yaml") }
                    .map(\.name)
                let have = TakeoverFiles.importTables(text) ?? []
                if have != want {
                    notes.append("\(file) 现在导入的词库是 \(have.joined(separator: "、"))；接管后由应用生成，导入 \(want.joined(separator: "、"))")
                }
            }
        }
    }

    // MARK: 外观（规则 4、5）

    func detectAppearance() throws -> Appearance {
        var appearance = Appearance()
        let file = try upstreamYAML("squirrel.yaml")
        let mine = PatchLeaves(existing["squirrel"] ?? Patch())
        let base = PatchLeaves(expected["squirrel"] ?? Patch())
        let baseLight = base["style/color_scheme"]?.string ?? file?["style"]?["color_scheme"]?.string
        let baseDark = base["style/color_scheme_dark"]?.string ?? file?["style"]?["color_scheme_dark"]?.string
        schemes = Schemes(light: mine["style/color_scheme"]?.string ?? baseLight,
                          dark: mine["style/color_scheme_dark"]?.string ?? baseDark,
                          baseLight: baseLight, baseDark: baseDark)
        if schemes.light != baseLight { appearance.colorScheme = schemes.light }
        if schemes.dark != baseDark { appearance.colorSchemeDark = schemes.dark }

        for key in Self.appearanceKeys {
            /// 鼠须管先看配色里的，再看全局 style；补丁优先于包里的 squirrel.yaml
            func value(_ layers: [PatchLeaves], scheme: String?) -> Node? {
                if let scheme {
                    for layer in layers { if let v = layer["preset_color_schemes/\(scheme)/\(key)"] { return v } }
                    if let v = file?["preset_color_schemes"]?[scheme]?[key] { return v }
                }
                for layer in layers { if let v = layer["style/\(key)"] { return v } }
                return file?["style"]?[key]
            }
            func changed(_ now: Node?, _ before: Node?) -> Bool {
                guard let now else { return false }
                return before.map { !YAMLNode.same($0, now) } ?? true
            }
            let light = value([mine, base], scheme: schemes.light)
            let dark = value([mine, base], scheme: schemes.dark)
            let lightChanged = changed(light, value([base], scheme: baseLight))
            let darkChanged = changed(dark, value([base], scheme: baseDark))
            guard lightChanged || darkChanged, let picked = lightChanged ? light : dark else { continue }
            if let light, let dark, !YAMLNode.same(light, dark) {
                notes.append("浅色和深色配色的 \(key) 不一样（\(light.string ?? "")、\(dark.string ?? "")），接管后都用 \(picked.string ?? "")")
            }
            if !set(&appearance, key, picked) {
                notes.append("认不出 \(key) 的值「\(picked.string ?? "")」，接管后用方案默认值")
            }
        }

        if let size = PatchLeaves(existing["default"] ?? Patch())["menu/page_size"] {
            let before = try PatchLeaves(expected["default"] ?? Patch())["menu/page_size"]
                ?? upstreamYAML("default.yaml")?["menu"]?["page_size"]
            if before.map({ !YAMLNode.same($0, size) }) ?? true {
                if let n = Int(size.string ?? ""), Settings.pageSizeRange.contains(n) {
                    appearance.pageSize = n
                } else {
                    notes.append("认不出每页候选数「\(size.string ?? "")」，接管后用方案默认值")
                }
            }
        }
        return appearance
    }

    /// 写进设置；值认不出或超出范围时返回 false
    func set(_ appearance: inout Appearance, _ key: String, _ value: Node) -> Bool {
        let text = value.string ?? ""
        switch key {
        case "font_point", "label_font_point", "comment_font_point":
            guard let n = Int(text), Settings.fontPointRange.contains(n) else { return false }
            if key == "font_point" { appearance.fontPoint = n }
            if key == "label_font_point" { appearance.labelFontPoint = n }
            if key == "comment_font_point" { appearance.commentFontPoint = n }
        case "candidate_list_layout":
            guard let v = CandidateListLayout(rawValue: text) else { return false }
            appearance.candidateListLayout = v
        case "text_orientation":
            guard let v = TextOrientation(rawValue: text) else { return false }
            appearance.textOrientation = v
        default:
            return false
        }
        return true
    }

    // MARK: 保留的补丁（规则 3、4）

    /// 应用管理的键：生成时由设置写出
    func managedPaths(_ name: String) -> [String] {
        switch name {
        case "default":
            return ["schema_list", "menu/page_size"]
        case "squirrel":
            var paths = ["style/color_scheme", "style/color_scheme_dark"] + Self.appearanceKeys.map { "style/\($0)" }
            for scheme in [schemes.light, schemes.dark].compactMap({ $0 }) {
                paths += Self.appearanceKeys.map { "preset_color_schemes/\(scheme)/\($0)" }
            }
            return paths
        default:
            return []
        }
    }

    /// 应用注入短语翻译器的两项：有短语时生成器会再写
    func isPhraseInjection(_ entry: Patch.Entry) -> Bool {
        switch entry.key {
        case "engine/translators/@before 0": return entry.value.string == Self.phraseTranslator
        case "custom_phrase": return YAMLNode.same(entry.value, GenerationContext.phraseConfig())
        default: return false
        }
    }

    func preservedItems(_ name: String) throws -> [PreservedPatch] {
        guard let mine = existing[name] else { return [] }
        let base = expected[name] ?? Patch()
        let baseLeaves = PatchLeaves(base)
        let managed = managedPaths(name)
        let entries = mine.entries.filter { !isPhraseInjection($0) }

        // 和默认补丁、应用管理的键有上下级关系的项（以及和这些项有关系的项）逐个叶子比；其余整项原样保留
        var anchors = base.entries.map(\.key) + managed
        var related = Set<String>()
        var grew = true
        while grew {
            grew = false
            for entry in entries where !related.contains(entry.key) && anchors.contains(where: { PatchLeaves.overlaps($0, entry.key) }) {
                related.insert(entry.key)
                anchors.append(entry.key)
                grew = true
            }
        }
        var items: [PreservedPatch] = []
        for entry in entries where !related.contains(entry.key) {
            items.append(try Self.preserved(entry.key, entry.value))
        }
        var leaves = PatchLeaves()
        for entry in entries where related.contains(entry.key) { leaves.set(entry.key, entry.value) }
        for path in leaves.paths {
            let leaf = leaves[path]!
            if managed.contains(path) { continue }
            if let b = baseLeaves[path], YAMLNode.same(b, leaf) { continue }
            items.append(try Self.preserved(path, leaf))
        }

        let all = PatchLeaves(mine)
        let missing = baseLeaves.paths.filter { all[$0] == nil && !managed.contains($0) }
        if !missing.isEmpty {
            notes.append("\(name).custom.yaml 里没有上游默认补丁的这些项，接管后会按上游默认加上：\(missing.joined(separator: "、"))")
        }
        return items
    }

    static func preserved(_ key: String, _ value: Node) throws -> PreservedPatch {
        PreservedPatch(key: key, yaml: try Yams.serialize(node: value, allowUnicode: true))
    }

    // MARK: 短语（规则 7）

    func detectPhrases() throws -> (manual: [Phrase], matches: Int) {
        var phraseFiles: [String] = []
        for schema in survey.schemas {
            guard let root = try upstreamYAML("\(schema).schema.yaml") else { continue }
            let translators = root["engine"]?["translators"]?.sequence?.compactMap(\.string) ?? []
            let file = translators.contains(Self.phraseTranslator)
                ? (root["custom_phrase"]?["user_dict"]?.string ?? "custom_phrase") + ".txt"
                : "custom_phrase.txt"
            if !phraseFiles.contains(file) { phraseFiles.append(file) }
        }
        let fromTextReplacement = Set(textReplacement.map { $0.text + "\t" + $0.code })
        var manual: [Phrase] = []
        var seen = Set<String>()
        var matched = Set<String>()
        for file in phraseFiles {
            guard files.contains(file), let text = try TakeoverFiles.read(rime, file) else { continue }
            var upstream = Set<String>()
            if let url = upstreamURL(file) {
                upstream = Set(PhraseFile.parse(try String(contentsOf: url, encoding: .utf8)).map { $0.text + "\t" + $0.code })
            }
            for phrase in PhraseFile.parse(text) {
                let key = phrase.text + "\t" + phrase.code
                if upstream.contains(key) { continue }
                if fromTextReplacement.contains(key) {
                    matched.insert(key)
                    continue
                }
                if seen.insert(phrase.line).inserted { manual.append(phrase) }
            }
        }
        return (manual, matched.count)
    }
}
```

- [ ] **Step 6: 运行，确认通过**

Run: `swift test --filter TakeoverAnalyzerTests 2>&1 | grep -E "error:|warning:|passed|failed" | tail -5`
Expected: 13 个测试通过，没有 warning

- [ ] **Step 7: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit Tests/RimeKitTests
git commit -m "feat: 接管时认出方案、选项、外观、保留的补丁、个人词库和短语

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 预览：接管后哪些文件会变

**Files:**
- Create: `Sources/RimeKit/Takeover/TakeoverPreview.swift`
- Test: `Tests/RimeKitTests/TakeoverPreviewTests.swift`

**Interfaces:**
- Consumes: `TakeoverProposal.generationInput`（任务 5）、`ConfigGenerator`、`RimeFiles.configFiles`
- Produces: `public struct TakeoverPreview: Sendable, Equatable { replaced, unchanged, added, kept: [String]; warnings: [String]; static func make(_ proposal: TakeoverProposal, rime: URL, catalog: Catalog, packages: [String: CachedPackage], textReplacement: [Phrase], staging: URL) throws -> TakeoverPreview }`（`packages` 要有 `proposal.settings.requiredPackages` 里的所有包）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/TakeoverPreviewTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverPreviewTests {
    typealias F = TakeoverFixtures

    func preview(_ e: F.Env, _ p: TakeoverProposal) throws -> TakeoverPreview {
        try TakeoverPreview.make(p, rime: e.rime, catalog: e.catalog, packages: e.packages,
                                 textReplacement: [F.fromTR], staging: e.dir.url.appending(path: "staging", directoryHint: .isDirectory))
    }

    /// 目录里每个文件的哈希
    func snapshot(_ dir: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: dir.path) {
            let url = dir.appending(path: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                result[path] = try Hashing.sha256(of: url)
            }
        }
        return result
    }

    @Test func 应用生成的配置接管后什么都不变() throws {
        let e = try F.env(); defer { e.dir.remove() }
        let personalDir = e.dir.url.appending(path: "personal", directoryHint: .isDirectory)
        try F.put(GenFixtures.dict("py_user", ["私人词条\tsi ren ci tiao\t100"]), "py_user.dict.yaml", in: personalDir)
        try F.put(GenFixtures.dict("wb_user", ["私人五笔词\taaaa"]), "wb_user.dict.yaml", in: personalDir)
        let settings = Settings(
            schemas: ["wb_py", "wb", "py"],
            options: ["wubi": ["pinyinDictionary": "ext"]],
            appearance: Appearance(fontPoint: 24, labelFontPoint: 20, pageSize: 7),
            textReplacement: TextReplacementSettings(sync: true),
            preservedPatches: ["default": [PreservedPatch(key: "key_binder/bindings",
                                                          yaml: "- {when: has_menu, accept: minus, send: Page_Up}\n")]])
        let personal = PersonalContent(dicts: [personalDir.appending(path: "py_user.dict.yaml"), personalDir.appending(path: "wb_user.dict.yaml")],
                                       phrases: [F.manual])
        _ = try ConfigGenerator().generate(
            GenFixtures.input(settings, packages: e.packages, personal: personal, textReplacement: [F.fromTR]), into: e.rime)

        let p = try F.analyze(e)
        #expect(p.settings.schemas == settings.schemas)
        #expect(p.settings.options == settings.options)
        #expect(p.settings.appearance == settings.appearance)
        #expect(p.settings.textReplacement == settings.textReplacement)
        #expect(p.settings.preservedPatches["default"]?.map(\.key) == ["key_binder/bindings"])
        #expect(p.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(p.manualPhrases == [F.manual])
        #expect(p.textReplacementMatches == 1)
        #expect(p.notes.isEmpty, "\(p.notes)")

        let v = try preview(e, p)
        #expect(v.replaced == [], "\(v.replaced)")
        #expect(v.added == [])
        #expect(v.kept == [])
    }

    @Test func 手写样本的预览() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let before = try snapshot(e.rime)
        let v = try preview(e, try F.analyze(e))
        #expect(v.kept == ["notes.txt", "weasel.custom.yaml"])
        #expect(v.replaced.contains("default.custom.yaml"))
        #expect(v.replaced.contains("squirrel.custom.yaml"))
        #expect(v.unchanged.contains("wb.dict.yaml"))
        #expect(v.unchanged.contains("wb_user.dict.yaml"))
        #expect(v.added == [])
        #expect(try snapshot(e.rime) == before)   // 预览不改 Rime 目录
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.dir.url.appending(path: "staging").path).isEmpty)
    }

    @Test func 用户直接改过的上游文件会被换掉() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "wb.dict.yaml") + "自己加的\tzjjd\n", "wb.dict.yaml", in: e.rime)
        #expect(try preview(e, try F.analyze(e)).replaced.contains("wb.dict.yaml"))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TakeoverPreviewTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`cannot find 'TakeoverPreview' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Takeover/TakeoverPreview.swift`：

```swift
import Foundation

/// 接管后哪些文件会变：在暂存区按识别结果生成一遍，和现在的 Rime 目录逐个文件比。只读，不改 Rime 目录。
public struct TakeoverPreview: Sendable, Equatable {
    /// 现在有、接管后内容会变（上游的新版本、应用重新生成的补丁等）
    public let replaced: [String]
    /// 现在有、内容一样，只是以后归应用管
    public let unchanged: [String]
    /// 现在没有、接管后新加的
    public let added: [String]
    /// 应用不管、原样保留的
    public let kept: [String]
    /// 生成时的提醒
    public let warnings: [String]

    public static func make(_ proposal: TakeoverProposal, rime: URL, catalog: Catalog, packages: [String: CachedPackage],
                            textReplacement: [Phrase], staging: URL) throws -> TakeoverPreview {
        let fm = FileManager.default
        let out = staging.appending(path: "takeover-preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: out) }
        let input = proposal.generationInput(catalog: catalog, packages: packages, textReplacement: textReplacement)
        let result = try ConfigGenerator().generate(input, into: out)
        let dir = rime.resolvingSymlinksInPath()
        let existing = Set(try RimeFiles.configFiles(in: rime))
        var replaced: [String] = []
        var unchanged: [String] = []
        var added: [String] = []
        for file in result.files {
            guard existing.contains(file.path) else {
                added.append(file.path)
                continue
            }
            if fm.contentsEqual(atPath: dir.appending(path: file.path).path, andPath: out.appending(path: file.path).path) {
                unchanged.append(file.path)
            } else {
                replaced.append(file.path)
            }
        }
        let generated = Set(result.files.map(\.path))
        return TakeoverPreview(replaced: replaced, unchanged: unchanged, added: added,
                               kept: existing.subtracting(generated).sorted(), warnings: result.warnings)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TakeoverPreviewTests 2>&1 | grep -E "error:|warning:|passed|failed" | tail -5`
Expected: 3 个测试通过

如果「应用生成的配置接管后什么都不变」里 `replaced` 不为空：先看是哪个文件、差在哪里（`diff` 两边），找到认错的地方修识别逻辑，不要改测试。

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Takeover/TakeoverPreview.swift Tests/RimeKitTests/TakeoverPreviewTests.swift
git commit -m "feat: 接管预览：列出会换掉、不变、新加、原样保留的文件

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 确认接管

**Files:**
- Create: `Sources/RimeKit/Takeover/TakeoverApplier.swift`
- Test: `Tests/RimeKitTests/TakeoverApplierTests.swift`

**Interfaces:**
- Consumes: `Deployer.apply(_:options:)`、`ApplyOutcome`、`Ledger.load`、`SettingsStore`、`PhraseFile`（已有）；`TakeoverProposal`（任务 5）
- Produces: `public struct TakeoverApplier: Sendable { init(deployer: Deployer); func confirm(_ proposal: TakeoverProposal, catalog: Catalog, packages: [String: CachedPackage], textReplacement: [Phrase], force: Bool) async throws -> ApplyOutcome }`
  - 已经由应用管理 → 抛 `TakeoverError.alreadyManaged`；已有设置且没加 `force` → 抛 `TakeoverError.settingsExist`
  - 走 `Deployer.apply`（`overwriteExternalChanges: true`：用户确认的就是这些覆盖；第一次的备份永久保留）
  - 结果是 `.applied` 才保存设置、换掉 `personal/`（个人词库 + 手动短语）；其它结果什么都不保存

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/TakeoverApplierTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverApplierTests {
    typealias F = TakeoverFixtures

    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let catalog: Catalog
        let packages: [String: CachedPackage]
        let squirrel: FakeSquirrel

        func deployer(_ compiler: FakeCompiler = FakeCompiler()) -> Deployer {
            Deployer(paths: paths, locations: locations, compiler: compiler, squirrel: squirrel,
                     watcher: DeployFixtures.watcher(locations))
        }

        func proposal() throws -> TakeoverProposal {
            let survey = try TakeoverSurvey.scan(locations.rimeDirectory, catalog: catalog)
            return try TakeoverAnalyzer.analyze(locations.rimeDirectory, catalog: catalog, survey: survey,
                                                packages: packages, textReplacement: [F.fromTR])
        }

        func confirm(_ compiler: FakeCompiler = FakeCompiler(), force: Bool = false) async throws -> ApplyOutcome {
            try await TakeoverApplier(deployer: deployer(compiler))
                .confirm(try proposal(), catalog: catalog, packages: packages, textReplacement: [F.fromTR], force: force)
        }
    }

    func env() throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let packages = try GenFixtures.makePackages(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        try F.wubiSample(packages, into: locations.rimeDirectory)
        return Env(dir: dir, paths: paths, locations: locations, catalog: try GenFixtures.catalog(), packages: packages,
                   squirrel: FakeSquirrel(locations: locations, running: true))
    }

    @Test func 确认后写入并保存设置和个人内容() async throws {
        let e = try env(); defer { e.dir.remove() }
        let expected = try e.proposal()
        guard case .applied(let report) = try await e.confirm() else { Issue.record("没有写入"); return }
        #expect(report.backup.permanent)
        #expect(try SettingsStore(paths: e.paths).load() == expected.settings)
        let personal = try PersonalContent.load(from: e.paths)
        #expect(personal.dicts.map(\.lastPathComponent) == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(personal.phrases == [F.manual])
        #expect(!(try Ledger.load(e.paths).entries.isEmpty))
        // 应用不认识的文件原样保留
        #expect(try String(contentsOf: e.locations.rimeDirectory.appending(path: "notes.txt"), encoding: .utf8) == "随手记的东西\n")
        #expect(try String(contentsOf: e.locations.rimeDirectory.appending(path: "weasel.custom.yaml"), encoding: .utf8) == "patch:\n  style/font_point: 20\n")
    }

    @Test func 接管后再应用一次什么都不写() async throws {
        let e = try env(); defer { e.dir.remove() }
        guard case .applied = try await e.confirm() else { Issue.record("没有写入"); return }
        let settings = try #require(try SettingsStore(paths: e.paths).load())
        let input = GenerationInput(settings: settings, catalog: e.catalog, packages: e.packages,
                                    personal: try PersonalContent.load(from: e.paths), textReplacementPhrases: [F.fromTR])
        guard case .applied(let again) = try await e.deployer().apply(input) else { Issue.record("第二次没有写入"); return }
        #expect(again.written == [])
        #expect(again.removed == [])
    }

    @Test func 已经有设置时不加force就不接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        try SettingsStore(paths: e.paths).save(Settings(schemas: ["wb"]))
        await #expect(throws: TakeoverError.settingsExist(e.paths.settingsFile.path)) { try await e.confirm() }
        #expect(try Ledger.load(e.paths).entries.isEmpty)
        guard case .applied = try await e.confirm(force: true) else { Issue.record("加了 force 也没有写入"); return }
    }

    @Test func 已经由应用管理时不接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(e.paths)
        await #expect(throws: TakeoverError.alreadyManaged) { try await e.confirm() }
    }

    @Test func 编译失败时什么都不保存() async throws {
        let e = try env(); defer { e.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        guard case .compileFailed = try await e.confirm(failing) else { Issue.record("应该编译失败"); return }
        #expect(!FileManager.default.fileExists(atPath: e.paths.settingsFile.path))
        #expect(!FileManager.default.fileExists(atPath: e.paths.personal.path))
        #expect(try Ledger.load(e.paths).entries.isEmpty)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter TakeoverApplierTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`cannot find 'TakeoverApplier' in scope`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Takeover/TakeoverApplier.swift`：

```swift
import Foundation

/// 用户确认接管后：按识别结果走 6.1 写入；写入成功后才保存设置和个人内容
public struct TakeoverApplier: Sendable {
    let deployer: Deployer

    public init(deployer: Deployer) {
        self.deployer = deployer
    }

    public func confirm(_ proposal: TakeoverProposal, catalog: Catalog, packages: [String: CachedPackage],
                        textReplacement: [Phrase], force: Bool) async throws -> ApplyOutcome {
        let paths = deployer.paths
        let fm = FileManager.default
        guard try Ledger.load(paths).entries.isEmpty else { throw TakeoverError.alreadyManaged }
        if fm.fileExists(atPath: paths.settingsFile.path), !force {
            throw TakeoverError.settingsExist(paths.settingsFile.path)
        }

        // 个人词库先复制一份到暂存区：写入后才放进 personal/，中途停下不会动正本
        let work = paths.staging.appending(path: "takeover-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        let dicts = work.appending(path: "dicts", directoryHint: .isDirectory)
        try fm.createDirectory(at: dicts, withIntermediateDirectories: true)
        var staged = proposal
        staged.personalDicts = try proposal.personalDicts.map { url in
            let target = dicts.appending(path: url.lastPathComponent)
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: target)
            return target
        }

        // 用户在预览里确认的就是这些覆盖；第一次的备份永久保留（Deployer.apply 负责）
        let outcome = try await deployer.apply(
            staged.generationInput(catalog: catalog, packages: packages, textReplacement: textReplacement),
            options: ApplyOptions(overwriteExternalChanges: true))
        guard case .applied = outcome else { return outcome }

        try SettingsStore(paths: paths).save(proposal.settings)
        if fm.fileExists(atPath: paths.personal.path) { try fm.removeItem(at: paths.personal) }
        try fm.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        for url in staged.personalDicts {
            try fm.copyItem(at: url, to: paths.personalDicts.appending(path: url.lastPathComponent))
        }
        if !proposal.manualPhrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(proposal.manualPhrases)).utf8)
                .write(to: paths.personalPhrases, options: .atomic)
        }
        return outcome
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter TakeoverApplierTests 2>&1 | grep -E "error:|warning:|passed|failed" | tail -5`
Expected: 5 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Takeover/TakeoverApplier.swift Tests/RimeKitTests/TakeoverApplierTests.swift
git commit -m "feat: 确认接管：走应用流程写入，成功后才保存设置和个人内容

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `rimectl takeover`；应用时同步文本替换

**Files:**
- Modify: `Sources/rimectl/Rimectl.swift`
- Test: `Tests/RimeKitTests/RimectlTakeoverTests.swift`

**Interfaces:**
- Consumes: `TakeoverSurvey`、`TakeoverAnalyzer`、`TakeoverPreview`、`TakeoverApplier`（任务 4–7）、`TextReplacementReader`（任务 3）
- Produces:
  - `Rimectl.Context.textReplacements: @Sendable () throws -> [Phrase]`（默认读系统数据库；测试换成假的）
  - `rimectl takeover [--confirm] [--force] [--cache-only]`：
    - 已经由应用管理 → 退出码 1
    - 已有设置没加 `--force` → 退出码 1，提示 `--force`
    - Rime 目录是空的 → 退出码 0，提示先选起步方案
    - 认不出方案 → 退出码 1
    - 预览 → 退出码 0，最后一行说「这只是预览」
    - `--confirm` → 打印预览后接管，输出和 `apply` 一样
  - `prepareInput`：设置里打开了文本替换同步时读文本替换（`apply`、`generate` 都用）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/RimectlTakeoverTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit
@testable import rimectl

@Suite struct RimectlTakeoverTests {
    typealias F = TakeoverFixtures

    struct Env {
        let dir: TempDir
        let paths: AppPaths
        let locations: RimeLocations
        let output: Output
        let context: Rimectl.Context

        func run(_ args: [String]) async -> Int32 {
            await Rimectl.run(args + ["--rime-dir", locations.rimeDirectory.path], context)
        }
    }

    func env(sample: Bool = true) throws -> Env {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let packages = try GenFixtures.makePackages(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        if sample { try F.wubiSample(packages, into: locations.rimeDirectory) }
        let output = Output(echo: false)
        let catalog = try GenFixtures.catalog()
        var context = Rimectl.Context(
            http: FakeHTTPClient(), retry: .immediate, catalog: { catalog }, defaultPaths: paths, output: output,
            locations: locations, compiler: FakeCompiler(), squirrel: FakeSquirrel(locations: locations, running: true),
            deployTimeout: .milliseconds(20), sleep: { _ in })
        context.textReplacements = { [F.fromTR] }
        return Env(dir: dir, paths: paths, locations: locations, output: output, context: context)
    }

    @Test func 预览不改任何东西() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        let text = e.output.text
        #expect(text.contains("五笔拼音（wb_py）"))
        #expect(text.contains("个人词库：2 个"))
        #expect(text.contains("手动短语：1 条"))
        #expect(text.contains("和 macOS 文本替换一样的短语：1 条"))
        #expect(text.contains("原样保留：notes.txt、weasel.custom.yaml"))
        #expect(text.contains("这只是预览"))
        #expect(!FileManager.default.fileExists(atPath: e.paths.settingsFile.path))
        #expect(try Ledger.load(e.paths).entries.isEmpty)
    }

    @Test func 输出里没有个人内容() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        for secret in ["私人短语", "替换短语", "私人词条", "私人五笔词"] {
            #expect(!e.output.text.contains(secret), "输出里有「\(secret)」")
        }
    }

    @Test func 确认接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        #expect(await e.run(["takeover", "--confirm", "--cache-only"]) == 0)
        #expect(e.output.text.contains("永久保留"))
        #expect(e.output.text.contains("部署完成"))
        #expect(try SettingsStore(paths: e.paths).load()?.schemas == ["wb_py", "wb"])
    }

    @Test func 已经有设置时要加force() async throws {
        let e = try env(); defer { e.dir.remove() }
        try SettingsStore(paths: e.paths).save(Settings(schemas: ["wb"]))
        #expect(await e.run(["takeover", "--cache-only"]) == 1)
        #expect(e.output.text.contains("--force"))
        #expect(await e.run(["takeover", "--cache-only", "--force"]) == 0)
    }

    @Test func 已经由应用管理时不接管() async throws {
        let e = try env(); defer { e.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(e.paths)
        #expect(await e.run(["takeover", "--cache-only"]) == 1)
        #expect(e.output.text.contains("不用再接管"))
    }

    @Test func 空目录不用接管() async throws {
        let e = try env(sample: false); defer { e.dir.remove() }
        try F.put("var: {}\n", "user.yaml", in: e.locations.rimeDirectory)
        #expect(await e.run(["takeover", "--cache-only"]) == 0)
        #expect(e.output.text.contains("不用接管"))
    }

    @Test func 认不出方案() async throws {
        let e = try env(sample: false); defer { e.dir.remove() }
        try F.put("随手记\n", "notes.txt", in: e.locations.rimeDirectory)
        #expect(await e.run(["takeover", "--cache-only"]) == 1)
        #expect(e.output.text.contains("认不出来"))
    }

    @Test func 打开了文本替换同步时应用会带上文本替换() async throws {
        let e = try env(sample: false); defer { e.dir.remove() }
        var settings = Settings(schemas: ["wb"])
        settings.textReplacement.sync = true
        try SettingsStore(paths: e.paths).save(settings)
        #expect(await e.run(["apply", "--cache-only"]) == 0)
        let phrases = try String(contentsOf: e.locations.rimeDirectory.appending(path: "custom_phrase.txt"), encoding: .utf8)
        #expect(phrases.contains(F.fromTR.line))
    }
}
```

> 注：`GenFixtures` 里方案 `wb_py` 的名字是「五笔拼音」。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter RimectlTakeoverTests 2>&1 | grep -E "error:|passed|failed" | head -5`
Expected: 编译失败，`value of type 'Rimectl.Context' has no member 'textReplacements'`

- [ ] **Step 3: 实现**

`Sources/rimectl/Rimectl.swift`：

1. `Context` 里 `var activationTimeout: Double = 600` 后面加：

```swift
        /// 读 macOS 文本替换；测试时换成假的
        var textReplacements: @Sendable () throws -> [Phrase] = { try TextReplacementReader().read() }
```

2. `usage` 里 `rimectl apply …` 那一行后面加：

```
      rimectl takeover [--confirm] [--force] [--cache-only]    认出已有的 Rime 配置并预览；加 --confirm 才真的接管（先完整备份）
```

3. `run` 里参数变量加 `var confirm = false`，`switch args[i]` 里加：

```swift
            case "--confirm":
                confirm = true
                i += 1
```

4. `switch command` 里 `case "apply":` 后面加：

```swift
            case "takeover":
                return try await takeover(confirm: confirm, force: force, cacheOnly: cacheOnly,
                                          paths: paths, locations: locations, context)
```

5. `prepareInput` 最后的 `return` 改成：

```swift
        let textReplacement = settings.textReplacement.sync ? try context.textReplacements() : []
        return GenerationInput(settings: settings, catalog: catalog, packages: packages,
                               personal: try PersonalContent.load(from: paths), textReplacementPhrases: textReplacement)
```

6. `apply` 里 `switch try await deployer(…).apply(input, options: options) { … }` 整段换成 `return printApplyOutcome(try await deployer(paths: paths, locations: locations, context).apply(input, options: options), out)`，原来的 `switch` 挪进新函数（只改了「已备份」那一行，加上永久保留的说明）：

```swift
    private static func printApplyOutcome(_ outcome: ApplyOutcome, _ out: Output) -> Int32 {
        switch outcome {
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
            out.line("已备份：\(report.backup.id)（\(report.backup.reason)\(report.backup.permanent ? "，这份永久保留" : "")）")
            out.line("写入 \(report.written.count) 个文件，没变 \(report.unchanged) 个，删掉 \(report.removed.count) 个")
            for warning in report.warnings { out.line("注意：\(warning)") }
            out.line(report.launched ? "已启动鼠须管" : "已通知鼠须管重新部署")
            return reportDeploy(report.deploy, backupID: report.backup.id, out)
        }
    }
```

7. 新增（放在 `printApplyOutcome` 后面）：

```swift
    private static func takeover(confirm: Bool, force: Bool, cacheOnly: Bool, paths: AppPaths, locations: RimeLocations,
                                 _ context: Context) async throws -> Int32 {
        let out = context.output
        guard try Ledger.load(paths).entries.isEmpty else {
            out.error(TakeoverError.alreadyManaged.description)
            return 1
        }
        if FileManager.default.fileExists(atPath: paths.settingsFile.path), !force {
            out.error(TakeoverError.settingsExist(paths.settingsFile.path).description)
            return 1
        }
        let catalog = try context.catalog()
        let rime = locations.rimeDirectory
        let survey = try TakeoverSurvey.scan(rime, catalog: catalog)
        if survey.isEmpty {
            out.line("Rime 目录里没有配置，不用接管。先选一个起步方案：rimectl settings init rime-ice|flypy|wubi-pinyin，再 rimectl apply")
            return 0
        }
        guard !survey.schemas.isEmpty else {
            out.error(TakeoverError.nothingRecognized.description)
            return 1
        }
        let store = PackageStore(paths: paths, http: context.http, retry: context.retry)
        var packages: [String: CachedPackage] = [:]
        for spec in try catalog.installOrder(for: survey.packages) {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        var textReplacement: [Phrase] = []
        do {
            textReplacement = try context.textReplacements()
        } catch {
            out.line("注意：\(error)。短语都按手动短语处理")
        }
        let proposal = try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: packages,
                                                    textReplacement: textReplacement)
        for spec in try proposal.settings.requiredPackages(catalog) where packages[spec.id] == nil {
            guard let pkg = try await obtain(spec, cacheOnly: cacheOnly, store: store, out) else { return 1 }
            packages[spec.id] = pkg
        }
        let preview = try TakeoverPreview.make(proposal, rime: rime, catalog: catalog, packages: packages,
                                               textReplacement: textReplacement, staging: paths.staging)
        printTakeover(proposal, preview, catalog: catalog, rime: rime, out)
        guard confirm else {
            out.line("这只是预览，什么都没改。确认接管：rimectl takeover --confirm（会先完整备份 Rime 目录，这份备份永久保留）")
            return 0
        }
        let outcome = try await TakeoverApplier(deployer: deployer(paths: paths, locations: locations, context))
            .confirm(proposal, catalog: catalog, packages: packages, textReplacement: textReplacement, force: force)
        return printApplyOutcome(outcome, out)
    }

    /// 只打印设置、文件名和条数，不打印词库和短语的内容
    private static func printTakeover(_ proposal: TakeoverProposal, _ preview: TakeoverPreview, catalog: Catalog,
                                      rime: URL, _ out: Output) {
        let s = proposal.settings
        func schemaName(_ id: String) -> String {
            let name = catalog.packageOwning(schema: id)?.schemas.first { $0.id == id }?.name ?? id
            return "\(name)（\(id)）"
        }
        out.line("Rime 目录：\(rime.path)")
        out.line("方案（第一个是默认方案）：" + s.schemas.map(schemaName).joined(separator: "、"))
        for packageID in s.options.keys.sorted() {
            guard let spec = catalog.package(packageID) else { continue }
            for option in spec.options {
                out.line("选项：\(spec.name) · \(option.name)：\(s.choice(option, of: spec).name)")
            }
        }
        let a = s.appearance
        var look: [String] = []
        if let v = a.fontPoint { look.append("候选字字号 \(v)") }
        if let v = a.labelFontPoint { look.append("序号字号 \(v)") }
        if let v = a.commentFontPoint { look.append("注释字号 \(v)") }
        if let v = a.colorScheme { look.append("浅色配色 \(v)") }
        if let v = a.colorSchemeDark { look.append("深色配色 \(v)") }
        if let v = a.candidateListLayout { look.append(v == .linear ? "候选横排" : "候选竖排") }
        if let v = a.textOrientation { look.append(v == .horizontal ? "文字横排" : "文字竖排") }
        if let v = a.pageSize { look.append("每页 \(v) 个候选") }
        out.line("外观：" + (look.isEmpty ? "都是方案默认的" : look.joined(separator: "，")))
        for (name, items) in s.preservedPatches.sorted(by: { $0.key < $1.key }) {
            out.line("保留的补丁：\(name).custom.yaml 里的 " + items.map(\.key).joined(separator: "、"))
        }
        let dicts = proposal.personalDicts.map(\.lastPathComponent)
        out.line("个人词库：\(dicts.count) 个" + (dicts.isEmpty ? "" : "（\(dicts.joined(separator: "、"))）"))
        out.line("手动短语：\(proposal.manualPhrases.count) 条")
        if proposal.textReplacementMatches > 0 {
            out.line("和 macOS 文本替换一样的短语：\(proposal.textReplacementMatches) 条（接管后打开文本替换同步，由它生成）")
        }
        for note in proposal.notes + preview.warnings { out.line("注意：\(note)") }
        out.line("接管后：换掉 \(preview.replaced.count) 个文件，内容不变 \(preview.unchanged.count) 个，新加 \(preview.added.count) 个，原样保留 \(preview.kept.count) 个")
        if !preview.replaced.isEmpty { out.line("  换掉：" + preview.replaced.joined(separator: "、")) }
        if !preview.added.isEmpty { out.line("  新加：" + preview.added.joined(separator: "、")) }
        if !preview.kept.isEmpty { out.line("  原样保留：" + preview.kept.joined(separator: "、")) }
    }
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "Rimectl" 2>&1 | grep -E "error:|warning:|Test run" | tail -3`
Expected: 全部通过（包括原来的 `RimectlApplyTests`）

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/rimectl/Rimectl.swift Tests/RimeKitTests/RimectlTakeoverTests.swift
git commit -m "feat: rimectl takeover（预览 / --confirm 接管）；应用时同步文本替换

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 联网测试：用真实上游造脱敏样本，接管、编译、打字

**Files:**
- Create: `Tests/RimeKitTests/Support/WubiSample.swift`
- Create: `Tests/RimeKitTests/OnlineTakeoverTests.swift`

**Interfaces:**
- Consumes: 任务 4–6 的全部；`RimeTools.build`、`RimeTools.type`（已有，需要先 `./tools/vm/build-probes.sh`）
- Produces: `WubiSample.build(wubi:dicts:into:)`；环境变量 `RIMEKIT_SAMPLE_OUT=<目录>` 时把造好的样本复制一份到那里（任务 10 在测试机里用）

样本照 [reference-wubi-profile.md](../../reference-wubi-profile.md) 的改法造：上游文件原样；`default.custom.yaml` 拼音混输排第一、打开 `-` `=` 翻页；`squirrel.custom.yaml` 浅色深色字号都改成 24/20/20；`pinyin_ext` 总词库；5 个补丁（换词库 + 注入短语）；个人词库和短语是编的；另有 `weasel.custom.yaml` 和 `default.custom.yaml.bak` 两个应用不认识的文件。

- [ ] **Step 1: 写样本**

`Tests/RimeKitTests/Support/WubiSample.swift`：

```swift
import Foundation
@testable import RimeKit

/// 按作者的五笔配置（docs/reference-wubi-profile.md）造一个脱敏的样本 Rime 目录：
/// 上游文件 + 同样的改法；个人词库和短语都是编的
enum WubiSample {
    static let manualPhrase = Phrase(text: "手动短语样本", code: "sdzd", weight: 1)
    /// 和测试机里加过的文本替换一样（tstx → 测试短语）
    static let textReplacement = Phrase(text: "测试短语", code: "tstx", weight: 1)
    static let pinyinWord = (text: "鼠须管样本词", code: "shu xu guan yang ben ci")
    static let wubiWord = (text: "五笔样本词", code: "tgtg")

    struct UpstreamChanged: Error, CustomStringConvertible {
        let description: String
    }

    /// 替换并检查次数：上游文件变了就报错，不会悄悄造出一个没改过的样本
    static func replace(_ text: String, _ old: String, _ new: String, count: Int) throws -> String {
        let found = text.components(separatedBy: old).count - 1
        guard found == count else {
            throw UpstreamChanged(description: "上游文件变了，造样本时「\(old)」找到 \(found) 处，应该是 \(count) 处")
        }
        return text.replacingOccurrences(of: old, with: new)
    }

    static func build(wubi: CachedPackage, dicts: CachedPackage, into rime: URL) throws {
        func put(_ text: String, _ path: String) throws {
            let url = rime.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func upstream(_ package: CachedPackage, _ path: String) throws -> String {
            try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8)
        }
        for package in [wubi, dicts] {
            for path in package.info.files where !GenerationContext.isUpstreamPatch(path) && path != "LICENSE" {
                try put(try upstream(package, path), path)
            }
        }

        var defaults = try upstream(wubi, "default.custom.yaml")
        defaults = try replace(defaults,
            "    - schema: wubi86_jidian             # 五笔\n    - schema: numbers                   # 大写数字\n    - schema: wubi86_jidian_pinyin      # 五笔拼音混输\n",
            "    - schema: wubi86_jidian_pinyin      # 五笔拼音混输\n    - schema: wubi86_jidian             # 五笔\n    - schema: numbers                   # 大写数字\n",
            count: 1)
        defaults = try replace(defaults, "#      - { when: has_menu, accept: minus, send: Page_Up }",
                               "      - { when: has_menu, accept: minus, send: Page_Up }", count: 1)
        defaults = try replace(defaults, "#      - { when: has_menu, accept: equal, send: Page_Down }",
                               "      - { when: has_menu, accept: equal, send: Page_Down }", count: 1)
        try put(defaults, "default.custom.yaml")
        try put(defaults, "default.custom.yaml.bak")   // 作者目录里有这样的备份文件：应该原样保留

        var squirrel = try upstream(wubi, "squirrel.custom.yaml")
        squirrel = try replace(squirrel, "      font_point: 18", "      font_point: 24", count: 2)
        squirrel = try replace(squirrel, "      label_font_point: 17", "      label_font_point: 20", count: 2)
        squirrel = try replace(squirrel, "      comment_font_point: 16", "      comment_font_point: 20", count: 2)
        try put(squirrel, "squirrel.custom.yaml")

        try put("""
            ---
            name: pinyin_ext
            version: "2026-10-14"
            sort: by_weight
            import_tables:
              - pinyin_user
              - cn_dicts/8105
              - cn_dicts/base
              - cn_dicts/ext
            ...

            """, "pinyin_ext.dict.yaml")
        try put("---\nname: pinyin_user\nversion: \"1\"\nsort: by_weight\n...\n\(pinyinWord.text)\t\(pinyinWord.code)\t100\n",
                "pinyin_user.dict.yaml")
        var user = try upstream(wubi, "wubi86_jidian_user.dict.yaml")
        if !user.hasSuffix("\n") { user += "\n" }
        try put(user + "\(wubiWord.text)\t\(wubiWord.code)\n", "wubi86_jidian_user.dict.yaml")

        let phrase = """
              "engine/translators/@before 0": table_translator@custom_phrase
              custom_phrase:
                dictionary: ""
                user_dict: custom_phrase
                db_class: stabledb
                enable_completion: false
                enable_sentence: false
                initial_quality: 100

            """
        try put("patch:\n  translator/dictionary: pinyin_ext\n" + phrase, "pinyin_simp.custom.yaml")
        for schema in ["wubi86_jidian", "wubi86_jidian_pinyin", "wubi86_jidian_trad", "wubi86_jidian_trad_pinyin"] {
            try put("patch:\n  reverse_lookup/dictionary: pinyin_ext\n" + phrase, "\(schema).custom.yaml")
        }
        try put(PhraseFile.header + PhraseFile.render([textReplacement, manualPhrase]), "custom_phrase.txt")
        try put("patch:\n  style/font_point: 20\n", "weasel.custom.yaml")   // 小狼毫用的，应该原样保留
    }
}
```

- [ ] **Step 2: 写联网测试**

`Tests/RimeKitTests/OnlineTakeoverTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

/// 用真实上游包造样本、接管、生成、编译、打字。要联网，要宿主机装了鼠须管，要先 ./tools/vm/build-probes.sh：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineTakeoverTests
/// 加 RIMEKIT_SAMPLE_OUT=<目录> 会把五笔样本复制一份到那个目录（测试机里用）
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1" && RimeTools.installed))
struct OnlineTakeoverTests {
    @Test func 五笔样本() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let catalog = try Catalog.builtIn()
        let store = PackageStore(paths: Fixtures.paths(dir))
        let wubi = try await store.fetch(try #require(catalog.package("wubi86-jidian")))
        let dicts = try await store.fetch(try #require(catalog.package("rime-ice-dicts")))
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try WubiSample.build(wubi: wubi, dicts: dicts, into: rime)
        if let keep = ProcessInfo.processInfo.environment["RIMEKIT_SAMPLE_OUT"] {
            let target = URL(fileURLWithPath: keep, isDirectory: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: rime, to: target)
        }
        let tr = [WubiSample.textReplacement]

        let survey = try TakeoverSurvey.scan(rime, catalog: catalog)
        let p = try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: ["wubi86-jidian": wubi], textReplacement: tr)
        let starter = Settings.starter(.wubiPinyin)
        #expect(p.settings.schemas == starter.schemas)
        #expect(p.settings.options == starter.options)
        #expect(p.settings.appearance == Appearance(fontPoint: 24, labelFontPoint: 20, commentFontPoint: 20))
        #expect(p.settings.textReplacement == TextReplacementSettings(sync: true))
        #expect(p.settings.preservedPatches.mapValues { $0.map(\.key) } == ["default": ["key_binder/bindings"]])
        #expect(p.personalDicts.map(\.lastPathComponent) == ["pinyin_user.dict.yaml", "wubi86_jidian_user.dict.yaml"])
        #expect(p.manualPhrases == [WubiSample.manualPhrase])
        #expect(p.textReplacementMatches == 1)
        #expect(p.notes.isEmpty, "\(p.notes)")

        let packages = ["wubi86-jidian": wubi, "rime-ice-dicts": dicts]
        let preview = try TakeoverPreview.make(p, rime: rime, catalog: catalog, packages: packages, textReplacement: tr,
                                               staging: dir.url.appending(path: "staging", directoryHint: .isDirectory))
        #expect(preview.kept == ["default.custom.yaml.bak", "weasel.custom.yaml"])
        #expect(preview.added == [])

        let out = dir.url.appending(path: "out", directoryHint: .isDirectory)
        _ = try ConfigGenerator().generate(p.generationInput(catalog: catalog, packages: packages, textReplacement: tr), into: out)
        #expect(try RimeTools.build(out).status == 0)
        let r = try RimeTools.type(out, schema: "wubi86_jidian_pinyin",
                                   ["g", "weixin", "qukuailian", "tstx", "sdzd", "shuxuguanyangbenci", WubiSample.wubiWord.code])
        #expect(r["g"]?.first == "一")
        #expect(r["weixin"]?.first == "微信")
        #expect(r["qukuailian"]?.first == "区块链")
        #expect(r["tstx"]?.first == "测试短语")
        #expect(r["sdzd"]?.first == "手动短语样本")
        #expect(r["shuxuguanyangbenci"]?.contains(WubiSample.pinyinWord.text) == true, "\(r["shuxuguanyangbenci"] ?? [])")
        #expect(r[WubiSample.wubiWord.code]?.contains(WubiSample.wubiWord.text) == true, "\(r[WubiSample.wubiWord.code] ?? [])")
        let bindings = try #require(try GenFixtures.patch(out, "default")["key_binder/bindings"])
        #expect(YAMLNode.canonical(bindings).contains("minus"))
        #expect(YAMLNode.canonical(bindings).contains("equal"))
        let squirrel = try GenFixtures.patch(out, "squirrel")
        #expect(squirrel["preset_color_schemes/roseo_maple_dark/font_point"]?.string == "24")
    }

    @Test func 雾凇生成的配置接管后什么都不变() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let catalog = try Catalog.builtIn()
        var settings = Settings(schemas: ["rime_ice", "double_pinyin_flypy"])
        settings.appearance.fontPoint = 22
        settings.appearance.pageSize = 7
        let store = PackageStore(paths: Fixtures.paths(dir))
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) { packages[spec.id] = try await store.fetch(spec) }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        _ = try ConfigGenerator().generate(
            GenerationInput(settings: settings, catalog: catalog, packages: packages,
                            personal: PersonalContent(dicts: [], phrases: [WubiSample.manualPhrase]), textReplacementPhrases: []),
            into: rime)

        let survey = try TakeoverSurvey.scan(rime, catalog: catalog)
        let p = try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: packages, textReplacement: [])
        #expect(p.settings.schemas == settings.schemas)
        #expect(p.settings.appearance == settings.appearance)
        #expect(p.settings.preservedPatches.isEmpty, "\(p.settings.preservedPatches)")
        #expect(p.manualPhrases == [WubiSample.manualPhrase])
        #expect(p.notes.isEmpty, "\(p.notes)")
        let preview = try TakeoverPreview.make(p, rime: rime, catalog: catalog, packages: packages, textReplacement: [],
                                               staging: dir.url.appending(path: "staging", directoryHint: .isDirectory))
        #expect(preview.replaced == [], "\(preview.replaced)")
        #expect(preview.added == [])
        #expect(preview.kept == [])
    }
}
```

- [ ] **Step 3: 运行**

Run:
```bash
./tools/vm/build-probes.sh >/dev/null && RIMEKIT_ONLINE=1 swift test --filter OnlineTakeoverTests 2>&1 | grep -E "error:|Expectation failed|passed|failed" | head -20
```
Expected: 2 个测试通过。

如果失败：
- `上游文件变了`：上游改了文件，按实际内容更新 `WubiSample` 里的替换原文，在 ledger 里记一条 Ruling。
- `notes` 不为空或 `preservedPatches` 多出别的键：说明真实上游里有识别规则没覆盖的写法。先看是哪一项、为什么，修识别逻辑并补一个用自造包的单元测试（任务 5 的测试文件）；确实是合理的提示，就改断言并记 Ruling。
- 打字结果不对：先用 `RimeTools.type` 看候选，确认是生成问题还是测试期望写错了。

- [ ] **Step 4: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Tests/RimeKitTests/Support/WubiSample.swift Tests/RimeKitTests/OnlineTakeoverTests.swift
git commit -m "test: 联网测试：真实上游的五笔样本接管后编译打字正常；雾凇配置接管后不变

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 测试机里实测；（经同意）只读检查宿主机的真实配置

**Files:**
- Create: `docs/phase5-vm-log.md`

**Interfaces:**
- Consumes: `rimectl takeover`（任务 8）、`RIMEKIT_SAMPLE_OUT`（任务 9）
- Produces: 实测记录；发现的问题按 TDD 修（先写自造包的失败测试）

先编译：`swift build 2>&1 | tail -1`。下面 `vmrun` 是在 `squirrel-dev` 的桌面会话里跑 rimectl：

```bash
vmrun() { ./tools/vm/vm.sh ssh squirrel-dev "sudo launchctl asuser \$(id -u) sudo -u tester '/Volumes/My Shared Files/project/.build/debug/rimectl' $*"; }
```

（测试机的远程 shell 是 zsh：参数用 `$*` 拼进字符串，不要依赖变量分词。）

- [ ] **Step 1: 接管一份应用自己生成的雾凇配置（`squirrel-dev` 现在的状态，由 `/tmp/rk` 管理）**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rk5 && mkdir -p /tmp/rk5 && cp -R /tmp/rk/packages /tmp/rk5/packages && cat /tmp/rk/settings.json'
vmrun takeover --cache-only --data-dir /tmp/rk5
```

Expected：方案、外观和 `/tmp/rk/settings.json` 一致；「换掉 0 个文件」。

例外：如果 `/tmp/rk` 的手动短语里有和测试机文本替换一样的条目（`tstx → 测试短语`），接管会把它算成文本替换并打开同步，`custom_phrase*.txt` 会多出系统自带的那一条，这时换掉的只能是短语文件。记录实际情况。

```bash
vmrun takeover --confirm --cache-only --data-dir /tmp/rk5
vmrun apply --cache-only --data-dir /tmp/rk5
```

Expected：确认后「部署完成」；再 `apply` 输出「写入 0 个文件」。然后 `./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rk5'`（`/tmp/rk` 的记录和文件仍然一致：`vmrun status --data-dir /tmp/rk` 没有外部改动）。

- [ ] **Step 2: 造五笔样本放进测试机的 Rime 目录**

```bash
RIMEKIT_ONLINE=1 RIMEKIT_SAMPLE_OUT="$PWD/.build/wubi-sample" swift test --filter OnlineTakeoverTests 2>&1 | grep -E "Test run"
./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rime-before-phase5 && cp -Rp ~/Library/Rime /tmp/rime-before-phase5 && find ~/Library/Rime -mindepth 1 -maxdepth 1 ! -name user.yaml ! -name installation.yaml ! -name "*.userdb" -exec rm -rf {} + && cp -R "/Volumes/My Shared Files/project/.build/wubi-sample/." ~/Library/Rime/ && ls ~/Library/Rime | wc -l'
```

- [ ] **Step 3: 预览、确认接管**

```bash
vmrun takeover --data-dir /tmp/rk6
```

Expected：方案是五笔拼音混输排第一的 6 个方案；选项「拼音词库：雾凇大词库」；外观「候选字字号 24，序号字号 20，注释字号 20」；保留的补丁 `default.custom.yaml 里的 key_binder/bindings`；个人词库 2 个；手动短语 1 条；和文本替换一样的 1 条；原样保留 `default.custom.yaml.bak`、`weasel.custom.yaml`；没有「注意」。

```bash
vmrun takeover --confirm --data-dir /tmp/rk6
```

Expected：「已备份：…（第一次应用前，这份永久保留）」「部署完成」。

- [ ] **Step 4: 用户打字检查**

用 AskUserQuestion 请用户在 `squirrel-dev` 里切到「五笔拼音混输」打字，选项写清楚要看的结果：
- `g` → 一；`weixin` → 微信；`qukuailian` → 区块链
- `tstx` → 测试短语（文本替换）；`sdzd` → 手动短语样本
- `shuxuguanyangbenci` 候选里有「鼠须管样本词」；`tgtg` 候选里有「五笔样本词」
- 候选字明显变大（24 号）；按 `-` `=` 能翻页

然后：

```bash
vmrun apply --data-dir /tmp/rk6
```

Expected：「写入 0 个文件」（文本替换同步读的是测试机真实的文本替换，和接管时一样）。

- [ ] **Step 5: 还原测试机**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'find ~/Library/Rime -mindepth 1 -maxdepth 1 ! -name "*.userdb" -exec rm -rf {} + && cp -Rp /tmp/rime-before-phase5/. ~/Library/Rime/ && sudo launchctl asuser $(id -u) sudo -u tester "/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --reload; rm -rf /tmp/rk6'
vmrun status --data-dir /tmp/rk
```

Expected：`status` 没有外部改动。等几秒后 `./tools/vm/vm.sh ssh squirrel-dev 'rm -rf /tmp/rime-before-phase5'`。

- [ ] **Step 6: 宿主机真实配置（先问用户）**

用 AskUserQuestion 问用户（至少两个选项）：
- 「可以，在宿主机上跑」：复制一份 `~/Library/Rime` 到临时目录，只做预览；
- 「我自己跑」：把下面的命令给用户；
- 「跳过」。

同意后运行（只预览，不加 `--confirm`；`--rime-dir` 指向副本，不会通知鼠须管；会只读读取文本替换数据库，只输出条数）：

```bash
S=$(mktemp -d) && cp -Rp ~/Library/Rime "$S/Rime" && rm -rf "$S/Rime/build" && .build/debug/rimectl takeover --rime-dir "$S/Rime" --data-dir "$S/data"; rm -rf "$S"
```

Expected：和 [reference-wubi-profile.md](../../reference-wubi-profile.md) 一致——6 个方案、拼音混输第一；雾凇大词库；字号 24/20/20；保留 `key_binder/bindings`；个人词库 2 个；短语条数和文本替换对得上（宿主机文本替换 11 条，短语文件里能对上的那些算文本替换）；原样保留 `weasel.custom.yaml` 和两个 `.bak`。和预期不一样的地方记下来，属于识别问题的按 TDD 修。

- [ ] **Step 7: 写记录，提交**

`docs/phase5-vm-log.md`：按步骤写实际命令的关键输出（不写任何短语、词库内容，宿主机部分只写设置、文件名和条数）、用户打字检查结果、发现的问题和怎么修的。

```bash
git add docs/phase5-vm-log.md
git commit -m "docs: 阶段 5 测试机实测记录（接管雾凇和五笔样本）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: 更新文档

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（加 5.2 接管识别规则；6.2 指向它）
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`（阶段 5 已完成；阶段 7 说明读取已提前）
- Modify: `CLAUDE.md`、`README.md`（阶段状态、`rimectl takeover`）
- Modify: `docs/verified-facts.md`（只在任务 10 发现了新事实时）

- [ ] **Step 1: 设计文档**

在 `### 5.1 生成规则` 那一节最后（`8. 只有内容不为空的补丁才生成 .custom.yaml 文件。` 后面）加：

```markdown

### 5.2 接管识别规则

阶段 5 定下，用自造包、真实上游的脱敏样本和测试机验证。

1. **有没有配置**：Rime 目录里有配置文件（不算 `build/`、`user.yaml` 这些 Rime 自己的运行文件）。
2. **方案**：`default.custom.yaml` 补丁里的 `schema_list`，没有就看 `default.yaml`。清单里没有的方案不启用，文件原样保留，告诉用户。
3. **对照的默认补丁** = 包里自带的 `<名字>.custom.yaml` + 认出的选项的补丁。只看 `default`、`squirrel`、这些包的方案和自带补丁对应的 `.custom.yaml`，别的（如 `weasel.custom.yaml`）原样保留。
4. **选项**：某个选择的补丁全都在、要生成的总词库也在，就算选了它；都对得上时选条件最多的。只对上一部分时提示。
5. **用户补丁逐项比**：拆成叶子（`menu: {page_size: 5}` → `menu/page_size`）和默认补丁比。应用管理的键变成设置；和默认一样的丢掉；不一样的存成「保留的补丁」；和默认补丁、应用管理的键都没关系的项整项原样保留。默认补丁有、用户补丁没有的项，提示「接管后会按上游默认加上」。键里有 `/` 的映射（标点映射）整个当一项。
6. **外观**：看实际生效的值（配色里的优先于全局 `style`），和不接管时的默认值比，不一样才写进设置。浅色深色不一样时用浅色的并提示。
7. **个人词库**：清单里标出的个人词库模板和上游不一样的；所选选项总词库里「只在有个人词库时」导入的词库。
8. **短语**：启用的方案用到的短语文件，去掉上游自带的；和 macOS 文本替换一样的算文本替换（打开同步），其余算手动短语。
9. **预览和确认**：在暂存区按识别结果生成一遍，逐个文件比，列出会换掉、不变、新加、原样保留的文件。用户确认后走 6.1（覆盖前完整备份，这份永久保留）；写入成功后才保存设置和个人内容。已经由应用管理的目录不再接管。
```

6.2 第 2 步「已有配置」那一条末尾加：`识别规则见 5.2；命令行是 rimectl takeover（预览）、rimectl takeover --confirm。`

- [ ] **Step 2: 路线图、CLAUDE.md、README**

- 路线图阶段 5 那一行的成果改成：`rimectl takeover`：认出已有配置（方案、选项、外观、保留的补丁、个人词库、短语），预览会变的文件，确认后接管；文本替换的读取提前到这一阶段（已完成，2026-10-15）。阶段 7 那一行成果改成：有变化时提示、同步（读取已在阶段 5 做好）。
- `CLAUDE.md` 第一段的阶段状态改成「阶段 0–5 已完成（…；接管已有配置），下一步写阶段 6 的计划」；测试机一节加一句：`rimectl takeover` 也要用桌面会话（`--confirm` 会通知鼠须管）。
- `README.md` 里「宿主机上试 `rimectl apply` …」那一行后面加：`- 接管已有配置：rimectl takeover --rime-dir 临时目录 --data-dir D 只预览、不改文件；加 --confirm 才真的接管（会通知鼠须管，只在测试机里做）`（命令部分用反引号）。

- [ ] **Step 3: 检查，提交**

```bash
grep -n "5.2 接管识别规则" docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md
grep -n "已完成" docs/superpowers/plans/2026-10-15-roadmap.md | grep "| 5 |"
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 5 完成：接管识别规则写进设计，更新路线图和说明

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

# 阶段 8b：主窗口 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 设置好以后进入主窗口。左边栏 6 页：方案、外观、文本替换、导入导出、备份、诊断。改方案、外观、文本替换开关这类设置时，先改在草稿里，底部出现「有改动还没应用 [撤销] [应用改动]」；点「应用改动」才走 6.1 写进鼠须管。导出、导入、还原、检查是马上执行的操作。出错时说清楚，能给出下一步（设计第 7 节）。

**Architecture:**
- `AppCore` 新增 `MainModel`（`@MainActor @Observable`）：
  - 管 `saved`（已经生效的设置）和 `draft`（正在改的设置）；
  - 执行应用、导出、导入、还原、文本替换检查、诊断；
  - 结果和错误用 `Notice` 交给界面，外部改动用 `pendingExternalChanges` 交给界面弹窗。
- `AppCore` 新增 `AppState`：决定显示引导还是主窗口。
- `AppUI` 加主窗口和 6 个页面，视图里不写逻辑。
- RimeKit 只加 `ColorSchemes`：从包里读出能选的配色。
- `AppEnvironment` 的取包拆成「下载」和「本地缓存」两个函数：主窗口里下载失败时问用户要不要先用旧版本；引导里照旧自动用旧版本，但会在完成页提醒（8a 的待改进项）。

**Tech Stack:** Swift 6.4、SwiftUI（`NavigationSplitView`、`Form`、`fileImporter`、`NSSavePanel`）、Observation、Swift Testing。

**Spec:** [docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md](../specs/2026-10-15-squirrel-macos-v1-design.md)（第 1 节第一版范围、第 5 节 `settings.json`、5.1、6.1、6.3、6.4、6.5、第 7 节、8.3）；路线图 [2026-10-15-roadmap.md](2026-10-15-roadmap.md)；8a 计划 [2026-10-15-phase8a-app-setup.md](2026-10-15-phase8a-app-setup.md)

## 已经和你确认的

- 改设置后点「应用改动」才写进鼠须管，改动可以在应用前撤销。

## 本阶段要定的事（计划里的做法，请确认）

| # | 问题 | 计划里的做法 | 理由 |
|---|---|---|---|
| 1 | 主窗口结构 | 一个窗口，左边栏 6 页：方案、外观、文本替换、导入导出、备份、诊断。第一次打开先走引导，完成页点「开始使用」进主窗口；已经设置好的直接进主窗口 | 设计第 1 节第一版范围 |
| 2 | 哪些算「改设置」（要点「应用改动」） | 方案的启用、顺序、包选项；外观；文本替换同步的开关。导出、导入、还原、文本替换的「检查」、诊断马上执行 | 前者会改写配置，可以攒着一起应用；后者本身就是一次性的动作 |
| 3 | 还没应用的改动 | 只在内存里，退出应用就没了，不提示 | 第一版先简单；草稿不落盘 |
| 4 | 应用时遇到外部改动 | 弹窗列出文件，三个选项：「覆盖（先备份）」；「采用外面改过的个人词库，其余覆盖」（只在有个人词库被改过时出现）；「放弃这次改动」 | 设计第 7 节 |
| 5 | 应用时下载失败 | 本地有旧版本就提示「某某下载失败，可以先用本地旧版本」，点了再应用一次；没有就报错 | 设计第 7 节 |
| 6 | 部署完成但有错误，或者等太久没看到部署完成 | 提示问题，带一个「还原到应用改动前」按钮 | 设计第 7 节 |
| 7 | 编译不过 | 显示翻译后的错误，改动留在草稿里（可以撤销或继续改）。「展开原始日志」以后再做（现在 `Deployer` 只返回翻译后的行） | 设计第 7 节 |
| 8 | 还原 | 列出备份（时间、原因、是否永久保留、文件数），选一个确认后还原。说明里写清楚：还原只换回 Rime 目录里的文件，应用里的设置不变；之后再「应用改动」会按应用里的设置重新写入 | 备份里没有应用的设置（阶段 3 的做法） |
| 9 | 导入前 | 先确认「会换掉现在的设置和个人内容（会另存一份）」；有还没应用的改动时提醒它们也会丢掉 | |
| 10 | 配色的选项 | 从用到的包里读（`squirrel.yaml` 和包自带的 `squirrel.custom.yaml` 里的 `preset_color_schemes`），再加「方案默认」。当前设置的配色不在里面时也照样列出来 | 包里有哪些配色就能选哪些 |
| 11 | 同时启用好几个方案包（例如雾凇和极点五笔） | 允许，方案页显示一句提醒：它们的默认短语、按键设置可能会互相影响 | 你说过这个规则以后再定 |
| 12 | 诊断 | 用 `Doctor`，不联网查鼠须管最新版本（鼠须管自己会提示更新）。提示里还是 `rimectl` 的命令，先照样显示，以后改成界面上的说法 | 先把检查结果搬到界面上 |

## Global Constraints

- 宿主机**不碰** `~/Library/Rime`、`/Library/Input Methods`、输入法启用状态：**不在宿主机上运行应用**，只编译和跑单元测试（假依赖、临时目录）。
- 逻辑全部在 `AppCore`（可测）；视图里不写逻辑，只绑定 `MainModel` 的属性、调用它的方法。
- 真实配置只在 6.1 的写入一步才改；编译失败、外部改动、下载失败时什么都不写，草稿保留。
- 正在做一件事时不接受新操作（和 8a 一样），界面上显示正在做什么。
- 隐私：界面只显示设置、文件名和条数，不显示个人词库、短语、文本替换、输入习惯的内容。
- 第三方依赖只有 Yams。
- 测试机：`squirrel-dev` 用来点主窗口（测完还原：删掉应用的数据目录，`/tmp/rk` 仍然对得上）。点按钮、看界面、打字由用户做。测试机里 SSH 会话进不了 `~/Downloads` 等目录，给应用的文件放 `/Users/Shared`。
- 用简单直白的中文写界面文字和错误信息。
- 提交：按任务提交，阶段结束推送 `main`；提交信息结尾 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. 改了几项再点「应用改动」：写入成功后草稿和已生效的一致，底部的提示消失；编译失败、外部改动、下载失败时什么都没写，草稿还在（任务 4 有测试，任务 9 实测）。
2. 外部改动弹窗的三个选项各自做对了：覆盖前有备份；「采用外面改过的个人词库」后 `personal/` 里是外面的版本（任务 4 有测试）。
3. 还原、导入以后，界面上显示的设置和实际一致；导入前另存了原来的设置（任务 5 有测试）。
4. 方案页：不能把最后一个方案关掉；拖动顺序后第一个就是默认方案（任务 3 有测试，任务 9 实测）。
5. 正在应用、导出、导入时，再点别的按钮不会叠在一起执行（任务 4 有测试）。

---

## 文件结构

```
Sources/RimeKit/Config/ColorSchemes.swift      # 新：包里能选的配色
Sources/AppCore/AppEnvironment.swift           # fetchPackage 只下载；新增 cachedPackage
Sources/AppCore/SetupFlow.swift                # 下载失败用旧版本时在完成页提醒
Sources/AppCore/Notice.swift                   # 新：给界面的消息
Sources/AppCore/MainModel.swift                # 新：主窗口的设置草稿和编辑
Sources/AppCore/MainModel+Actions.swift        # 新：应用、导出、导入、还原、文本替换、诊断
Sources/AppCore/AppState.swift                 # 新：引导还是主窗口
Sources/AppUI/RootView.swift                   # 改用 AppState；完成页「开始使用」
Sources/AppUI/MainView.swift                   # 新：边栏、底部应用栏、消息、外部改动弹窗
Sources/AppUI/SchemasPage.swift、AppearancePage.swift、TextReplacementPage.swift、
  TransferPage.swift、BackupsPage.swift、DiagnosticsPage.swift   # 新
Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift
Tests/RimeKitTests/
  ColorSchemesTests.swift、MainModelTests.swift、MainModelActionsTests.swift、AppStateTests.swift
  SetupFlowTests.swift、Support/AppFakes.swift
docs/phase8b-vm-log.md
```

---

### Task 1: 取包拆成「下载」和「本地缓存」；引导里用旧版本时提醒

**Files:**
- Modify: `Sources/AppCore/AppEnvironment.swift`
- Modify: `Sources/AppCore/SetupFlow.swift`
- Modify: `Tests/RimeKitTests/Support/AppFakes.swift`
- Test: `Tests/RimeKitTests/SetupFlowTests.swift`

**Interfaces:**
- Produces:
  - `AppEnvironment.fetchPackage`：只下载（不再自己退回缓存）
  - `AppEnvironment.cachedPackage: @Sendable (PackageSpec) -> CachedPackage?`（放在 `fetchPackage` 后面）
  - `SetupFlow`：下载失败、本地有缓存时用缓存，并在完成页加一行「某某没下载成（…），先用了本地以前下载的版本」

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/Support/AppFakes.swift`：`environment(…)` 的 `AppEnvironment(` 调用里，`fetchPackage: { … },` 后面加一行：

```swift
            cachedPackage: { packages[$0.id] },
```

`Tests/RimeKitTests/SetupFlowTests.swift` 的 suite 里加：

```swift
    @Test func 下载失败时先用本地旧版本_完成页提醒() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        var env = m.environment()
        env.fetchPackage = { _ in throw HTTPError.transport("断网了") }
        let flow = SetupFlow(env: env)
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .done(let lines) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(lines.contains { $0.contains("没下载成") && $0.contains("测试拼音") })
    }

    @Test func 下载失败又没有缓存时报错() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        var env = m.environment()
        env.fetchPackage = { _ in throw HTTPError.transport("断网了") }
        env.cachedPackage = { _ in nil }
        let flow = SetupFlow(env: env)
        await flow.useSettings(Settings(schemas: ["py"]))
        guard case .failed(let message) = flow.step else { Issue.record("\(flow.step)"); return }
        #expect(message.contains("断网了"))
    }
```

（GenFixtures 里拼音包的名字是「测试拼音」。）

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter SetupFlowTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`extra argument 'cachedPackage'`

- [ ] **Step 3: 实现**

`Sources/AppCore/AppEnvironment.swift`：
1. `fetchPackage` 的注释改成 `/// 下载一个上游包（已经是最新的就直接用缓存；下载失败就抛错）`，后面加：

```swift
    /// 本地缓存里最新的这个包（下载失败时可以先用它）
    public var cachedPackage: @Sendable (PackageSpec) -> CachedPackage?
```

2. `live()` 里 `fetchPackage: { spec in … },` 整段换成：

```swift
            fetchPackage: { try await store.fetch($0) },
            cachedPackage: { store.latestCached(for: $0) },
```

`Sources/AppCore/SetupFlow.swift`：
1. `private var busy = false` 后面加：

```swift
    /// 这次操作里下载失败、改用本地旧版本的说明，完成页上提醒
    private var fallbackNotes: [String] = []
```

2. `fetch` 里 `result[spec.id] = try await env.fetchPackage(spec)` 换成：

```swift
            do {
                result[spec.id] = try await env.fetchPackage(spec)
            } catch where PackageStore.isDownloadFailure(error) {
                // 下载不了时先用本地缓存的旧版本（设计第 7 节），完成页上提醒
                guard let old = env.cachedPackage(spec) else { throw error }
                fallbackNotes.append("\(spec.name) 没下载成（\(error)），先用了本地以前下载的版本")
                result[spec.id] = old
            }
```

3. `finish` 里 `lines += report.warnings + notes` 换成：

```swift
            lines += report.warnings + notes + fallbackNotes
```

并在 `finish` 的最后（`switch` 后面）加 `fallbackNotes = []`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter "SetupFlowTests|TakeoverSummaryTests" 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 全部通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -3
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore Tests/RimeKitTests
git commit -m "feat(app): 取包拆成下载和本地缓存；引导里改用旧版本时在完成页提醒

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 包里能选的配色

**Files:**
- Create: `Sources/RimeKit/Config/ColorSchemes.swift`
- Test: `Tests/RimeKitTests/ColorSchemesTests.swift`

**Interfaces:**
- Produces: `public struct ColorSchemeInfo: Sendable, Equatable, Identifiable { id: String; name: String }`；`public enum ColorSchemes { static func available(in packages: [CachedPackage]) throws -> [ColorSchemeInfo] }`（按 id 排序、去重；名字取配色里的 `name`，没有就用 id）

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/ColorSchemesTests.swift`：

```swift
import Foundation
import Testing
@testable import RimeKit

@Suite struct ColorSchemesTests {
    @Test func 从包里读出配色() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url)
        // 拼音包的 squirrel.yaml 有 aqua（碧水）；五笔包自带的 squirrel.custom.yaml 补丁里有 roseo（玫枫）、roseo_dark（玫枫暗）
        let schemes = try ColorSchemes.available(in: [packages["pinyin"]!, packages["wubi"]!, packages["words"]!])
        #expect(schemes == [
            ColorSchemeInfo(id: "aqua", name: "碧水"),
            ColorSchemeInfo(id: "roseo", name: "玫枫"),
            ColorSchemeInfo(id: "roseo_dark", name: "玫枫暗"),
        ])
    }

    @Test func 没有配色的包是空的() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url)
        #expect(try ColorSchemes.available(in: [packages["words"]!]) == [])
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter ColorSchemesTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'ColorSchemes'`

- [ ] **Step 3: 实现**

`Sources/RimeKit/Config/ColorSchemes.swift`：

```swift
import Foundation
import Yams

public struct ColorSchemeInfo: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// 包里能选的配色：squirrel.yaml 的 preset_color_schemes，加上包自带补丁 squirrel.custom.yaml 里的
public enum ColorSchemes {
    public static func available(in packages: [CachedPackage]) throws -> [ColorSchemeInfo] {
        var result: [String: ColorSchemeInfo] = [:]
        for package in packages {
            for file in ["squirrel.yaml", "squirrel.custom.yaml"] where package.info.files.contains(file) {
                let text = try String(contentsOf: package.filesDirectory.appending(path: file), encoding: .utf8)
                guard let root = try YAMLNode.parse(text) else { continue }
                let presets = file == "squirrel.yaml" ? root["preset_color_schemes"] : root["patch"]?["preset_color_schemes"]
                for (key, value) in presets?.mapping ?? [:] {
                    guard let id = key.string, result[id] == nil else { continue }
                    result[id] = ColorSchemeInfo(id: id, name: value["name"]?.string ?? id)
                }
            }
        }
        return result.values.sorted { $0.id < $1.id }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter ColorSchemesTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 2 个测试通过

如果 `presets?.mapping ?? [:]` 编译不过（`Node.Mapping` 不能用字典字面量初始化）：改成 `guard let mapping = presets?.mapping else { continue }` 再遍历，记一条 Ruling。

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/RimeKit/Config/ColorSchemes.swift Tests/RimeKitTests/ColorSchemesTests.swift
git commit -m "feat: 从包里读出能选的配色

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: 主窗口的设置草稿和编辑

**Files:**
- Create: `Sources/AppCore/Notice.swift`
- Create: `Sources/AppCore/MainModel.swift`
- Test: `Tests/RimeKitTests/MainModelTests.swift`

**Interfaces:**
- Consumes: `AppEnvironment`（任务 1）、`ColorSchemes`（任务 2）
- Produces:
  - `public struct Notice: Identifiable, Equatable, Sendable { id; kind: Kind (.info/.warning/.error); title; lines; action: Action?; actionTitle: String? }`；`enum Action: Equatable, Sendable { case applyUsingCache, restore(String) }`
  - `@MainActor @Observable public final class MainModel`：
    - `enum Page`（6 页，`title`、`symbol`）；`page`
    - `saved`、`draft`、`isDirty`
    - `working: String?`、`notice: Notice?`、`colorSchemes`
    - `init(env:welcome:) throws`（没有设置时抛 `TransferError.noSettings`）
    - `revert()`
    - `catalogPackages`、`schemaName(_:)`、`isEnabled(_:)`、`setEnabled(_:_:)`（不能关掉最后一个）、`moveSchemas(from:to:)`
    - `optionPackages`、`choice(_:of:)`、`setChoice(_:option:of:)`
    - `mixedPackagesNote: String?`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/MainModelTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct MainModelTests {
    typealias T = TransferFixtures

    @Test func 打开时读出设置_没有改动() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment(), welcome: ["设置好了"])
        #expect(model.saved == T.settings)
        #expect(model.draft == T.settings)
        #expect(!model.isDirty)
        #expect(model.notice?.lines == ["设置好了"])
    }

    @Test func 没有设置时打不开() throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        #expect(throws: TransferError.noSettings) { try MainModel(env: m.environment()) }
    }

    @Test func 启用和关掉方案_至少留一个() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)
        #expect(model.draft.schemas == ["wb_py", "py", "wb"])
        #expect(model.isDirty)
        model.setEnabled("wb_py", false)
        model.setEnabled("py", false)
        #expect(model.draft.schemas == ["wb"])
        model.setEnabled("wb", false)
        #expect(model.draft.schemas == ["wb"])
        #expect(model.notice?.title == "至少要留一个方案")
    }

    @Test func 调整顺序_第一个是默认方案() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)                       // [wb_py, py, wb]
        model.moveSchemas(from: IndexSet(integer: 2), to: 0)
        #expect(model.draft.schemas == ["wb", "wb_py", "py"])
        model.moveSchemas(from: IndexSet(integer: 0), to: 3)
        #expect(model.draft.schemas == ["wb_py", "py", "wb"])
    }

    @Test func 撤销() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.setEnabled("wb", true)
        model.draft.appearance.fontPoint = 30
        model.revert()
        #expect(model.draft == model.saved)
        #expect(!model.isDirty)
    }

    @Test func 包选项() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(model.optionPackages.map(\.id) == ["wubi"])
        let wubi = model.optionPackages[0]
        let option = wubi.options[0]
        #expect(model.choice(option, of: wubi) == "ext")
        model.setChoice("builtin", option: option, of: wubi)
        #expect(model.draft.options["wubi"]?["pinyinDictionary"] == "builtin")
    }

    @Test func 方案名字和配色列表() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(model.schemaName("wb_py") == "五笔拼音")
        #expect(model.schemaName("nope") == "nope")
        #expect(model.colorSchemes.map(\.id) == ["aqua", "roseo", "roseo_dark"])
        #expect(model.catalogPackages.map(\.id) == ["pinyin", "wubi"])   // 没有方案的词库包不列
    }

    @Test func 同时启用好几个方案包时提醒() throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        #expect(model.mixedPackagesNote != nil)             // wb_py 和 py 来自两个包
        model.setEnabled("py", false)
        #expect(model.mixedPackagesNote == nil)
    }
}
```

（GenFixtures 里 `wb_py` 的名字是「五笔拼音」；清单里的包顺序是 pinyin、words、wubi，words 没有方案。）

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter MainModelTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'MainModel'`

- [ ] **Step 3: 实现**

`Sources/AppCore/Notice.swift`：

```swift
import Foundation

/// 给界面看的一条消息：结果、错误，可以带一个下一步的按钮
public struct Notice: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case info, warning, error
    }

    public enum Action: Equatable, Sendable {
        /// 下载失败时：用本地缓存的旧版本再应用一次
        case applyUsingCache
        /// 部署有问题时：还原到这个备份
        case restore(String)
    }

    public let id = UUID()
    public var kind: Kind
    public var title: String
    public var lines: [String]
    public var action: Action?
    public var actionTitle: String?

    public init(kind: Kind, title: String, lines: [String], action: Action? = nil, actionTitle: String? = nil) {
        self.kind = kind
        self.title = title
        self.lines = lines
        self.action = action
        self.actionTitle = actionTitle
    }
}
```

`Sources/AppCore/MainModel.swift`：

```swift
import Foundation
import Observation
import RimeKit

/// 主窗口：设置草稿（改了点「应用改动」才生效），以及导出、导入、还原、检查等操作（见 MainModel+Actions）
@MainActor @Observable
public final class MainModel {
    public enum Page: String, CaseIterable, Identifiable, Sendable {
        case schemas, appearance, textReplacement, transfer, backups, diagnostics

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .schemas: return "方案"
            case .appearance: return "外观"
            case .textReplacement: return "文本替换"
            case .transfer: return "导入导出"
            case .backups: return "备份"
            case .diagnostics: return "诊断"
            }
        }

        public var symbol: String {
            switch self {
            case .schemas: return "list.bullet"
            case .appearance: return "textformat.size"
            case .textReplacement: return "text.badge.checkmark"
            case .transfer: return "arrow.up.arrow.down.square"
            case .backups: return "clock.arrow.circlepath"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    public var page: Page = .schemas
    /// 已经生效的设置
    public internal(set) var saved: Settings
    /// 正在改的设置：界面直接改它，点「应用改动」才写进鼠须管
    public var draft: Settings {
        didSet { if oldValue.schemas != draft.schemas || oldValue.options != draft.options { refreshColorSchemes() } }
    }
    public var isDirty: Bool { draft != saved }
    /// 正在做的事（界面上显示）；nil 表示空闲
    public internal(set) var working: String?
    public var notice: Notice?
    public internal(set) var colorSchemes: [ColorSchemeInfo] = []

    let env: AppEnvironment

    public init(env: AppEnvironment, welcome: [String] = []) throws {
        guard let settings = try SettingsStore(paths: env.paths).load() else { throw TransferError.noSettings }
        self.env = env
        saved = settings
        draft = settings
        if !welcome.isEmpty { notice = Notice(kind: .info, title: "设置好了", lines: welcome) }
        refreshColorSchemes()
    }

    public func revert() {
        draft = saved
    }

    // MARK: 方案

    /// 有方案的包（方案页列出来让用户启用）
    public var catalogPackages: [PackageSpec] {
        env.catalog.packages.filter { !$0.schemas.isEmpty }
    }

    public func schemaName(_ id: String) -> String {
        env.catalog.packageOwning(schema: id)?.schemas.first { $0.id == id }?.name ?? id
    }

    public func isEnabled(_ schema: String) -> Bool {
        draft.schemas.contains(schema)
    }

    public func setEnabled(_ schema: String, _ on: Bool) {
        if on {
            if !draft.schemas.contains(schema) { draft.schemas.append(schema) }
            return
        }
        guard draft.schemas != [schema] else {
            notice = Notice(kind: .warning, title: "至少要留一个方案", lines: ["先启用别的方案，再关掉这个"])
            return
        }
        draft.schemas.removeAll { $0 == schema }
    }

    /// 拖动调整顺序（和 SwiftUI 的 onMove 一样：destination 是移动前的下标）；第一个是默认方案
    public func moveSchemas(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.map { draft.schemas[$0] }
        var rest = draft.schemas.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let index = destination - offsets.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(max(index, 0), rest.count))
        draft.schemas = rest
    }

    /// 同时启用了好几个方案包时的提醒（同时启用的规则还没定）
    public var mixedPackagesNote: String? {
        let packages = Set(draft.schemas.compactMap { env.catalog.packageOwning(schema: $0)?.id })
        guard packages.count > 1 else { return nil }
        return "同时启用了好几个方案包的方案，它们的默认短语、按键设置可能会互相影响"
    }

    // MARK: 包选项

    /// 用到的包里有选项的
    public var optionPackages: [PackageSpec] {
        ((try? draft.requiredPackages(env.catalog)) ?? []).filter { !$0.options.isEmpty }
    }

    public func choice(_ option: PackageOption, of package: PackageSpec) -> String {
        draft.choice(option, of: package).id
    }

    public func setChoice(_ id: String, option: PackageOption, of package: PackageSpec) {
        draft.options[package.id, default: [:]][option.id] = id
    }

    // MARK: 配色

    /// 用到的包里能选的配色（从本地缓存读；没有缓存的包跳过）
    func refreshColorSchemes() {
        let packages = ((try? draft.requiredPackages(env.catalog)) ?? []).compactMap { env.cachedPackage($0) }
        colorSchemes = (try? ColorSchemes.available(in: packages)) ?? []
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter MainModelTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 8 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -3
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore Tests/RimeKitTests/MainModelTests.swift
git commit -m "feat(app): 主窗口的设置草稿：方案启用、顺序、包选项、撤销

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: 应用改动

**Files:**
- Create: `Sources/AppCore/MainModel+Actions.swift`
- Test: `Tests/RimeKitTests/MainModelActionsTests.swift`

**Interfaces:**
- Consumes: `MainModel`、`Notice`（任务 3）；RimeKit 的 `Deployer`、`PersonalContent`、`Ledger`、`recordingTextReplacement`
- Produces（`extension MainModel`）：
  - `func apply(_ options: ApplyOptions = ApplyOptions(), usingCache: Bool = false) async`
  - `pendingExternalChanges: [ExternalChange]?`、`pendingPersonalChanges: Bool`
  - `enum ExternalChoice { case overwrite, adoptPersonal, cancel }`；`func resolveExternalChanges(_:) async`
  - `func perform(_ action: Notice.Action) async`
  - 结果：
    - 成功 → `saved = draft = 写入的设置`（含文本替换记录），`notice` 是「改动已经生效」；部署有错误或没完成 → `.warning`，带「还原到应用改动前」。
    - 编译不过 → `.error`，草稿不变。
    - 外部改动 → `pendingExternalChanges`；已经要求覆盖了还是有（目录是外面的链接）→ `.error`。
    - 下载失败、本地有缓存 → `.warning`，带「先用本地旧版本」；没有缓存 → `.error`。
    - 正在做别的事 → 直接返回。

`MainModel` 里给 `+Actions` 用的存储属性要加在 `MainModel.swift` 里（扩展里不能加存储属性）：`pendingExternalChanges`、`pendingPersonalChanges`、`lastApply`（记下上次应用的选项，弹窗选了以后再用）。

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/MainModelActionsTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct MainModelActionsTests {
    typealias T = TransferFixtures

    func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    @Test func 应用改动后生效() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.kind == .info)
        #expect(model.notice?.title == "改动已经生效")
        #expect(!model.isDirty)
        #expect(model.saved.appearance.fontPoint == 26)
        #expect(try SettingsStore(paths: m.paths).load()?.appearance.fontPoint == 26)
        #expect(FileManager.default.fileExists(atPath: m.locations.rimeDirectory.appending(path: "squirrel.custom.yaml").path))
        #expect(model.working == nil)
    }

    @Test func 编译不过时什么都不写_草稿还在() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let failing = FakeCompiler(report: CompileReport(succeeded: false, errors: ["E20261015 boom"]))
        let model = try MainModel(env: m.environment(compiler: failing))
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.kind == .error)
        #expect(model.notice?.title == "新配置编译不过，没有写入")
        #expect(model.isDirty)
        #expect(try SettingsStore(paths: m.paths).load()?.appearance.fontPoint == 22)
    }

    @Test func 外部改动_放弃和覆盖() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()                                   // 先写一次，ledger 里有记录
        let file = m.locations.rimeDirectory.appending(path: "default.custom.yaml")
        try Data((read(file) + "# 在应用外改过\n").utf8).write(to: file)
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.pendingExternalChanges == [.modified("default.custom.yaml")])
        #expect(!model.pendingPersonalChanges)
        await model.resolveExternalChanges(.cancel)
        #expect(model.pendingExternalChanges == nil)
        #expect(model.isDirty)
        #expect(read(file).contains("在应用外改过"))
        await model.apply()
        await model.resolveExternalChanges(.overwrite)
        #expect(model.notice?.title == "改动已经生效")
        #expect(!read(file).contains("在应用外改过"))
        #expect(!model.isDirty)
    }

    @Test func 外部改过的个人词库可以采用() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        let dict = m.locations.rimeDirectory.appending(path: "py_user.dict.yaml")
        let edited = read(dict) + "外面加的\twai mian\t1\n"
        try Data(edited.utf8).write(to: dict)
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.pendingPersonalChanges)
        await model.resolveExternalChanges(.adoptPersonal)
        #expect(model.notice?.title == "改动已经生效")
        #expect(read(m.paths.personalDicts.appending(path: "py_user.dict.yaml")) == edited)
    }

    @Test func 下载失败时可以先用本地旧版本() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        var env = m.environment()
        env.fetchPackage = { _ in throw HTTPError.transport("断网了") }
        let model = try MainModel(env: env)
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.action == .applyUsingCache)
        #expect(model.notice?.lines.joined().contains("断网了") == true)
        #expect(try Ledger.load(m.paths).entries.isEmpty)       // 什么都没写
        await model.perform(.applyUsingCache)
        #expect(model.notice?.title == "改动已经生效")
        #expect(!model.isDirty)
    }

    @Test func 部署有错误时可以还原到应用改动前() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        m.squirrel.errorLine = "E20261015 12:00:00.000000 1 deployer.cc:1] 部署出错"
        model.draft.appearance.fontPoint = 26
        await model.apply()
        guard case .restore(let id)? = model.notice?.action else { Issue.record("\(String(describing: model.notice))"); return }
        #expect(model.notice?.kind == .warning)
        m.squirrel.errorLine = nil
        await model.perform(.restore(id))
        #expect(model.notice?.title.contains("还原") == true)
    }

    @Test func 正在做的时候再点不会重复做() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var value = 0
            func add() { lock.withLock { value += 1 } }
        }
        let fetches = Counter()
        var env = m.environment()
        let fetch = env.fetchPackage
        env.fetchPackage = { spec in
            fetches.add()
            try? await Task.sleep(for: .milliseconds(50))
            return try await fetch(spec)
        }
        let model = try MainModel(env: env)
        model.draft.appearance.fontPoint = 26
        async let first: Void = model.apply()
        async let second: Void = model.apply()
        _ = await (first, second)
        #expect(fetches.value == 3)            // 只应用了一次：要用 words、wubi、pinyin 三个包
        #expect(m.squirrel.calls.count == 1)   // 只部署了一次
    }
}
```

> 注：`T.settings` 是 `wb_py`、`py` 加上五笔的「大词库」选项，要用到 3 个包（words、wubi、pinyin）。

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter MainModelActionsTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`value of type 'MainModel' has no member 'apply'`

- [ ] **Step 3: 实现**

`Sources/AppCore/MainModel.swift`：在 `public var notice: Notice?` 后面加：

```swift
    /// 应用时遇到的外部改动：界面弹窗让用户选（覆盖 / 采用外面改过的个人词库 / 放弃）
    public internal(set) var pendingExternalChanges: [ExternalChange]?
    /// 外部改动里有个人词库被改过（弹窗里多一个「采用」）
    public internal(set) var pendingPersonalChanges = false
    /// 上次应用用的选项（用户在弹窗里选了以后再用）
    var lastApply = (options: ApplyOptions(), usingCache: false)
```

`Sources/AppCore/MainModel+Actions.swift`：

```swift
import Foundation
import RimeKit

extension MainModel {
    public enum ExternalChoice: Sendable {
        case overwrite, adoptPersonal, cancel
    }

    /// 重活放到后台做，界面不卡
    func offMain<T: Sendable>(_ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await Task.detached(operation: body).value
    }

    // MARK: 应用改动（设计 6.1）

    public func apply(_ options: ApplyOptions = ApplyOptions(), usingCache: Bool = false) async {
        guard working == nil else { return }
        let settings = draft
        do {
            try settings.validate(env.catalog)
        } catch {
            notice = Notice(kind: .error, title: "设置有问题", lines: ["\(error)"])
            return
        }
        working = "正在准备……"
        defer { working = nil }
        lastApply = (options, usingCache)
        pendingExternalChanges = nil
        do {
            guard let packages = try await packages(for: settings, usingCache: usingCache) else { return }
            let replacements = settings.textReplacement.sync ? try env.textReplacements().usable : []
            let input = GenerationInput(settings: settings, catalog: env.catalog, packages: packages,
                                        personal: try PersonalContent.load(from: env.paths), textReplacementPhrases: replacements)
            // 写好后（通知鼠须管前）保存设置，并记下这次用的文本替换
            let updated = settings.recordingTextReplacement(replacements)
            let paths = env.paths
            let deployer = env.deployer()
            working = "正在生成配置、检查、备份、写入、部署……"
            let outcome = try await offMain {
                try await deployer.apply(input, options: options, afterWrite: { try SettingsStore(paths: paths).save(updated) })
            }
            switch outcome {
            case .applied(let report):
                saved = updated
                draft = updated
                notice = Self.notice(for: report)
            case .compileFailed(let errors):
                notice = Notice(kind: .error, title: "新配置编译不过，没有写入", lines: errors)
            case .externalChanges(let changes):
                if options.overwriteExternalChanges {
                    // 已经要求覆盖了还是不能写：所在目录是指到 Rime 目录外面的链接
                    notice = Notice(kind: .error, title: "这些文件不能写，没有写入", lines: changes.map(\.description))
                } else {
                    let ledger = try Ledger.load(env.paths)
                    pendingPersonalChanges = changes.contains {
                        guard case .modified(let path) = $0 else { return false }
                        return ledger.entries[path]?.origin == FileOrigin.personal.ledgerValue
                    }
                    pendingExternalChanges = changes
                }
            }
        } catch {
            notice = Notice(kind: .error, title: "没能应用改动", lines: ["\(error)"])
        }
    }

    /// 取用到的包。下载失败、本地有旧版本时提示用户（返回 nil）；没有旧版本就抛错
    func packages(for settings: Settings, usingCache: Bool) async throws -> [String: CachedPackage]? {
        var result: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(env.catalog) {
            working = "正在下载方案：\(spec.name)……"
            if usingCache, let cached = env.cachedPackage(spec) {
                result[spec.id] = cached
                continue
            }
            do {
                result[spec.id] = try await env.fetchPackage(spec)
            } catch where PackageStore.isDownloadFailure(error) {
                guard env.cachedPackage(spec) != nil else { throw error }
                notice = Notice(kind: .warning, title: "\(spec.name) 下载失败",
                                lines: ["\(error)", "本地有以前下载的版本，可以先用它，以后再更新。"],
                                action: .applyUsingCache, actionTitle: "先用本地旧版本")
                return nil
            }
        }
        return result
    }

    static func notice(for report: ApplyReport) -> Notice {
        var lines = ["写入 \(report.written.count) 个文件，没变 \(report.unchanged) 个，删掉 \(report.removed.count) 个"]
        lines += report.warnings
        if !report.deploy.finished {
            lines.append("等了很久还没看到部署完成，可能还在部署；过一会儿再试试打字")
            return Notice(kind: .warning, title: "改动已经写入，但还没看到部署完成", lines: lines,
                          action: .restore(report.backup.id), actionTitle: "还原到应用改动前")
        }
        if !report.deploy.errors.isEmpty {
            return Notice(kind: .warning, title: "部署完成，但有错误", lines: report.deploy.errors + lines,
                          action: .restore(report.backup.id), actionTitle: "还原到应用改动前")
        }
        return Notice(kind: .info, title: "改动已经生效", lines: lines)
    }

    /// 外部改动弹窗里的选择
    public func resolveExternalChanges(_ choice: ExternalChoice) async {
        pendingExternalChanges = nil
        let usingCache = lastApply.usingCache
        switch choice {
        case .cancel:
            return
        case .overwrite:
            await apply(ApplyOptions(overwriteExternalChanges: true), usingCache: usingCache)
        case .adoptPersonal:
            await apply(ApplyOptions(overwriteExternalChanges: true, adoptPersonalChanges: true), usingCache: usingCache)
        }
    }

    /// 消息里的按钮
    public func perform(_ action: Notice.Action) async {
        notice = nil
        switch action {
        case .applyUsingCache:
            await apply(lastApply.options, usingCache: true)
        case .restore(let id):
            await restore(id)
        }
    }

    // MARK: 还原（任务 5 补全备份列表）

    public func restore(_ id: String) async {
        guard working == nil else { return }
        working = "正在还原……"
        defer { working = nil }
        let deployer = env.deployer()
        do {
            let report = try await offMain { try await deployer.restore(id) }
            var lines = ["还原前的状态也备份了：\(report.safetyBackup.id)",
                         "应用里的设置没有变；之后再「应用改动」会按应用里的设置重新写入"]
            lines += report.deploy.errors.map { "部署时有错误：\($0)" } + report.warnings
            notice = Notice(kind: report.deploy.errors.isEmpty ? .info : .warning,
                            title: "已还原到 \(report.restored.id)（\(report.restored.reason)）", lines: lines)
        } catch {
            notice = Notice(kind: .error, title: "没能还原", lines: ["\(error)"])
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter MainModelActionsTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -5`
Expected: 7 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -3
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore Tests/RimeKitTests/MainModelActionsTests.swift
git commit -m "feat(app): 应用改动：外部改动弹窗、下载失败用旧版本、部署有错误时还原

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: 文本替换检查、导出、导入、备份列表、诊断

**Files:**
- Modify: `Sources/AppCore/MainModel.swift`（存储属性）
- Modify: `Sources/AppCore/MainModel+Actions.swift`
- Test: `Tests/RimeKitTests/MainModelActionsTests.swift`

**Interfaces:**
- Consumes: 任务 3、4；RimeKit 的 `Exporter`、`ImportArchive`、`Importer`、`UserDBTransfer`、`BackupStore`、`Doctor`、`TextReplacementSync`
- Produces：
  - `public struct TextReplacementStatus: Equatable, Sendable { usable, badShortcut, badPhrase: Int; changes: TextReplacementSync.Changes?; synced: Bool; error: String? }`
  - `MainModel` 的属性：`textReplacementStatus`、`backups: [BackupInfo]`、`checks: [DoctorCheck]`、`includeUserDB = true`
  - `MainModel` 的方法：`checkTextReplacement() async`、`export(to:) async`、`importFile(_:) async`、`loadBackups()`、`runDiagnostics() async`
  - 导入成功后 `saved`、`draft` 换成导入的设置

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/MainModelActionsTests.swift` 的 suite 里加：

```swift
    final class Replacements: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [Phrase]
        init(_ phrases: [Phrase]) { value = phrases }
        func set(_ phrases: [Phrase]) { lock.withLock { value = phrases } }
        func get() -> TextReplacementSnapshot {
            lock.withLock { TextReplacementSnapshot(usable: value, badShortcut: 1, badPhrase: 0) }
        }
    }

    @Test func 文本替换检查() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let a = Phrase(text: "替换甲", code: "tha", weight: 1)
        let b = Phrase(text: "替换乙", code: "thb", weight: 1)
        let r = Replacements([a])
        let model = try MainModel(env: m.environment(textReplacements: { r.get() }))
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus == TextReplacementStatus(usable: 1, badShortcut: 1, badPhrase: 0, changes: nil, synced: false, error: nil))
        model.draft.textReplacement.sync = true
        await model.apply()
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus?.changes == TextReplacementSync.Changes(added: 0, removed: 0))
        r.set([a, b])
        await model.checkTextReplacement()
        #expect(model.textReplacementStatus?.changes == TextReplacementSync.Changes(added: 1, removed: 0))
        #expect(model.textReplacementStatus?.synced == true)
    }

    @Test func 导出() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        let file = m.dir.url.appending(path: "out/e.zip")
        await model.export(to: file)
        #expect(model.notice?.title == "已导出")
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(m.tool.calls == ["export wb_py"])
        model.includeUserDB = false
        await model.export(to: file)
        #expect(m.tool.calls == ["export wb_py"])   // 这次没导输入习惯
    }

    @Test func 导入后界面上的设置换成导入的() async throws {
        let a = try T.machine(); defer { a.dir.remove() }
        let file = a.dir.url.appending(path: "e.zip")
        _ = try await a.exporter().export(to: file, packages: [])
        let b = try T.machine(userDB: [:]); defer { b.dir.remove() }
        try SettingsStore(paths: b.paths).save(Settings(schemas: ["py"]))
        let model = try MainModel(env: b.environment())
        model.setEnabled("wb", true)                 // 还没应用的改动也会被换掉
        await model.importFile(file)
        #expect(model.saved == T.settings)
        #expect(model.draft == T.settings)
        #expect(model.notice?.lines.contains { $0.contains("另存在") } == true)
    }

    @Test func 备份列表和还原() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        let model = try MainModel(env: m.environment())
        await model.apply()
        model.draft.appearance.fontPoint = 26
        await model.apply()
        model.loadBackups()
        #expect(model.backups.count == 2)
        await model.restore(model.backups[0].id)
        #expect(model.notice?.title.hasPrefix("已还原到") == true)
        model.loadBackups()
        #expect(model.backups.count == 3)   // 还原前又备份了一份
    }

    @Test func 诊断() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try InstallFixtures.writeInfoPlist(app: m.locations.squirrelApp, version: "1.1.2")   // Doctor 靠它判断装没装
        let model = try MainModel(env: m.environment())
        await model.runDiagnostics()
        #expect(model.checks.contains { $0.name == "鼠须管" })
        #expect(model.checks.contains { $0.name == "输入法" && $0.level == .ok })
    }
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter MainModelActionsTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'TextReplacementStatus'`

- [ ] **Step 3: 实现**

`Sources/AppCore/MainModel.swift`：`colorSchemes` 后面加：

```swift
    public internal(set) var textReplacementStatus: TextReplacementStatus?
    public internal(set) var backups: [BackupInfo] = []
    public internal(set) var checks: [DoctorCheck] = []
    /// 导出时带上输入习惯（默认带上）
    public var includeUserDB = true
```

文件末尾（`MainModel` 类外面）加：

```swift
/// 文本替换页显示的状态（只有条数）
public struct TextReplacementStatus: Equatable, Sendable {
    public var usable: Int
    public var badShortcut: Int
    public var badPhrase: Int
    /// 和上次同步时比（同步没打开或从没同步过时为 nil）
    public var changes: TextReplacementSync.Changes?
    /// 同步打开了（已经生效的设置里）
    public var synced: Bool
    /// 读不了时的原因
    public var error: String?

    public init(usable: Int, badShortcut: Int, badPhrase: Int, changes: TextReplacementSync.Changes?, synced: Bool, error: String?) {
        self.usable = usable
        self.badShortcut = badShortcut
        self.badPhrase = badPhrase
        self.changes = changes
        self.synced = synced
        self.error = error
    }
}
```

`Sources/AppCore/MainModel+Actions.swift` 末尾（`extension` 的最后一个 `}` 前面）加：

```swift
    // MARK: 文本替换（设计 6.5）

    public func checkTextReplacement() async {
        let read = env.textReplacements
        let synced = saved.textReplacement
        do {
            let snapshot = try await offMain { try read() }
            textReplacementStatus = TextReplacementStatus(
                usable: snapshot.usable.count, badShortcut: snapshot.badShortcut, badPhrase: snapshot.badPhrase,
                changes: synced.sync ? TextReplacementSync.changes(snapshot.usable, since: synced) : nil,
                synced: synced.sync, error: nil)
        } catch {
            textReplacementStatus = TextReplacementStatus(usable: 0, badShortcut: 0, badPhrase: 0, changes: nil,
                                                          synced: synced.sync,
                                                          error: "\(error)。可以去「系统设置 → 隐私与安全性」检查权限")
        }
    }

    // MARK: 导出（设计 6.3）

    public func export(to file: URL) async {
        guard working == nil else { return }
        working = includeUserDB ? "正在导出（输入法会暂停几秒）……" : "正在导出……"
        defer { working = nil }
        do {
            let versions = try saved.requiredPackages(env.catalog).compactMap { spec in
                env.cachedPackage(spec).map { ExportManifest.Package(id: spec.id, version: $0.info.version) }
            }
            let exporter = Exporter(paths: env.paths, locations: env.locations,
                                    userDB: includeUserDB ? UserDBTransfer(tool: env.userDBTool, squirrel: env.squirrel, sleep: env.sleep) : nil)
            // 保存对话框已经问过要不要覆盖
            let report = try await offMain { try await exporter.export(to: file, packages: versions, overwrite: true) }
            let m = report.manifest
            notice = Notice(kind: .info, title: "已导出", lines: [
                file.path,
                "方案 \(m.settings.schemas.count) 个，个人词库 \(m.personalDicts.count) 个，手动短语 \(m.phrases) 条，输入习惯 \(m.userDB.count) 份（文本替换生成的短语不导出）",
            ] + report.warnings)
        } catch {
            notice = Notice(kind: .error, title: "没能导出", lines: ["\(error)"])
        }
    }

    // MARK: 导入（设计 6.4）

    public func importFile(_ file: URL) async {
        guard working == nil else { return }
        working = "正在读取导出文件……"
        defer { working = nil }
        let work = env.paths.staging.appending(path: "import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let accessing = file.startAccessingSecurityScopedResource()
        defer { if accessing { file.stopAccessingSecurityScopedResource() } }
        do {
            let catalog = env.catalog
            let archive = try await offMain { try ImportArchive.open(file, catalog: catalog, into: work) }
            let settings = archive.manifest.settings
            guard let packages = try await packages(for: settings, usingCache: false) else { return }
            var lines = archive.warnings
            var replacements: [Phrase] = []
            if settings.textReplacement.sync {
                do {
                    replacements = try env.textReplacements().usable
                } catch {
                    lines.append("读不了 macOS 文本替换（\(error)），这次先不带文本替换的短语")
                }
            }
            working = archive.userDB.isEmpty ? "正在写入、部署……" : "正在写入、部署，然后合并输入习惯（输入法会暂停几秒）……"
            let importer = Importer(deployer: env.deployer(),
                                    userDB: UserDBTransfer(tool: env.userDBTool, squirrel: env.squirrel, sleep: env.sleep))
            let phrases = replacements
            let report = try await offMain { try await importer.run(archive, catalog: catalog, packages: packages, textReplacement: phrases) }
            if let previous = report.previous { lines.append("原来的设置和个人内容另存在：\(previous.path)") }
            if let error = report.userDBError { lines.append("输入习惯没有合并上：\(error)。配置已经导入好了，可以再导入一次") }
            switch report.outcome {
            case .applied(let applied):
                if let now = try SettingsStore(paths: env.paths).load() {
                    saved = now
                    draft = now
                }
                var result = Self.notice(for: applied)
                result.title = result.kind == .info ? "已导入" : result.title
                result.lines += lines
                notice = result
            case .compileFailed(let errors):
                notice = Notice(kind: .error, title: "导入的配置编译不过，没有写入", lines: errors + lines)
            case .externalChanges(let changes):
                notice = Notice(kind: .error, title: "这些文件不能写，没有导入", lines: changes.map(\.description) + lines)
            }
        } catch {
            notice = Notice(kind: .error, title: "没能导入", lines: ["\(error)"])
        }
    }

    // MARK: 备份、诊断

    public func loadBackups() {
        backups = BackupStore(paths: env.paths).list()
    }

    public func runDiagnostics() async {
        let read = env.textReplacements
        let doctor = Doctor(paths: env.paths, locations: env.locations, inputSource: env.inputSource, squirrel: env.squirrel,
                            releaseSource: nil, textReplacements: { try read().usable })
        checks = await doctor.run()
    }
```

`restore` 成功或失败后都刷新备份列表：在 `restore` 的 `defer { working = nil }` 后面加 `defer { loadBackups() }`。

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter MainModelActionsTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -5`
Expected: 12 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -3
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore Tests/RimeKitTests/MainModelActionsTests.swift
git commit -m "feat(app): 主窗口的文本替换检查、导出、导入、备份列表、诊断

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: 引导还是主窗口

**Files:**
- Create: `Sources/AppCore/AppState.swift`
- Test: `Tests/RimeKitTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `SetupFlow`（8a）、`MainModel`（任务 3）
- Produces: `@MainActor @Observable public final class AppState { init(env:); setup: SetupFlow; main: MainModel?; openError: String?; func start() async; func openMain(welcome: [String]) }`
  - `start()`：先跑引导的 `start()`；已经由应用管理（引导直接 `.done`）就马上打开主窗口
  - 引导走完、用户在完成页点「开始使用」→ `openMain(welcome: 完成页的说明)`

- [ ] **Step 1: 写失败的测试**

`Tests/RimeKitTests/AppStateTests.swift`：

```swift
import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

@MainActor @Suite struct AppStateTests {
    typealias T = TransferFixtures

    @Test func 已经设置好的直接进主窗口() async throws {
        let m = try T.machine(); defer { m.dir.remove() }
        try Ledger(entries: ["x.yaml": LedgerEntry(sha256: "0", origin: "generated")]).save(m.paths)
        let state = AppState(env: m.environment())
        await state.start()
        #expect(state.main != nil)
        #expect(state.main?.notice == nil)
    }

    @Test func 没设置好的先走引导_走完点开始使用进主窗口() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let state = AppState(env: m.environment())
        await state.start()
        #expect(state.main == nil)
        #expect(state.setup.step == .chooseStart(.empty))
        await state.setup.useSettings(Settings(schemas: ["py"]))
        guard case .done(let lines) = state.setup.step else { Issue.record("\(state.setup.step)"); return }
        state.openMain(welcome: lines)
        #expect(state.main?.saved.schemas == ["py"])
        #expect(state.main?.notice?.lines == lines)
    }

    @Test func 打不开主窗口时说原因() async throws {
        let m = try T.machine(withSettings: false); defer { m.dir.remove() }
        let state = AppState(env: m.environment())
        state.openMain(welcome: [])
        #expect(state.main == nil)
        #expect(state.openError?.contains("还没有设置") == true)
    }
}
```

- [ ] **Step 2: 运行，确认失败**

Run: `swift test --filter AppStateTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: 编译失败，`cannot find 'AppState'`

- [ ] **Step 3: 实现**

`Sources/AppCore/AppState.swift`：

```swift
import Foundation
import Observation
import RimeKit

/// 整个应用的状态：先走第一次打开的引导，设置好了进主窗口
@MainActor @Observable
public final class AppState {
    public let setup: SetupFlow
    public private(set) var main: MainModel?
    /// 打不开主窗口时的原因
    public private(set) var openError: String?
    let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
        setup = SetupFlow(env: env)
    }

    /// 打开应用时：已经由应用管理的直接进主窗口
    public func start() async {
        guard main == nil else { return }
        await setup.start()
        if case .done = setup.step { openMain(welcome: []) }
    }

    /// 引导完成页点「开始使用」
    public func openMain(welcome: [String]) {
        do {
            main = try MainModel(env: env, welcome: welcome)
            openError = nil
        } catch {
            openError = "\(error)"
        }
    }
}
```

- [ ] **Step 4: 运行，确认通过**

Run: `swift test --filter AppStateTests 2>&1 | grep -E "error:|warning:|Expectation failed|Test run" | tail -3`
Expected: 3 个测试通过

- [ ] **Step 5: 全部测试，提交**

```bash
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add Sources/AppCore/AppState.swift Tests/RimeKitTests/AppStateTests.swift
git commit -m "feat(app): 先走引导，设置好了进主窗口

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: 主窗口的框架：边栏、应用栏、消息、外部改动弹窗

**Files:**
- Modify: `Sources/AppUI/RootView.swift`
- Create: `Sources/AppUI/MainView.swift`
- Modify: `Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`

**Interfaces:**
- Consumes: `AppState`、`MainModel`（任务 3–6）
- Produces: `RootView(state: AppState?)`；`MainView(model:)`；页面视图在任务 8 写，这一步先放占位 `Text(page.title)`

- [ ] **Step 1: 改 RootView**

`Sources/AppUI/RootView.swift`：
1. `RootView` 整个换成：

```swift
/// 应用的根视图：先走第一次打开的引导，设置好了进主窗口
public struct RootView: View {
    let state: AppState?

    public init(state: AppState?) {
        self.state = state
    }

    public var body: some View {
        if let state {
            if let main = state.main {
                MainView(model: main)
            } else if let error = state.openError {
                Message(symbol: "exclamationmark.triangle", title: "打不开主窗口", lines: [error])
                    .padding(40)
                    .frame(width: 560)
            } else {
                SetupView(flow: state.setup, onFinish: { state.openMain(welcome: $0) })
                    .task { await state.start() }
                    .frame(width: 560)
                    .frame(minHeight: 360)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Message(symbol: "exclamationmark.triangle", title: "应用里找不到方案清单",
                        lines: ["应用好像坏了，请重新下载"])
            }
            .padding(40)
            .frame(width: 560)
        }
    }
}
```

2. `SetupView` 加属性 `let onFinish: ([String]) -> Void`；`.done(let lines)` 那一段换成：

```swift
        case .done(let lines):
            Message(symbol: "checkmark.circle", title: "设置好了", lines: lines)
            Button("开始使用") { onFinish(lines) }
                .buttonStyle(.borderedProminent)
```

`Sources/SquirrelMacOSApp/SquirrelMacOSApp.swift`：`@State private var flow …` 换成 `@State private var state: AppState? = try? AppState(env: AppEnvironment.live())`，`RootView(flow: flow)` 换成 `RootView(state: state)`。

- [ ] **Step 2: 写主窗口**

`Sources/AppUI/MainView.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI

/// 主窗口：左边栏 6 页；底部是「应用改动」栏；消息和外部改动用弹窗
struct MainView: View {
    @Bindable var model: MainModel

    var body: some View {
        NavigationSplitView {
            List(MainModel.Page.allCases, selection: Binding(get: { model.page }, set: { if let page = $0 { model.page = page } })) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    page
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(model.working != nil)
                ApplyBar(model: model)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .alert(model.notice?.title ?? "", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
               presenting: model.notice) { notice in
            if let action = notice.action, let title = notice.actionTitle {
                Button(title) { Task { await model.perform(action) } }
            }
            Button("好", role: .cancel) {}
        } message: { notice in
            Text(notice.lines.joined(separator: "\n"))
        }
        .confirmationDialog("有文件在应用外被改过", isPresented: Binding(get: { model.pendingExternalChanges != nil }, set: { _ in }),
                            titleVisibility: .visible) {
            Button("覆盖（先备份）") { Task { await model.resolveExternalChanges(.overwrite) } }
            if model.pendingPersonalChanges {
                Button("采用外面改过的个人词库，其余覆盖") { Task { await model.resolveExternalChanges(.adoptPersonal) } }
            }
            Button("放弃这次改动", role: .cancel) { Task { await model.resolveExternalChanges(.cancel) } }
        } message: {
            Text((model.pendingExternalChanges ?? []).map(\.description).joined(separator: "\n"))
        }
    }

    @ViewBuilder var page: some View {
        switch model.page {
        case .schemas: Text(model.page.title)
        case .appearance: Text(model.page.title)
        case .textReplacement: Text(model.page.title)
        case .transfer: Text(model.page.title)
        case .backups: Text(model.page.title)
        case .diagnostics: Text(model.page.title)
        }
    }
}

/// 底部：正在做什么，或者「有改动还没应用 [撤销] [应用改动]」
struct ApplyBar: View {
    let model: MainModel

    var body: some View {
        if let working = model.working {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(working)
                Spacer()
            }
            .padding(12)
            .background(.bar)
        } else if model.isDirty {
            HStack(spacing: 10) {
                Label("有改动还没应用", systemImage: "pencil.circle")
                Spacer()
                Button("撤销") { model.revert() }
                Button("应用改动") { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            .background(.bar)
        }
    }
}
```

- [ ] **Step 3: 编译，打包**

Run:
```bash
swift build 2>&1 | grep -E "error:|warning:" | head -5
./tools/app/build-app.sh
swift test 2>&1 | grep -E "error:|Test run" | tail -2
```
Expected：没有 error、warning；打包成功；测试全部通过。

- [ ] **Step 4: 提交**

```bash
git add Sources/AppUI Sources/SquirrelMacOSApp
git commit -m "feat(app): 主窗口框架：边栏、应用改动栏、消息和外部改动弹窗

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: 6 个页面

**Files:**
- Create: `Sources/AppUI/SchemasPage.swift`、`AppearancePage.swift`、`TextReplacementPage.swift`、`TransferPage.swift`、`BackupsPage.swift`、`DiagnosticsPage.swift`
- Modify: `Sources/AppUI/MainView.swift`（`page` 换成真正的页面）

**Interfaces:**
- Consumes: `MainModel` 的属性和方法（任务 3–5）

- [ ] **Step 1: 方案页、外观页**

`Sources/AppUI/SchemasPage.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI

struct SchemasPage: View {
    @Bindable var model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("启用的方案").font(.title2.bold())
            Text("第一个是默认方案；拖动可以调整顺序。按 Control+0（或 F4）可以在方案之间切换。")
                .foregroundStyle(.secondary)
            List {
                ForEach(model.draft.schemas, id: \.self) { id in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Text(model.schemaName(id))
                        if id == model.draft.schemas.first {
                            Text("默认").font(.caption).padding(.horizontal, 6).background(.quaternary, in: Capsule())
                        }
                        Spacer()
                        Button { model.setEnabled(id, false) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .help("不启用这个方案")
                    }
                }
                .onMove { model.moveSchemas(from: $0, to: $1) }
            }
            .listStyle(.bordered)
            .frame(height: CGFloat(model.draft.schemas.count) * 30 + 12)
            if let note = model.mixedPackagesNote { Note(text: note) }

            Text("可以启用的方案").font(.title2.bold())
            ForEach(model.catalogPackages, id: \.id) { package in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(package.summary).font(.caption).foregroundStyle(.secondary)
                        ForEach(package.schemas, id: \.id) { schema in
                            Toggle(schema.name, isOn: Binding(get: { model.isEnabled(schema.id) },
                                                              set: { model.setEnabled(schema.id, $0) }))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("\(package.name)（\(package.license)）").font(.headline)
                }
            }

            if !model.optionPackages.isEmpty {
                Text("选项").font(.title2.bold())
                ForEach(model.optionPackages, id: \.id) { package in
                    ForEach(package.options, id: \.id) { option in
                        Picker("\(package.name) · \(option.name)",
                               selection: Binding(get: { model.choice(option, of: package) },
                                                  set: { model.setChoice($0, option: option, of: package) })) {
                            ForEach(option.choices, id: \.id) { Text($0.name).tag($0.id) }
                        }
                    }
                }
            }
        }
    }
}
```

`Sources/AppUI/AppearancePage.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI

struct AppearancePage: View {
    @Bindable var model: MainModel

    var body: some View {
        Form {
            Section("配色") {
                schemePicker("浅色模式", selection: $model.draft.appearance.colorScheme)
                schemePicker("深色模式", selection: $model.draft.appearance.colorSchemeDark)
            }
            Section("字号（浅色、深色配色一起改）") {
                OptionalStepper(title: "候选字", value: $model.draft.appearance.fontPoint, range: Settings.fontPointRange, start: 18)
                OptionalStepper(title: "序号", value: $model.draft.appearance.labelFontPoint, range: Settings.fontPointRange, start: 16)
                OptionalStepper(title: "注释", value: $model.draft.appearance.commentFontPoint, range: Settings.fontPointRange, start: 16)
            }
            Section("排列") {
                Picker("候选", selection: $model.draft.appearance.candidateListLayout) {
                    Text("方案默认").tag(CandidateListLayout?.none)
                    Text("横排").tag(CandidateListLayout?.some(.linear))
                    Text("竖排").tag(CandidateListLayout?.some(.stacked))
                }
                Picker("文字方向", selection: $model.draft.appearance.textOrientation) {
                    Text("方案默认").tag(TextOrientation?.none)
                    Text("横排").tag(TextOrientation?.some(.horizontal))
                    Text("竖排").tag(TextOrientation?.some(.vertical))
                }
                OptionalStepper(title: "每页候选数", value: $model.draft.appearance.pageSize, range: Settings.pageSizeRange, start: 5)
            }
        }
        .formStyle(.grouped)
    }

    func schemePicker(_ title: String, selection: Binding<String?>) -> some View {
        let ids = model.colorSchemes.map(\.id)
        return Picker(title, selection: selection) {
            Text("方案默认").tag(String?.none)
            ForEach(model.colorSchemes) { Text($0.name).tag(String?.some($0.id)) }
            if let current = selection.wrappedValue, !ids.contains(current) {
                Text(current).tag(String?.some(current))
            }
        }
    }
}

/// 可以选「方案默认」的数字设置
struct OptionalStepper: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    /// 从「方案默认」改成自定义时的起始值
    let start: Int

    var body: some View {
        HStack {
            Toggle(title, isOn: Binding(get: { value != nil }, set: { value = $0 ? (value ?? start) : nil }))
            Spacer()
            if let current = value {
                Stepper("\(current)", value: Binding(get: { current }, set: { value = $0 }), in: range)
                    .fixedSize()
            } else {
                Text("方案默认").foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 2: 文本替换页、导入导出页、备份页、诊断页**

`Sources/AppUI/TextReplacementPage.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI

struct TextReplacementPage: View {
    @Bindable var model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("macOS 文本替换").font(.title2.bold())
            Text("把「系统设置 → 键盘 → 文本替换」里的条目变成鼠须管的自定义短语。快捷码只有英文字母的条目才能在鼠须管里打出来。文本替换的内容不会导出（同一个 Apple 账户在新电脑上会自动同步）。")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("同步文本替换", isOn: $model.draft.textReplacement.sync)
            Text("打开、关掉以后，点底部的「应用改动」才生效。同步开着时，每次应用改动都会带上最新的文本替换。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("现在的状态").font(.headline)
                Spacer()
                Button("检查") { Task { await model.checkTextReplacement() } }
            }
            if let status = model.textReplacementStatus {
                if let error = status.error {
                    Note(text: "读不了文本替换：\(error)")
                } else {
                    Text("能用的 \(status.usable) 条")
                    if status.badShortcut > 0 { Text("快捷码里有英文字母以外的字符、打不出来的 \(status.badShortcut) 条").foregroundStyle(.secondary) }
                    if status.badPhrase > 0 { Text("内容是空的、有换行或 Tab 的 \(status.badPhrase) 条").foregroundStyle(.secondary) }
                    if status.synced {
                        if let changes = status.changes {
                            if changes.isEmpty {
                                Label("和上次同步时一样", systemImage: "checkmark.circle")
                            } else {
                                Note(text: "和上次同步比：新增 \(changes.added) 条，删掉 \(changes.removed) 条")
                                Button("同步这些变化") { Task { await model.apply(); await model.checkTextReplacement() } }
                                    .buttonStyle(.borderedProminent)
                            }
                        } else {
                            Note(text: "还没同步过")
                            Button("现在同步") { Task { await model.apply(); await model.checkTextReplacement() } }
                        }
                    }
                }
            }
        }
        .task { await model.checkTextReplacement() }
    }
}
```

`Sources/AppUI/TransferPage.swift`：

```swift
import AppCore
import AppKit
import RimeKit
import SwiftUI
import UniformTypeIdentifiers

struct TransferPage: View {
    @Bindable var model: MainModel
    @State private var choosing = false
    @State private var importing: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出").font(.title2.bold())
            Text("把设置、个人词库、手动短语打成一个文件，在新电脑上用这个应用一键导入。不放上游方案文件（导入时下载最新版），也不放文本替换生成的短语。")
                .fixedSize(horizontal: false, vertical: true)
            Toggle("带上输入习惯（导出时输入法会暂停几秒）", isOn: $model.includeUserDB)
            Button("导出…") { chooseExportFile() }
                .buttonStyle(.borderedProminent)
            Divider()
            Text("导入").font(.title2.bold())
            Text("用导出文件换掉现在的设置和个人内容（现在的会先另存一份）；输入习惯是合并，不会丢掉这台电脑上已经学到的。")
                .fixedSize(horizontal: false, vertical: true)
            Button("从导出文件导入…") { choosing = true }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result { importing = url }
        }
        .confirmationDialog("导入会换掉现在的设置和个人内容", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                            titleVisibility: .visible) {
            Button("导入") {
                if let url = importing { Task { await model.importFile(url) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(model.isDirty ? "现在的设置和个人内容会另存一份。还没应用的改动也会丢掉。" : "现在的设置和个人内容会另存一份。")
        }
    }

    func chooseExportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "squirrel-macos 导出.zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.export(to: url) }
    }
}
```

`Sources/AppUI/BackupsPage.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI

struct BackupsPage: View {
    let model: MainModel
    @State private var restoring: BackupInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("备份").font(.title2.bold())
            Text("每次写入前都会备份 Rime 目录里的配置文件（留最近 10 份；第一次接管、导入前的那份永久保留）。还原只换回 Rime 目录里的文件，应用里的设置不变；之后再「应用改动」会按应用里的设置重新写入。")
                .fixedSize(horizontal: false, vertical: true)
            if model.backups.isEmpty {
                Text("还没有备份").foregroundStyle(.secondary)
            }
            ForEach(model.backups, id: \.id) { backup in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backup.createdAt.formatted(date: .numeric, time: .shortened))
                        Text("\(backup.reason)\(backup.permanent ? "，永久保留" : "") · \(backup.files.count) 个文件")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("还原…") { restoring = backup }
                }
                Divider()
            }
        }
        .task { model.loadBackups() }
        .confirmationDialog("还原到这个备份？", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("还原") {
                if let backup = restoring { Task { await model.restore(backup.id) } }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("还原前会先给现在的状态做一份备份，还原也能撤销。")
        }
    }
}
```

`Sources/AppUI/DiagnosticsPage.swift`：

```swift
import AppCore
import RimeKit
import SwiftUI

struct DiagnosticsPage: View {
    let model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("诊断").font(.title2.bold())
                Spacer()
                Button("重新检查") { Task { await model.runDiagnostics() } }
            }
            ForEach(Array(model.checks.enumerated()), id: \.offset) { _, check in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(check.level))
                        .foregroundStyle(color(check.level))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(check.name)：\(check.message)")
                        if let hint = check.hint {
                            Text(hint).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .task { await model.runDiagnostics() }
    }

    func symbol(_ level: CheckLevel) -> String {
        switch level {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    func color(_ level: CheckLevel) -> Color {
        switch level {
        case .ok: return .green
        case .warning: return .orange
        case .problem: return .red
        }
    }
}
```

`Sources/AppUI/MainView.swift` 的 `page` 换成：

```swift
    @ViewBuilder var page: some View {
        switch model.page {
        case .schemas: SchemasPage(model: model)
        case .appearance: AppearancePage(model: model)
        case .textReplacement: TextReplacementPage(model: model)
        case .transfer: TransferPage(model: model)
        case .backups: BackupsPage(model: model)
        case .diagnostics: DiagnosticsPage(model: model)
        }
    }
```

- [ ] **Step 3: 编译，打包**

Run:
```bash
swift build 2>&1 | grep -E "error:|warning:" | head -8
./tools/app/build-app.sh
swift test 2>&1 | grep -E "error:|Test run" | tail -2
```
Expected：没有 error、warning；打包成功；测试全部通过。编译报错时，按报错改视图代码（不改 `AppCore` 的接口），记一条 Ruling。

- [ ] **Step 4: 提交**

```bash
git add Sources/AppUI
git commit -m "feat(app): 主窗口 6 个页面：方案、外观、文本替换、导入导出、备份、诊断

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: 测试机里由用户点一遍主窗口

**Files:**
- Create: `docs/phase8b-vm-log.md`

**Interfaces:**
- Consumes: 任务 1–8；`tools/vm/install-app.sh`
- Produces: 实测记录；逻辑问题先写假依赖的失败测试再修（在 `MainModel`），界面问题直接改视图

用 `squirrel-dev`：应用的数据目录是空的，打开后走接管（8a 已经测过），完成页点「开始使用」进主窗口。每一步用 AskUserQuestion 问用户看到了什么（至少两个选项，带「有问题，写在备注里」）。

- [ ] **Step 1: 进主窗口**

```bash
./tools/vm/vm.sh ssh squirrel-dev 'ls ~/Library/Application\ Support/squirrel-macos 2>/dev/null || echo 空的'
./tools/vm/install-app.sh squirrel-dev
```

请用户：接管 → 完成页点「开始使用」→ 看到主窗口，左边 6 页，弹出「设置好了」的消息。

- [ ] **Step 2: 方案、外观、应用改动**

请用户：
1. 方案页：启用「小鹤双拼」，拖到第一个。底部出现「有改动还没应用」。点「撤销」后回到原样；再改一次。
2. 外观页：候选字字号改成 28，深色配色选一个别的。
3. 点「应用改动」：底部显示正在做什么，然后弹出「改动已经生效」。
4. 打字检查：默认方案变成小鹤双拼（`nihc` → 你好），候选字明显变大。

- [ ] **Step 3: 外部改动**

在测试机里改一个应用管理的文件：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'echo "# 在应用外改过" >> ~/Library/Rime/default.custom.yaml'
```

请用户在外观页改一下每页候选数，点「应用改动」：弹出「有文件在应用外被改过」，列出 `default.custom.yaml`。先点「放弃这次改动」：底部的提示还在。再点「应用改动」→「覆盖（先备份）」→「改动已经生效」。

- [ ] **Step 4: 文本替换、导出、导入、备份、诊断**

请用户依次：
1. 文本替换页：看到「能用的 N 条」；打开「同步文本替换」→「应用改动」→ 状态变成「和上次同步时一样」；打 `tstx` → 测试短语。
2. 导入导出页：「导出…」保存到 `/Users/Shared/phase8b.zip` → 弹出「已导出」（导出时输入法暂停几秒）。
3. 备份页：看到几份备份；对最近一份点「还原…」→「还原」→ 弹出「已还原到…」。
4. 诊断页：各项是绿的。
5. 导入导出页：「从导出文件导入…」选 `/Users/Shared/phase8b.zip` → 确认 → 弹出「已导入」，带「原来的设置和个人内容另存在…」。

- [ ] **Step 5: 还原测试机**

把 `squirrel-dev` 还原到 rimectl `/tmp/rk` 管理的状态：

```bash
./tools/vm/vm.sh ssh squirrel-dev 'pkill -x SquirrelMacOSApp; rm -rf ~/Library/Application\ Support/squirrel-macos /Users/Shared/phase8b.zip'
```

然后在测试机里用 rimectl（先复制到本地，见 `CLAUDE.md`）`apply --overwrite --cache-only --data-dir /tmp/rk`，把 Rime 目录写回 `/tmp/rk` 的设置。`status` 没有外部改动、`textreplacement status` 显示同步关着，就算还原好了。请用户确认打字和原来一样（雾凇全拼、24 号、每页 7 个）。

- [ ] **Step 6: 写记录，提交**

`docs/phase8b-vm-log.md`：每一步用户看到的、发现的问题和怎么修的。

```bash
git add docs/phase8b-vm-log.md
git commit -m "docs: 阶段 8b 测试机实测记录（主窗口）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: 更新文档

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md`（第 7 节表格后加「界面上的做法」；8.3）
- Modify: `docs/superpowers/plans/2026-10-15-roadmap.md`、`CLAUDE.md`、`README.md`

- [ ] **Step 1: 设计文档**

第 7 节「隐私」那一段后面加：

```markdown
**界面上的做法（阶段 8b 定下）**：
- 改设置（方案、外观、文本替换开关）先改在草稿里，底部出现「有改动还没应用 [撤销] [应用改动]」，点了才走 6.1。草稿不落盘。
- 外部改动：弹窗列出文件，选「覆盖（先备份）」「采用外面改过的个人词库，其余覆盖」（有个人词库被改过时才有）或「放弃这次改动」。
- 下载失败：本地有旧版本时提示，点「先用本地旧版本」再应用一次。第一次打开的引导里自动用旧版本，完成页提醒。
- 部署有错误或没看到部署完成：提示问题，带「还原到应用改动前」。
- 还原只换回 Rime 目录里的文件，应用里的设置不变；界面上写明。
```

8.3 末尾加：`- 主窗口（阶段 8b）：左边栏 6 页（方案、外观、文本替换、导入导出、备份、诊断）；逻辑在 AppCore 的 MainModel，宿主机用假依赖测。`

- [ ] **Step 2: 路线图、CLAUDE.md、README**

- 路线图 8b 那一行的成果末尾加「（已完成，2026-10-15）」。
- `CLAUDE.md` 第一段的阶段状态改成「阶段 0–8 已完成（…；应用骨架和第一次打开的引导；主窗口），第一版功能都有了；下一步按设计第 11 节准备发布（应用名、许可证、签名公证），或者整理待改进项」。
- `README.md` 「应用：」那一行改成：`- 应用：./tools/app/build-app.sh 打包成 .build/app/squirrel-macos.app；第一次打开走引导，之后是主窗口（方案、外观、文本替换、导入导出、备份、诊断）。只在测试机里打开（./tools/vm/install-app.sh 测试机名字）`（命令用反引号）。

- [ ] **Step 3: 检查，提交**

```bash
grep -n "阶段 8b 定下" docs/superpowers/specs/2026-10-15-squirrel-macos-v1-design.md
swift test 2>&1 | grep -E "error:|Test run" | tail -2
git add docs CLAUDE.md README.md
git commit -m "docs: 阶段 8b 完成：界面上的出错处理写进设计，更新路线图和说明

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

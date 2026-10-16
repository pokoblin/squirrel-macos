# 五笔个人词库编辑器 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 应用里加「五笔词库」页：给极点五笔的个人词库加词（自动算五笔编码、让用户选排第几）、批量导入、改删、检查能不能打出来。

**Architecture:**
- RimeKit 新模块 `WubiDict`：词库文件读写（保留原样的行）、按词库里的 `encoder` 规则算编码、编码索引和权重、个人词库的存储（起点、合并外面的修改）、批量导入解析、检查（用试打预览的 `PreviewWorkspace` + `PreviewSession` + `PreviewProbe`）。
- AppCore `WubiDictModel` 放页面逻辑，AppUI `WubiDictPage` 只管显示；`rimectl wubi` 用同一套。
- 个人词库的改动马上写进 `personal/`，「应用改动」照旧把它写进 Rime 目录。

**Tech Stack:** Swift 6.4、Swift Testing、SwiftUI、Yams（读词库头部）、正则（`Regex`）。

**执行方式：** Subagent-driven（用户 2026-10-16 选定）。

**Spec:** [docs/superpowers/specs/2026-10-16-wubi-user-dict-design.md](../specs/2026-10-16-wubi-user-dict-design.md)（下面写成「设计 x.y」）。依赖的试打预览：[2026-10-16-typing-preview-design.md](../specs/2026-10-16-typing-preview-design.md)。

## 计划里定下的细节（设计没写死的地方）

| # | 问题 | 计划里的做法 |
|---|---|---|
| 1 | 编辑哪个包、哪些文件 | 写成一个常量 `WubiDictTarget.jidian`：包 id `wubi86-jidian`，主词库 `wubi86_jidian.dict.yaml`，个人词库 `wubi86_jidian_user.dict.yaml`，方案前缀 `wubi86_jidian`。测试换成夹具的同名包，所以夹具用同样的 id 和文件名 |
| 2 | 「有没有没应用的词库改动」怎么记 | 不另存状态：`personal/dicts/wubi86_jidian_user.dict.yaml` 的哈希和账本里这个路径记的哈希不一样，就算有改动（应用重启后也对） |
| 3 | 收回外面的修改以后，怎么让「应用改动」不再把它当外部改动 | 合并后在应用锁里把账本这个路径的哈希改成 Rime 目录里那份当前的哈希（「已经看过了」）。下次应用时它不再算外部改动，会被 `personal/` 里合并后的版本覆盖 |
| 4 | 同一编码下的顺序（权重相同时） | 先按权重从大到小；权重相同时按「主词库在前、导入表按 `import_tables` 的顺序、同一文件里按行的顺序」。任务 3 用真 librime 的集成测试确认；不对就按实测改，并记进 verified-facts |
| 5 | 放在第一个前面的权重 | 第一个的权重 + 10（留出以后再插的空档）。放在第 n−1 和第 n 个之间：两者权重差 ≥ 2 时取中间（向下取整）；差 < 2 时「放不进去」。放在最后：不写权重 |
| 6 | 检查时「排第几」和试打结果怎么比 | `PreviewProbe.find` 的结果加一个 `overall`：前面各页的候选数 + 本页序号（从 0 起）。和索引里算出的位置（从 0 起）比 |
| 7 | 判断「汉字」 | `Character` 只有一个 Unicode 标量，且 `properties.isIdeographic` 为真 |
| 8 | 页面在哪 | `MainModel.Page` 在 `.preview` 后面加 `.wubiDict`，标题「五笔词库」，图标 `character.book.closed` |
| 9 | 联网的完整测试 | `RIMEKIT_ONLINE=1 swift test --filter OnlineWubiDictTests`：下载真的极点五笔包，检查「张三丰」→ `xddh`、「宋氏」（二字）、「中华人民共和国」（长词）的编码和 librime 一致 |

## Global Constraints

- 只做五笔（极点五笔 86）。只编辑 `wubi86_jidian_user.dict.yaml`；主词库、扩展词库、`wubi86_jidian_user_hamster.dict.yaml` 只读（设计 1）。
- 组词规则、单字编码、`exclude_patterns` 一律从缓存包里的 `wubi86_jidian.dict.yaml` 读，不写死（设计 4.2）。
- 单字全码 = 这个字最长的编码，`exclude_patterns` 匹配的不算；最长的不止一个时列出所有组合（设计 2.2、4.2）。
- 手动编码：只能是 `a`–`y` 小写字母，1 到 4 个（设计 4.2）。
- 导入格式：UTF-8 纯文本，每行 `词`、`词<Tab或空格>编码`、`词<Tab>编码<Tab>权重`；空行和 `#` 开头的行跳过；`---`…`...` 头部跳过；词含空格时只能用 Tab（设计 4.3）。
- 保存时只改词条行：头部、注释、空行、认不出的行原样保留，原有词条顺序不变，新词加在末尾（设计 4.4）。
- 不改上游词或用户已有词的权重（设计 4.5）。
- 页面和检查都不联网：只用本地缓存的包（设计第 5 节）。
- 检查用 `settings.schemas` 里第一个以 `wubi86_jidian` 开头的方案（设计 4.6）。
- 界面文字用设计里的原话：「先在「方案」页启用极点五笔」「还没下载极点五笔，先应用一次改动」「认不出这个版本的极点五笔词库，自动编码用不了」「已经加过了」「词库里已经有了」「这个位置放不进去」「鼠须管目录里的五笔个人词库在应用外被改过」「把外面加的词收进来」「检查能不能打出来」。
- 隐私：测试、日志只用虚构的词；不打印用户词库内容，只统计条数（设计第 6 节）。
- 不碰宿主机真实的 `~/Library/Rime`；测试只用临时目录；librime 只在副本上跑。
- 每个任务：先写测试看它失败，再实现，再跑 `swift test`（全部通过）。视图层没有单元测试，`swift build` 通过、测试机里检查。
- 提交：按任务提交，提交信息用中文，**不加署名行**；推送前问用户。

## Review Focus

1. **用户的个人词库里有手写的注释、分组行、奇怪的行**（`dict_grouped`、`## 分组`、多一列 stem、空格分隔）：保存后这些行一个不少、顺序不变——任务 1 有测试（往返不变）。
2. **主词库里没有的字、非汉字（字母、数字、emoji）、扩展区汉字**：不崩，给出「算不出」并让用户手填——任务 2 有测试。
3. **批量导入的文本有 BOM、Windows 换行（`\r\n`）、全角空格、重复行**：能正确解析，重复只留第一行——任务 5 有测试。
4. **两个相邻词权重没有空档、编码下还没有词、编码下全是不带权重的词**：给出「放不进去」或合理的权重，不改别人的权重——任务 3 有测试。
5. **用户在应用外改过 Rime 目录里的个人词库，同时应用里也加了词**：收回时按词条合并，两边的词都在——任务 4 有测试。

---

## 文件结构

| 文件 | 做什么 | 任务 |
|---|---|---|
| `Sources/RimeKit/WubiDict/DictFile.swift`（新） | `.dict.yaml` 读写：头部、列、词条，保留原样的行 | 1 |
| `Sources/RimeKit/WubiDict/WubiEncoder.swift`（新） | 组词规则、单字全码、算编码、手动编码校验 | 2 |
| `Sources/RimeKit/WubiDict/WubiCodeIndex.swift`（新） | 编码 → 已有词和权重（主词库 + 导入表），排第几 → 权重 | 3 |
| `Sources/RimeKit/WubiDict/WubiDictTarget.swift`（新） | 包 id、文件名常量 | 3 |
| `Sources/RimeKit/WubiDict/WubiUserDict.swift`（新） | 个人词库的存储：起点、加改删、保存、有没有改动、外部修改的检测和合并 | 4 |
| `Sources/RimeKit/Deploy/Ledger.swift` | 加 `acknowledge(path:sha256:)` | 4 |
| `Sources/RimeKit/WubiDict/WubiImport.swift`（新） | 批量导入的解析和每行状态 | 5 |
| `Sources/RimeKit/Preview/PreviewProbe.swift` | `PreviewMatch.overall` | 6 |
| `Sources/RimeKit/WubiDict/WubiCheck.swift`（新） | 检查能不能打出来 | 6 |
| `Sources/rimectl/Wubi.swift`（新）、`Rimectl.swift` | `rimectl wubi …` | 7 |
| `Sources/AppCore/WubiDictModel.swift`（新）、`MainModel.swift`、`MainModel+Actions.swift` | 页面逻辑、接进主窗口、「有改动还没应用」 | 8 |
| `Sources/AppUI/WubiDictPage.swift`、`WubiImportSheet.swift`（新）、`MainView.swift` | 页面和导入表 | 9 |
| `Tests/RimeKitTests/Support/WubiFixtures.swift`（新） | 迷你极点五笔包（同 id、同文件名）、编译好的副本 | 2、3 |
| `Tests/RimeKitTests/OnlineWubiDictTests.swift`（新）、docs | 联网测试、测试机记录、文档 | 10 |

---

### Task 1: 词库文件读写 `DictFile`

**Files:**
- Create: `Sources/RimeKit/WubiDict/DictFile.swift`
- Test: `Tests/RimeKitTests/DictFileTests.swift`

**Interfaces:**
- Produces（RimeKit，`public`、`Sendable`）：
  - `struct DictEntry: Equatable { var text: String; var code: String?; var weight: Int? }`
  - `struct DictFile: Equatable`：`var columns: [String]`（头部的 `columns`，没有就是 `["text", "code", "weight"]`）；`var importTables: [String]`；`var sort: String?`；`var entries: [DictEntry] { get }`；`static func parse(_ text: String) throws -> DictFile`；`func render() -> String`；`mutating func append(_ e: DictEntry)`；`mutating func removeEntries(where: (DictEntry) -> Bool)`；`mutating func replaceEntry(at index: Int, with e: DictEntry)`（index 是 `entries` 里的序号）
  - `enum DictFileError: Error, Equatable { case noHeader, notUTF8 }`
- 内部：按原文的每一行存成「头部原文 / 词条（记下原行文本，没改过就原样输出）/ 其他原样行」。

- [ ] **Step 1: 写失败的测试**：

```swift
@Test func 往返不变() throws {   // 含 BOM 以外的一切：头部注释、dict_grouped、空行、「## 分组」注释、空格分隔的行、四列（含 stem）的行
    let text = "# 注释\n---\nname: x\nversion: \"1\"\nsort: original\ndict_grouped: true\n...\n## 分组一\n张三丰\txddh\n\n奇怪 的行\n李四\tsbl\t20\tsb\n"
    #expect(try DictFile.parse(text).render() == text)
}
@Test func 读出词条() throws {   // 上面的文本：entries == [张三丰/xddh/nil, 李四/sbl/20]；「奇怪 的行」不是词条（只有一列且列间不是 Tab）——按 columns 用 Tab 拆，拆出一列且 text 含空格的算原样行
}
@Test func 只写词的行() throws { /* "王五\n" → DictEntry(text: "王五", code: nil, weight: nil) */ }
@Test func 列顺序按头部() throws { /* columns: [text, weight, code] 时 "词\t5\tabc" → code abc、weight 5；render 加新词也按这个顺序写 */ }
@Test func 加词改词删词只动对应的行() throws {
    // append 加在文件末尾（末尾没有换行时先补一个）；replaceEntry 只改那一行；removeEntries 只删那些行；其余行逐字不变
}
@Test func 读头部() throws { /* importTables == ["a_user", "a_extra"]、sort == "by_weight"（夹具里的 import_tables 带行尾注释） */ }
@Test func 没有头部() { #expect(throws: DictFileError.noHeader) { try DictFile.parse("张三\tabc\n") } }
```

- [ ] **Step 2: 跑 `swift test --filter DictFileTests`**，Expected：编译失败。
- [ ] **Step 3: 实现**：头部是第一个 `---` 行到 `...` 行（Yams 读 `columns`、`import_tables`、`sort`）；正文逐行分类；渲染时没改过的行用原文。
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(wubi): 词库文件读写，保留原样的行`

---

### Task 2: 算五笔编码 `WubiEncoder`

**Files:**
- Create: `Sources/RimeKit/WubiDict/WubiEncoder.swift`、`Tests/RimeKitTests/Support/WubiFixtures.swift`
- Test: `Tests/RimeKitTests/WubiEncoderTests.swift`

**Interfaces:**
- Consumes: `DictFile`（任务 1）
- Produces（`public`）：
  - `struct WubiEncoder: Sendable { init(mainDict: DictFile) throws; func encode(_ word: String) -> WubiEncoding; static func isValidCode(_ code: String) -> Bool }`
  - `enum WubiEncoding: Equatable, Sendable { case codes([String]) /* 至少一个，第一个是默认 */; case unknown([Character]) /* 主词库里没有的字或非汉字 */; case singleCharacter /* 一个字的词，编码要手填 */ }`
  - `enum WubiEncoderError: Error, Equatable { case noRules }` → 对应「认不出这个版本的极点五笔词库」
  - 规则：`encoder/rules` 的 `length_equal`、`length_in_range` 和 `formula`（大写字母 A–Z 是字序，`Z` 是最后一字，`Y` 倒数第二；小写字母 a–z 是那个字编码里的第几码，`z` 是最后一码）；`encoder/exclude_patterns` 是正则
- `WubiFixtures`：`static let catalogJSON`（一个 id 为 `wubi86-jidian` 的包，`userDicts: ["wubi86_jidian_user.dict.yaml"]`，方案 `wubi86_jidian`）；`static let mainDict`（真包的 `encoder` 段原样 + 约 30 个单字和若干词，含「张 xt/xta/xtay」「三 dg/dgg/dggg」「丰 dh/dhk」「戈」两个四码全码、一个只有 `z` 码之外还有正常码的字）；`static func makePackage(in cache: URL) throws -> CachedPackage`；`static func compiled(in dir: URL, userDict: String? = nil) throws -> URL`（生成最小的 `wubi86_jidian.schema.yaml` + `default.custom.yaml` + 词库，用 `RimeTools.build` 编译）

- [ ] **Step 1: 写失败的测试**：

```swift
@Test func 三字词() throws { #expect(try enc().encode("张三丰") == .codes(["xddh"])) }
@Test func 二字词() throws { /* 「张三」→ AaAbBaBb = "xtdg" */ }
@Test func 四字词() throws { /* 夹具里四个字的词 → AaBaCaZa */ }
@Test func 超出规则的长度() throws { /* 十一个字（规则只到十）→ .unknown([])，界面说「这个长度算不出编码，请手动填」 */ }
@Test func 最长码不止一个时列出组合() throws { /* 含「戈」的二字词 → .codes 有两个，顺序按主词库里出现的先后 */ }
@Test func 排除z开头的码() throws { /* 某字有 z 开头的更长编码时不用它 */ }
@Test func 主词库里没有的字() throws { /* 「张𠀀」→ .unknown(["𠀀"])；「张A」→ .unknown(["A"])；「张😀」→ .unknown(["😀"]) */ }
@Test func 单字() throws { #expect(try enc().encode("张") == .singleCharacter) }
@Test(arguments: ["a", "abcd", "xddh", "y"]) func 合法编码(_ c: String) { #expect(WubiEncoder.isValidCode(c)) }
@Test(arguments: ["", "abcde", "z", "abz", "AB", "a1", "ab cd"]) func 不合法编码(_ c: String) { #expect(!WubiEncoder.isValidCode(c)) }
@Test func 没有规则() { /* 主词库头部没有 encoder → throws .noRules */ }
```

- [ ] **Step 2: 跑 `swift test --filter WubiEncoderTests`**，Expected：编译失败。
- [ ] **Step 3: 实现**（单字索引：主词库词条里只有一个字的，按字收集编码，去掉 `exclude_patterns` 匹配的，留最长的那些；保持出现顺序）。
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(wubi): 按词库里的组词规则算五笔编码`

---

### Task 3: 编码索引和权重 `WubiCodeIndex`

**Files:**
- Create: `Sources/RimeKit/WubiDict/WubiCodeIndex.swift`、`Sources/RimeKit/WubiDict/WubiDictTarget.swift`
- Test: `Tests/RimeKitTests/WubiCodeIndexTests.swift`（单元）、`Tests/RimeKitTests/WubiOrderCompileTests.swift`（`@Suite(.enabled(if: RimeTools.installed))`）

**Interfaces:**
- Consumes: `DictFile`、`WubiFixtures`、`PreviewSession`、`PreviewFixtures.helper`、`RimeTools`
- Produces（`public`）：
  - `struct WubiDictTarget: Sendable, Equatable { var packageID: String; var mainDict: String; var userDict: String; var schemaPrefix: String; static let jidian = WubiDictTarget(packageID: "wubi86-jidian", mainDict: "wubi86_jidian.dict.yaml", userDict: "wubi86_jidian_user.dict.yaml", schemaPrefix: "wubi86_jidian") }`
  - `struct IndexedWord: Sendable, Equatable { var text: String; var weight: Int?; var isPersonal: Bool }`
  - `struct WubiCodeIndex: Sendable { init(main: DictFile, imports: [(name: String, file: DictFile)]); func words(for code: String) -> [IndexedWord] /* 按细节 4 排好 */; func contains(text: String, code: String) -> (inPersonal: Bool, inOthers: Bool) }`
  - `enum WeightChoice: Equatable, Sendable { case weight(Int), noWeight, noRoom }`；`func weight(forPosition n: Int, code: String, excluding: DictEntry? = nil) -> WeightChoice`（n 从 0 起，n ≥ 列表长度 = 最后；`excluding` 用于改已有个人词的位置时先把它自己去掉）
  - `static func load(from package: CachedPackage, personalUserDict: URL?, target: WubiDictTarget) throws -> WubiCodeIndex`：读主词库，按 `import_tables` 递归读导入表（个人词库用 `personalUserDict`，有的话；其他用包里的文件；包里没有的导入表跳过）

- [ ] **Step 1: 写失败的单元测试**：

```swift
@Test func 按权重排() throws { /* 主词库 wqiy: 你 20、仰泳 10；个人词库 wqiy: 甲 100、乙 15、丙（无权重）→ 甲 你 乙 仰泳 丙 */ }
@Test func 放第一个前面() { #expect(idx.weight(forPosition: 0, code: "wqiy") == .weight(30)) }   // 你 20 + 10
@Test func 放中间() { /* 你 20、仰泳 10 之间 → .weight(15) */ }
@Test func 放最后() { #expect(idx.weight(forPosition: 99, code: "wqiy") == .noWeight) }
@Test func 没有空档() { /* 20、19 之间 → .noRoom */ }
@Test func 编码下还没有词() { #expect(idx.weight(forPosition: 0, code: "qqqq") == .noWeight) }
@Test func 全是不带权重的词() { /* 放第一个前面 → .weight(10)（0 + 10）；放它们中间 → .noRoom */ }
@Test func 改位置时去掉自己() { /* excluding 自己以后再算 */ }
@Test func 已经有了() { /* contains(text:code:) 分别认出个人词库里和主词库里的 */ }
@Test func 导入表递归和缺失() { /* 主词库 import_tables 里列了包里没有的表 → 跳过不报错 */ }
```

- [ ] **Step 2: 写失败的集成测试** `WubiOrderCompileTests`：用 `WubiFixtures.compiled` 把一份带权重的个人词库编译出来，用真的辅助程序打 `wqiy`，断言 librime 的顺序和 `WubiCodeIndex.words(for:)` 完全一致；另造权重相同的两组（主词库和个人词库各一个同权重词、同一文件里两个同权重词），断言顺序和细节 4 一致。**和细节 4 不一致时按实测改排序规则，并把结论写进 `docs/verified-facts.md`（新的 8.2 节「五笔组词和权重」，连同设计第 2 节的实测）。**
- [ ] **Step 3: 跑 `swift test --filter 'WubiCodeIndex|WubiOrderCompile'`**，Expected：编译失败。
- [ ] **Step 4: 实现。**
- [ ] **Step 5: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 6: 提交** `feat(wubi): 编码索引，按位置算权重`

---

### Task 4: 个人词库的存储 `WubiUserDict`

**Files:**
- Create: `Sources/RimeKit/WubiDict/WubiUserDict.swift`
- Modify: `Sources/RimeKit/Deploy/Ledger.swift`（`public mutating func acknowledge(path: String, sha256: String)`：只改已有条目的哈希，来源不变）
- Test: `Tests/RimeKitTests/WubiUserDictTests.swift`

**Interfaces:**
- Consumes: `DictFile`、`WubiDictTarget`、`AppPaths`、`RimeLocations`、`Ledger`、`ApplyLock`、`Hashing`、`CachedPackage`
- Produces（`public`）：
  - `struct WubiUserDict: Sendable { init(paths: AppPaths, locations: RimeLocations, target: WubiDictTarget = .jidian) }`
  - `func load(package: CachedPackage) throws -> DictFile`：有 `personal/dicts/<userDict>` 就读它；没有时按设计 4.4 定起点（Rime 目录里的和包里的一样或不存在 → 包里的；不一样 → Rime 目录里的），**只读不写**
  - `func save(_ file: DictFile) throws`：写 `personal/dicts/<userDict>`（先写临时文件再替换）
  - `func needsApply() -> Bool`（细节 2）
  - `func externalChange() -> Bool`：账本里有这个路径、Rime 目录里的文件哈希和账本不一样
  - `func mergeExternal(into file: DictFile) throws -> (merged: DictFile, added: Int)`：Rime 目录里那份有、`file` 里没有的词条（同 text 同 code 算同一条，code 为空时只比 text）加在末尾
  - `func acknowledgeExternal() throws`：拿 `ApplyLock`，把账本这个路径的哈希改成 Rime 目录里那份当前的哈希并保存（细节 3）

- [ ] **Step 1: 写失败的测试**（临时目录，`RimeLocations.rimeDirectory` 指向假的 Rime 目录，`WubiFixtures.makePackage`）：
  - `起点用包里的`：personal 没有、Rime 目录里的和包里一样 → load 的内容等于包里的；`personal/` 里没有生成文件
  - `起点用Rime目录里手改过的`：Rime 目录里那份多了两行 → load 出来有这两行
  - `保存后需要应用`：账本记的是包里文件的哈希；save 一个加了词的版本 → `needsApply() == true`；把账本哈希改成 personal 文件的哈希 → false
  - `外部改动和合并`（Review Focus 5）：personal 里加了「甲乙丙」；Rime 目录里那份在应用外加了「丁戊己」且账本哈希是旧的 → `externalChange() == true`；`mergeExternal` 后两个词都在、`added == 1`、原有行和注释不变；`acknowledgeExternal()` 后 `externalChange() == false`，且 `Ledger.externalChanges(in:)` 不再报这个路径
  - `合并时同词同码不重复`、`外面删掉的词不跟着删`
  - `Ledger.acknowledge 只改哈希`
- [ ] **Step 2: 跑 `swift test --filter WubiUserDictTests`**，Expected：编译失败。
- [ ] **Step 3: 实现。**
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(wubi): 个人词库的存储，收回外面的修改`

---

### Task 5: 批量导入 `WubiImport`

**Files:**
- Create: `Sources/RimeKit/WubiDict/WubiImport.swift`
- Test: `Tests/RimeKitTests/WubiImportTests.swift`

**Interfaces:**
- Consumes: `WubiEncoder`、`WubiCodeIndex`、`DictEntry`
- Produces（`public`）：
  - `enum ImportStatus: Equatable, Sendable { case ok, choose /* 有多个可能的编码 */, needsCode /* 有字算不出或编码不合法 */, alreadyPersonal, alreadyInDict, duplicateInBatch }`
  - `struct ImportRow: Equatable, Sendable, Identifiable { var id: Int /* 行号 */; var text: String; var code: String; var choices: [String]; var weight: Int?; var status: ImportStatus; var selected: Bool }`
  - `enum WubiImport { static func parse(_ text: String, encoder: WubiEncoder, index: WubiCodeIndex) -> [ImportRow]; static func entries(from rows: [ImportRow]) -> [DictEntry] /* 只取 selected 且编码合法的 */ }`
  - 默认 `selected`：`ok`、`choose` 为真，其余为假（设计 4.3）。

- [ ] **Step 1: 写失败的测试**：
  - 三种格式各一行：`张三丰` → ok/xddh/无权重；`张三丰 xddh` → 用给的编码；`李四\tsbl\t20` → 权重 20
  - 词含空格：`New York\tnyyk` → text 是 `New York`、code `nyyk`；行里没有 Tab 时按空格拆，第一段是词、第二段是编码、第三段是权重，多出来的段 → `needsCode`（所以 `New York nyyk` 得到词 `New`、编码 `York` 不合法 → `needsCode`）
  - 编码不合法（`张三 abcde`）→ `needsCode`、不选
  - 算不出（`张😀`）→ `needsCode`、code 为空
  - 多个可能编码 → `choose`、code 是第一个、choices 全部
  - 已经加过 / 词库里已经有 / 这次导入里重复（只留第一行，后面的标 `duplicateInBatch`）
  - Review Focus 3：开头 BOM、`\r\n` 换行、行尾空白、全角空格（`U+3000`）当分隔符、空行和 `#` 行跳过、`---`…`...` 头部跳过（Rime 词库原文能导入）
  - `entries(from:)` 只取选中的且编码合法的行，权重带上
- [ ] **Step 2: 跑 `swift test --filter WubiImportTests`**，Expected：编译失败。
- [ ] **Step 3: 实现。**
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(wubi): 批量导入的解析`

---

### Task 6: 检查能不能打出来 `WubiCheck`

**Files:**
- Modify: `Sources/RimeKit/Preview/PreviewProbe.swift`（`PreviewMatch` 加 `public var overall: Int` 和对应的 `init` 参数，现有调用和测试一起改）
- Create: `Sources/RimeKit/WubiDict/WubiCheck.swift`
- Test: `Tests/RimeKitTests/PreviewProbeTests.swift`（补 overall 断言）、`Tests/RimeKitTests/WubiCheckTests.swift`

**Interfaces:**
- Consumes: `PreviewEngine`、`PreviewProbe`、`WubiCodeIndex`、`DictEntry`
- Produces（`public`）：
  - `enum CheckResult: Equatable, Sendable { case asExpected(page: Int, index: Int), elsewhere(page: Int, index: Int), missing }`（page、index 从 0 起，界面显示时加 1）
  - `enum WubiCheck { static func run(_ entries: [DictEntry], index: WubiCodeIndex, engine: any PreviewEngine, userDir: URL, schema: String) async throws -> [CheckResult] }`：`open` 一次，然后逐个 `PreviewProbe.find(text, code:, maxPages: 5)`；期望位置 = `index.words(for: code)` 里这个词的序号；`overall` 相等就是 `asExpected`
  - `static func checkSchema(in settings: Settings, target: WubiDictTarget) -> String?`：第一个以 `target.schemaPrefix` 开头的方案

- [ ] **Step 1: 写失败的测试**：`PreviewProbeTests` 里每个找到的情况断言 `overall`（第 3 页第 2 个、每页 5 个 → overall 11）；`WubiCheckTests` 用假引擎测三种结果、`checkSchema` 选第一个极点方案（`["rime_ice", "wubi86_jidian_pinyin", "wubi86_jidian"]` → `wubi86_jidian_pinyin`；没有 → nil）；一条宿主机集成测试（`WubiFixtures.compiled` + 真的辅助程序）：加了权重 15 的词排在你 20 和仰泳 10 之间 → `asExpected(page: 0, index: 1)`。
- [ ] **Step 2: 跑 `swift test --filter 'PreviewProbe|WubiCheck'`**，Expected：编译失败。
- [ ] **Step 3: 实现。**
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(wubi): 检查加的词能不能打出来`

---

### Task 7: `rimectl wubi`

**Files:**
- Create: `Sources/rimectl/Wubi.swift`
- Modify: `Sources/rimectl/Rimectl.swift`（usage 加设计 4.7 的六行；`--position` 参数；命令 `wubi`）
- Test: `Tests/RimeKitTests/RimectlWubiTests.swift`

**Interfaces:**
- Consumes: 任务 1–6 的全部；`PackageStore.latestCached(_:)`、`prepareInput(cacheOnly: true, …)`、`PreviewWorkspace`、`PreviewSession`
- Produces：输出格式——
  - `encode`：每个词一行 `词\t编码1 编码2…`，算不出时 `词\t算不出：<字>`
  - `list`：每行 `词\t编码\t权重或 -`，最后一行 `共 N 个`
  - `add`：成功打印 `已加入：词 编码（排第 n 个）`；已经有 → 退出码 1；`--position` 从 1 起，放不进去 → 退出码 1 并说「这个位置放不进去」
  - `remove`：删掉的条数；没找到 → 退出码 1
  - `import`：`加入 N 个`，没加的逐行 `第 n 行：<原因>`
  - `check`：每个词一行 `词\t编码\t第 p 页第 i 个` / `位置和选的不一样：…` / `打不出来`；有打不出来的 → 退出码 1
  - 没启用极点 / 没有缓存包 → 设计第 5 节的原话，退出码 1

- [ ] **Step 1: 写失败的测试**：按上面每种输出各一条（`--data-dir` 临时目录，缓存放 `WubiFixtures.makePackage`，设置启用 `wubi86_jidian`；`check` 那条用宿主机鼠须管，`@Suite(.enabled(if: RimeTools.installed))`）。
- [ ] **Step 2: 跑 `swift test --filter RimectlWubiTests`**，Expected：FAIL。
- [ ] **Step 3: 实现。** `add`/`import`/`remove` 只写 `personal/`，不自动应用（和应用一致）；成功时提示「运行 rimectl apply 让它生效」。
- [ ] **Step 4: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 5: 提交** `feat(rimectl): wubi 命令`

---

### Task 8: AppCore：`WubiDictModel`

**Files:**
- Create: `Sources/AppCore/WubiDictModel.swift`
- Modify: `Sources/AppCore/MainModel.swift`（`Page` 加 `.wubiDict`（细节 8）；`public let wubiDict: WubiDictModel`；`hasPendingChanges` 加上 `wubiDict.needsApply`）、`Sources/AppCore/MainModel+Actions.swift`（应用成功后 `wubiDict.refresh()`）
- Test: `Tests/RimeKitTests/WubiDictModelTests.swift`

**Interfaces:**
- Consumes: 任务 1–6；`AppEnvironment`（`paths`、`locations`、`cachedPackage`、`catalog`、`previewEngine`、`compiler`、`textReplacements`）
- Produces（`@MainActor @Observable public final class WubiDictModel`）：
  - `enum Availability: Equatable { case ready, notEnabled, notDownloaded, badDict, unreadable(String) }`（文字见 Global Constraints；`unreadable` 是个人词库文件读不了，带原因，不写任何东西——设计第 5 节）
  - 状态：`availability`、`entries: [DictEntry]`、`searchText`、`externallyChanged: Bool`、`needsApply: Bool`、`checkResults: [Int: CheckResult]`（按 `entries` 序号）、`isChecking: Bool`、`message: String?`
  - 「加一个词」草稿：`draftText`（改了就重算）、`draftEncoding: WubiEncoding?`、`draftCode`、`draftCodeChoices: [String]`、`existing: [IndexedWord]`（这个编码现在出什么）、`draftPosition: Int`（默认最后）、`draftProblem: String?`（「已经加过了」「词库里已经有了」「这个位置放不进去」、编码不合法）、`canAdd: Bool`
  - 方法：`func load(settings: Settings) async`、`func add() async`、`func update(at: Int, code: String, position: Int) async`、`func remove(at: Int) async`、`func importRows(_ text: String) async -> [ImportRow]`、`func confirmImport(_ rows: [ImportRow]) async`、`func mergeExternal() async`、`func check(draft: Settings) async`、`func refresh()`
  - 解析大词库放后台（`Task.detached`），页面不卡；同一次 `load` 里缓存 `WubiEncoder` 和 `WubiCodeIndex`，编辑后重建索引。
  - `check` 用「应用后的样子」：输入的拼法和 `PreviewModel` 的 `pendingInput` 一样（缓存包、文本替换），`PreviewWorkspace.preparePending` → `env.previewEngine()` → `WubiCheck.run(…, schema: WubiCheck.checkSchema(...))` → 关引擎、删副本。

- [ ] **Step 1: 写失败的测试**（`TransferFixtures.Machine.environment(…)` 换成能放 `WubiFixtures` 包的版本；假引擎）：
  - 四种 `availability`
  - 输入「张三丰」→ `draftCode == "xddh"`、`existing` 是这个编码现在的词；改成「张😀」→ `draftProblem` 说明哪个字算不出、`canAdd == false`，手填合法编码后 `canAdd == true`
  - `add()` 后 `entries` 多一条、文件写进 `personal/`、`needsApply == true`、`MainModel.hasPendingChanges == true`；选了第一个位置时写进去的权重是索引给的
  - 放不进去 → `draftProblem == "这个位置放不进去"`、`canAdd == false`
  - 已经加过 / 词库里已经有
  - `update`、`remove` 只改对应的行
  - 外部改动：`externallyChanged == true`，`mergeExternal()` 后两边的词都在、`externallyChanged == false`
  - `importRows` + `confirmImport` 加进选中的行
  - `check`：结果按序号放进 `checkResults`；检查期间 `isChecking`；结束后副本删掉、引擎关掉；编译失败时 `message` 是翻译过的错误（`PreviewError.compileFailed` 的行）
  - `confirmImport` 后 `message` 是「加入 N 个，可以点「检查能不能打出来」」（设计 4.6）
  - 个人词库文件头部坏了 → `availability == .unreadable(…)`，不写文件
  - 应用改动成功后 `needsApply == false`
- [ ] **Step 2: 跑 `swift test --filter WubiDictModelTests`**，Expected：编译失败。
- [ ] **Step 3: 实现**（`MainView` 的 `switch` 先放占位 `case .wubiDict: Text("五笔词库")`，保持能编译）。
- [ ] **Step 4: 跑 `swift test`、`swift build`**，Expected：全部 PASS、没有新警告。
- [ ] **Step 5: 提交** `feat(app): 五笔词库页的逻辑 WubiDictModel`

---

### Task 9: AppUI：「五笔词库」页

**Files:**
- Create: `Sources/AppUI/WubiDictPage.swift`、`Sources/AppUI/WubiImportSheet.swift`
- Modify: `Sources/AppUI/MainView.swift`（换掉占位；`ApplyBar` 在只有词库改动时显示「五笔词库有改动还没应用」，「撤销」只在 `isDirty` 时显示——现在就是这样，确认文字）

**Interfaces:**
- Consumes: 任务 8 的 `WubiDictModel` 全部接口；`MainModel.draft`、`page`

- [ ] **Step 1: 写页面**（设计 4.1）：
  - `availability != .ready` 时只显示对应的一句话（`notEnabled` 带去「方案」页的按钮）。
  - `externallyChanged` 时顶部橙色提示「鼠须管目录里的五笔个人词库在应用外被改过」+ 按钮「把外面加的词收进来」。
  - 「加一个词」：词输入框；编码（多个可能时用下拉框选，`needsCode` 时是输入框）；「这个编码现在出什么」列出 `existing`（个人词标「我的」），用一个选择器选「排在第几」（选项是每个已有词前面的位置和「最后」）；`draftProblem` 用红字；「加入」按钮（`canAdd`）。
  - 列表：搜索框；每行 词 / 编码 / 位置 / 检查结果（`第 1 页第 2 个`、`位置和选的不一样：第 1 页第 3 个`、`打不出来`，页和个从 1 数）；行的右键菜单「改编码和位置……」「删除」。
  - 按钮「从文本导入……」打开 `WubiImportSheet`；「检查能不能打出来」（`isChecking` 时显示进度）。
  - `WubiImportSheet`：大文本框可粘贴，「选文件……」读 UTF-8 文本；「预览」后显示 `ImportRow` 表：勾选框、词、编码（可改；`choose` 用下拉框）、状态说明（设计 4.3 的表）；底部「加入 N 个」。
  - 进入页面 `.task { await model.wubiDict.load(settings: model.draft) }`。
- [ ] **Step 2: `swift build`**，Expected：通过、没有新警告。
- [ ] **Step 3: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 4: 提交** `feat(app): 侧边栏加「五笔词库」页`

---

### Task 10: 联网测试、测试机检查和文档

**Files:**
- Create: `Tests/RimeKitTests/OnlineWubiDictTests.swift`、`docs/wubi-user-dict-vm-log.md`
- Modify: `docs/verified-facts.md`（8.2，如果任务 3 还没建）、`docs/superpowers/plans/2026-10-15-v2-roadmap.md`、`docs/superpowers/specs/2026-10-16-wubi-user-dict-design.md`（状态：已实现）、`CLAUDE.md`、`docs/backlog.md`（留下的小问题）

- [ ] **Step 1: 写联网测试**（细节 9）：`RIMEKIT_ONLINE=1` 才跑；下载极点五笔包到临时数据目录；`WubiEncoder` 算「张三丰」「宋氏」「中华人民共和国」；用 `ConfigGenerator` 生成、编译，把这三个词不带编码写进个人词库，再用辅助程序打 `WubiEncoder` 算出的编码，断言能打出来（Rime 自己算的和我们算的一致）。
- [ ] **Step 2: 跑 `RIMEKIT_ONLINE=1 swift test --filter OnlineWubiDictTests`**，Expected：PASS。
- [ ] **Step 3: 测试机**：先记下测试机真实 `~/Library/Rime` 的文件列表（`stat`），装 debug 包（共享文件夹看不到新文件时用 `tar … | vm.sh ssh …` 传）。测试机 `squirrel-dev` 现在启用的是雾凇和小鹤，要先在「方案」页启用极点五笔并应用。请用户试：加一个词（看编码、选位置）、批量导入一段文本（含算不出、重复、Rime 词库原文）、改和删、检查能不能打出来、应用改动后切到鼠须管真的打一次、在应用外手改 Rime 目录里的个人词库再回来收进来。结束后对比 `~/Library/Rime`：只有应用改动写进去的文件变了。
- [ ] **Step 4: 写文档**：测试机记录；verified-facts；路线图子项目 3 改「已完成」（注明只做了五笔）；设计状态；CLAUDE.md 简介和「先读这些」；backlog 记下留下的问题（拼音词库、手动短语、上游更新后位置会变）。
- [ ] **Step 5: 跑 `swift test`**，Expected：全部 PASS。
- [ ] **Step 6: 提交** `docs: 五笔个人词库编辑器的测试机记录，更新说明和路线图`，然后问用户能不能推送。

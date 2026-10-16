import Foundation
import Synchronization
import Testing
@testable import AppCore
@testable import RimeKit

/// 假的试打引擎：按编码返回排好的候选页，记下打开、关闭；打开时可以看一眼模型的状态
private final class PageEngine: PreviewEngine {
    private struct Inner {
        var opened: [String] = []
        var closed = false
        var code = ""
        var page = 0
    }
    private let inner = Mutex(Inner())
    private let pages: [String: [[String]]]
    private let onOpen: @Sendable () async -> Void

    init(pages: [String: [[String]]], onOpen: @escaping @Sendable () async -> Void) {
        self.pages = pages
        self.onOpen = onOpen
    }

    var opened: [String] { inner.withLock { $0.opened } }
    var closed: Bool { inner.withLock { $0.closed } }

    private func state(_ i: Inner) -> PreviewState {
        let all = pages[i.code] ?? []
        guard i.page < all.count else { return PreviewState() }
        return PreviewState(
            preedit: i.code, candidates: all[i.page].map { PreviewCandidate(text: $0, comment: "") },
            pageNo: i.page, isLastPage: i.page == all.count - 1)
    }

    func open(userDir: URL, schema: String) async throws -> PreviewOpened {
        await onOpen()
        inner.withLock { $0.opened.append(schema) }
        return PreviewOpened(librimeVersion: "fake", state: .empty)
    }
    func input(_ text: String) async throws -> PreviewState {
        inner.withLock { $0.code = text; $0.page = 0; return state($0) }
    }
    func key(_ key: PreviewKey) async throws -> PreviewState {
        inner.withLock { if key == .pageDown { $0.page += 1 }; return state($0) }
    }
    func select(_ index: Int) async throws -> PreviewState { inner.withLock { state($0) } }
    func clear() async throws -> PreviewState { inner.withLock { $0.code = ""; $0.page = 0; return .empty } }
    func close() async { inner.withLock { $0.closed = true } }
}

/// 记下建过的引擎；打开时看到的 isChecking
private final class PageEngines: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [PageEngine] = []
    private var seen: [Bool] = []
    var pages: [String: [[String]]] = [:]
    /// 打开时读这个（测试里指向模型）
    var probe: (@MainActor @Sendable () -> Bool)?

    var all: [PageEngine] { lock.withLock { made } }
    var checkingSeen: [Bool] { lock.withLock { seen } }

    func make() -> any PreviewEngine {
        let probe = self.probe
        let engine = PageEngine(pages: pages) { [weak self] in
            guard let probe else { return }
            let v = await MainActor.run { probe() }
            self?.lock.withLock { self?.seen.append(v) }
        }
        lock.withLock { made.append(engine) }
        return engine
    }
}

@MainActor @Suite struct WubiDictModelTests {
    typealias T = TransferFixtures

    struct Setup {
        let machine: T.Machine
        var env: AppEnvironment
        fileprivate let engines: PageEngines

        var paths: AppPaths { machine.paths }
        var personalFile: URL { paths.personalDicts.appending(path: WubiFixtures.userName) }
        var rimeFile: URL { machine.locations.rimeDirectory.appending(path: WubiFixtures.userName) }
        var package: CachedPackage { machine.packages[WubiFixtures.packageID]! }

        func remove() { machine.dir.remove() }

        func writePersonal(_ text: String) throws {
            try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: personalFile)
        }

        func writeRime(_ text: String) throws {
            try Data(text.utf8).write(to: rimeFile)
        }

        func personalText() -> String { (try? String(contentsOf: personalFile, encoding: .utf8)) ?? "" }
        func rimeText() -> String { (try? String(contentsOf: rimeFile, encoding: .utf8)) ?? "" }

        /// 账本里个人词库这一条记成 text 的哈希
        func record(_ text: String) throws {
            var ledger = try Ledger.load(paths)
            ledger.entries[WubiFixtures.userName] = LedgerEntry(sha256: Hashing.sha256(of: Data(text.utf8)), origin: "personal")
            try ledger.save(paths)
        }

        func stagingIsEmpty() -> Bool {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.staging.path)) ?? []
            return !names.contains { $0.hasPrefix("preview-") }
        }

        @MainActor func model() -> WubiDictModel { WubiDictModel(env: env) }
    }

    static let settings = Settings(schemas: ["wubi86_jidian"])

    /// 一台假 Mac：缓存里只有迷你极点五笔包，设置里启用了极点五笔；编译器会写出 build/，引擎是假的
    func setup() throws -> Setup {
        let dir = try TempDir()
        let paths = Fixtures.paths(dir)
        let package = try WubiFixtures.makePackage(in: paths.packages)
        let locations = try DeployFixtures.locations(dir)
        try FileManager.default.createDirectory(at: locations.rimeDirectory, withIntermediateDirectories: true)
        try SettingsStore(paths: paths).save(Self.settings)
        let machine = T.Machine(dir: dir, paths: paths, locations: locations,
                                squirrel: FakeSquirrel(locations: locations, running: true),
                                tool: FakeUserDBTool(), catalog: try WubiFixtures.catalog(),
                                packages: [WubiFixtures.packageID: package])
        let engines = PageEngines()
        var env = machine.environment()
        env.compiler = WritingCompiler(schemas: [(id: "wubi86_jidian", name: "极点五笔")])
        env.previewEngine = { engines.make() }
        return Setup(machine: machine, env: env, engines: engines)
    }

    func loaded(_ s: Setup) async -> WubiDictModel {
        let model = s.model()
        await model.load(settings: Self.settings)
        return model
    }

    // MARK: 能不能用

    @Test func 四种状态() async throws {
        let s = try setup(); defer { s.remove() }
        let model = s.model()

        await model.load(settings: Settings(schemas: ["wb_py"]))
        #expect(model.availability == .notEnabled)
        #expect(model.availability.message == "先在「方案」页启用极点五笔")

        var noCache = s
        noCache.env.cachedPackage = { _ in nil }
        let missing = noCache.model()
        await missing.load(settings: Self.settings)
        #expect(missing.availability == .notDownloaded)
        #expect(missing.availability.message == "还没下载极点五笔，先应用一次改动")

        await model.load(settings: Self.settings)
        #expect(model.availability == .ready)
        #expect(model.availability.message == nil)
        #expect(model.entries.map(\.text) == ["分组词条"])

        // 主词库没有组词规则：自动编码用不了，仍可手填编码加词
        let main = s.package.filesDirectory.appending(path: WubiFixtures.mainName)
        try Data(WubiFixtures.mainDict.replacingOccurrences(of: "encoder:", with: "encoder_off:").utf8).write(to: main)
        let bad = s.model()
        await bad.load(settings: Self.settings)
        #expect(bad.availability == .badDict)
        #expect(bad.availability.message == "认不出这个版本的极点五笔词库，自动编码用不了")
        bad.draftText = "张三丰"
        #expect(bad.draftCode == "")
        #expect(bad.draftProblem == "认不出这个版本的极点五笔词库，自动编码用不了")
        bad.draftCode = "xddh"
        #expect(bad.canAdd)
        await bad.add()
        #expect(bad.entries.last == DictEntry(text: "张三丰", code: "xddh"))
    }

    @Test func 个人词库读不了时不写任何东西() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal("没有头部\t的文件\n")
        let model = await loaded(s)
        guard case .unreadable(let reason) = model.availability else {
            Issue.record("应该是 unreadable，实际是 \(model.availability)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(model.availability.message?.contains(reason) == true)
        model.draftText = "张三丰"
        #expect(!model.canAdd)
        await model.add()
        await model.remove(at: 0)
        #expect(s.personalText() == "没有头部\t的文件\n")

        // 不是 UTF-8
        try Data([0x2D, 0x2D, 0x2D, 0x0A, 0xFF, 0xFE, 0x0A]).write(to: s.personalFile)
        await model.load(settings: Self.settings)
        guard case .unreadable = model.availability else {
            Issue.record("应该是 unreadable，实际是 \(model.availability)")
            return
        }
    }

    // MARK: 加一个词的草稿

    @Test func 草稿自动算编码_算不出时手填() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n张三风\txddh\t5\n")
        let model = await loaded(s)

        model.draftText = "张三丰"
        #expect(model.draftEncoding == .codes(["xddh"]))
        #expect(model.draftCode == "xddh")
        #expect(model.draftCodeChoices == ["xddh"])
        #expect(model.existing == [IndexedWord(text: "张三风", weight: 5, isPersonal: true)])
        #expect(model.draftPosition == 2)   // 默认最后
        #expect(model.draftProblem == nil)
        #expect(model.canAdd)

        model.draftText = "张😀"
        #expect(model.draftCode == "")
        #expect(model.draftProblem?.contains("😀") == true)
        #expect(!model.canAdd)
        model.draftCode = "zz"
        #expect(model.draftProblem == "编码只能是 a–y 的小写字母，1 到 4 个")
        #expect(!model.canAdd)
        model.draftCode = "xxxx"
        #expect(model.draftProblem == nil)
        #expect(model.canAdd)

        // 有好几个可能的编码：列出来，默认第一个
        model.draftText = "戈戈"
        #expect(model.draftCodeChoices.count == 4)
        #expect(model.draftCode == model.draftCodeChoices[0])

        model.draftText = ""
        #expect(model.draftProblem == nil)
        #expect(!model.canAdd)
    }

    @Test func 已经加过和词库里已经有() async throws {
        let s = try setup(); defer { s.remove() }
        // 没写编码的词按自动编码查重
        try s.writePersonal(WubiFixtures.userDict + "\n张三丰\n")
        let model = await loaded(s)
        model.draftText = "张三丰"
        #expect(model.draftProblem == "已经加过了")
        #expect(!model.canAdd)
        model.draftText = "仰泳"
        #expect(model.draftProblem == "词库里已经有了")
        #expect(!model.canAdd)
    }

    @Test func 放不进去() async throws {
        let s = try setup(); defer { s.remove() }
        // wqiy 下：你 20、甲乙 19、仰泳 10
        try s.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t19\n")
        let model = await loaded(s)
        model.draftText = "丙丁"
        model.draftCode = "wqiy"
        #expect(model.existing.map(\.text) == ["你", "甲乙", "仰泳"])
        model.draftPosition = 2
        #expect(model.draftProblem == "这个位置放不进去")
        #expect(!model.canAdd)
        await model.add()
        #expect(model.entries.count == 2)
        model.draftPosition = 3
        #expect(model.draftProblem == nil)
        #expect(model.canAdd)
        await model.add()
        #expect(model.entries.last == DictEntry(text: "丙丁", code: "wqiy", weight: 14))
    }

    // MARK: 加、改、删

    @Test func 加入以后写进personal_底部有改动() async throws {
        let s = try setup(); defer { s.remove() }
        let main = try MainModel(env: s.env)
        let model = main.wubiDict
        await model.load(settings: Self.settings)
        #expect(!model.needsApply)
        #expect(!main.hasPendingChanges)

        model.draftText = "张三丰"
        await model.add()
        #expect(model.entries.last == DictEntry(text: "张三丰", code: "xddh"))
        #expect(s.personalText() == WubiFixtures.userDict + "\n张三丰\txddh\n")
        #expect(model.needsApply)
        #expect(main.hasPendingChanges)
        #expect(!main.isDirty)
        #expect(model.positions[1] == 1)
        // 加完草稿清空
        #expect(model.draftText == "")
        #expect(!model.canAdd)

        // 放第一个：权重是索引给的（你 20 + 10）
        model.draftText = "甲乙"
        model.draftCode = "wqiy"
        model.draftPosition = 1
        await model.add()
        #expect(model.entries.last == DictEntry(text: "甲乙", code: "wqiy", weight: 30))
        #expect(s.personalText().hasSuffix("甲乙\twqiy\t30\n"))
        #expect(model.positions[2] == 1)
    }

    @Test func 改和删只动对应的行() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t15\n丙丁\tabcd\n")
        let model = await loaded(s)
        // 0 分组词条、1 甲乙、2 丙丁
        await model.update(at: 1, code: "wqiy", position: 1)
        #expect(s.personalText() == WubiFixtures.userDict + "\n甲乙\twqiy\t30\n丙丁\tabcd\n")
        #expect(model.positions[1] == 1)

        await model.update(at: 2, code: "abce", position: 1)
        #expect(s.personalText() == WubiFixtures.userDict + "\n甲乙\twqiy\t30\n丙丁\tabce\n")

        // 换到别的编码下排第一个：泳 100 + 10
        await model.update(at: 1, code: "iyiy", position: 1)
        #expect(s.personalText().contains("甲乙\tiyiy"))

        await model.remove(at: 2)
        #expect(s.personalText() == WubiFixtures.userDict + "\n甲乙\tiyiy\t110\n")
        #expect(model.entries.map(\.text) == ["分组词条", "甲乙"])
        #expect(model.needsApply)
    }

    @Test func 改成已有的词不写() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n仰泳\tabcd\n甲乙\twqiy\n甲乙\tabcd\n")
        let model = await loaded(s)
        let before = s.personalText()
        await model.update(at: 1, code: "wqiy", position: nil)
        #expect(model.message == "词库里已经有了")
        await model.update(at: 3, code: "wqiy", position: nil)
        #expect(model.message == "已经加过了")
        await model.update(at: 3, code: "ABC", position: nil)
        #expect(model.message == "编码只能是 a–y 的小写字母，1 到 4 个")
        #expect(s.personalText() == before)
    }

    @Test func 搜索按词或编码() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\n张三丰\n")
        let model = await loaded(s)
        #expect(model.visibleIndices == [0, 1, 2])
        model.searchText = "甲"
        #expect(model.visibleIndices == [1])
        model.searchText = "xddh"   // 没写编码的按自动编码搜
        #expect(model.visibleIndices == [2])
        #expect(model.codes == ["wxyt", "wqiy", "xddh"])
    }

    // MARK: 外面改过

    @Test func 外面改过_收进来两边的词都在() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n甲乙丙\tlnxy\n")
        try s.writeRime(WubiFixtures.userDict + "\n丁戊己\tsdnn\n")
        try s.record(WubiFixtures.userDict)
        let model = await loaded(s)
        #expect(model.externallyChanged)
        await model.mergeExternal()
        #expect(!model.externallyChanged)
        #expect(model.entries.map(\.text) == ["分组词条", "甲乙丙", "丁戊己"])
        #expect(s.personalText().contains("甲乙丙\tlnxy"))
        #expect(s.personalText().contains("丁戊己\tsdnn"))
        #expect(model.message == "收进来 1 个词")
        #expect(model.needsApply)
    }

    @Test func 外面改过_还没有personal也要写下合并的结果() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writeRime(WubiFixtures.userDict + "\n丁戊己\tsdnn\n")
        try s.record(WubiFixtures.userDict)
        let model = await loaded(s)
        #expect(model.externallyChanged)
        #expect(model.entries.map(\.text) == ["分组词条", "丁戊己"])   // 起点用 Rime 目录里那份
        await model.mergeExternal()
        #expect(!model.externallyChanged)
        #expect(s.personalText().contains("丁戊己\tsdnn"))
    }

    // MARK: 导入

    @Test func 导入选中的行() async throws {
        let s = try setup(); defer { s.remove() }
        let model = await loaded(s)
        var rows = await model.importRows("张三丰\n仰泳\n甲乙\twqiy\n丙丁\tabcd\n")
        #expect(rows.map(\.status) == [.ok, .alreadyInDict, .ok, .ok])
        rows[3].selected = false
        await model.confirmImport(rows)
        #expect(model.entries.map(\.text) == ["分组词条", "张三丰", "甲乙"])
        #expect(s.personalText().hasSuffix("\n张三丰\txddh\n甲乙\twqiy\n"))
        #expect(model.message == "加入 2 个，可以点「检查能不能打出来」")
        #expect(model.needsApply)

        // 同样的再导一次：都已经有了，不写
        let again = await model.importRows("张三丰\n")
        #expect(again.map(\.status) == [.alreadyPersonal])
        let before = s.personalText()
        await model.confirmImport([ImportRow(id: 1, text: "张三丰", code: "xddh", choices: [], weight: nil, status: .ok, selected: true)])
        #expect(s.personalText() == before)
    }

    // MARK: 检查

    @Test func 检查结果按序号放() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t15\n张三丰\n")
        s.engines.pages = ["wqiy": [["你", "甲乙", "仰泳"]], "xddh": [["别的", "张三丰"]]]
        let model = await loaded(s)
        s.engines.probe = { model.isChecking }
        await model.check(draft: Self.settings)
        #expect(model.checkResults == [
            0: .missing,                          // 分组词条 wxyt 引擎里没有
            1: .asExpected(page: 0, index: 1),
            2: .elsewhere(page: 0, index: 1),
        ])
        #expect(!model.isChecking)
        #expect(s.engines.checkingSeen == [true])
        let engine = try #require(s.engines.all.first)
        #expect(engine.opened == ["wubi86_jidian"])
        #expect(engine.closed)
        #expect(s.stagingIsEmpty())
        #expect(model.message == nil)

        // 改了词库，旧的结果不要了
        await model.remove(at: 0)
        #expect(model.checkResults.isEmpty)
    }

    @Test func 检查时编译不过() async throws {
        var s = try setup(); defer { s.remove() }
        s.env.compiler = FakeCompiler(report: CompileReport(succeeded: false, errors: [
            "E20261016 10:00:00.000000 0x1 deployment_tasks.cc:376] dictionary 'wubi86_jidian' failed to compile.",
        ]))
        try s.writePersonal(WubiFixtures.userDict + "\n甲乙\twqiy\t15\n")
        let model = await loaded(s)
        await model.check(draft: Self.settings)
        #expect(model.message?.contains("词库 wubi86_jidian 编译失败") == true)
        #expect(model.checkResults.isEmpty)
        #expect(!model.isChecking)
        #expect(s.engines.all.isEmpty)
        #expect(s.stagingIsEmpty())
    }

    // MARK: 和主窗口

    @Test func 页面在试打后面() {
        let pages = MainModel.Page.allCases
        #expect(pages[pages.firstIndex(of: .preview)! + 1] == .wubiDict)
        #expect(MainModel.Page.wubiDict.title == "五笔词库")
        #expect(MainModel.Page.wubiDict.symbol == "character.book.closed")
    }

    @Test func 应用改动以后没有词库改动了() async throws {
        let s = try setup(); defer { s.remove() }
        let main = try MainModel(env: s.env)
        let model = main.wubiDict
        await model.load(settings: main.draft)
        model.draftText = "张三丰"
        await model.add()
        #expect(main.hasPendingChanges)
        await main.apply()
        #expect(main.notice?.title == "改动已经生效")
        #expect(!model.needsApply)
        #expect(!main.hasPendingChanges)
        #expect(s.rimeText().contains("张三丰\txddh"))
    }

    @Test func 打开应用时就知道有没应用的词库改动() async throws {
        let s = try setup(); defer { s.remove() }
        try s.writePersonal(WubiFixtures.userDict + "\n张三丰\txddh\n")
        let main = try MainModel(env: s.env)
        #expect(main.wubiDict.needsApply)
        #expect(main.hasPendingChanges)
    }

    @Test func 应用时只有五笔个人词库被外面改过_先提示收进来() async throws {
        let s = try setup(); defer { s.remove() }
        let main = try MainModel(env: s.env)
        let model = main.wubiDict
        await model.load(settings: main.draft)
        model.draftText = "张三丰"
        await model.add()
        await main.apply()
        #expect(main.notice?.title == "改动已经生效")

        try s.writeRime(s.rimeText() + "丁戊己\tsdnn\n")
        model.draftText = "甲乙"
        model.draftCode = "wqiy"
        await model.add()
        await main.apply()
        #expect(main.pendingExternalChanges == nil)
        #expect(main.notice?.title == "鼠须管目录里的五笔个人词库在应用外被改过")
        #expect(main.notice?.action == .mergeWubiDict)
        #expect(main.notice?.actionTitle == "把外面加的词收进来")
        #expect(model.externallyChanged)

        await main.perform(.mergeWubiDict)
        #expect(main.notice?.title == "改动已经生效")
        let text = s.rimeText()
        #expect(text.contains("张三丰\txddh"))
        #expect(text.contains("甲乙\twqiy"))
        #expect(text.contains("丁戊己\tsdnn"))
        #expect(!model.externallyChanged)
        #expect(!model.needsApply)
    }

    @Test func 不收的话再应用一次就按原来的流程问() async throws {
        let s = try setup(); defer { s.remove() }
        let main = try MainModel(env: s.env)
        let model = main.wubiDict
        await model.load(settings: main.draft)
        model.draftText = "张三丰"
        await model.add()
        await main.apply()
        try s.writeRime(s.rimeText() + "丁戊己\tsdnn\n")
        await main.apply()
        #expect(main.notice?.action == .mergeWubiDict)
        main.notice = nil
        await main.apply()
        #expect(main.pendingExternalChanges == [.modified(WubiFixtures.userName)])
        #expect(main.pendingPersonalChanges)
        // 采用外面那份：personal 换成外面的，页面跟着重新读
        await main.resolveExternalChanges(.adoptPersonal)
        #expect(main.notice?.title == "改动已经生效")
        #expect(model.entries.map(\.text).contains("丁戊己"))
        #expect(!model.externallyChanged)
    }
}

import Foundation
import Testing
@testable import AppCore
@testable import RimeKit

/// 假的试打引擎：记下收到的调用，按设定返回状态或抛错
actor FakePreviewEngine: PreviewEngine {
    enum Call: Equatable {
        case open(URL, String), input(String), key(PreviewKey), select(Int), clear, close
    }

    private(set) var calls: [Call] = []
    var inputState = PreviewState(preedit: "ni", candidates: [PreviewCandidate(text: "你", comment: "")])
    var inputError: PreviewError?

    func setInput(_ state: PreviewState) { inputState = state }
    func failInput(_ error: PreviewError?) { inputError = error }

    func open(userDir: URL, schema: String) async throws -> PreviewOpened {
        calls.append(.open(userDir, schema))
        return PreviewOpened(librimeVersion: "1.16.1", state: .empty)
    }

    func input(_ text: String) async throws -> PreviewState {
        calls.append(.input(text))
        if let inputError { throw inputError }
        return inputState
    }

    func key(_ key: PreviewKey) async throws -> PreviewState {
        calls.append(.key(key))
        return PreviewState(preedit: "ni", pageNo: key == .pageDown ? 1 : 0)
    }

    func select(_ index: Int) async throws -> PreviewState {
        calls.append(.select(index))
        return PreviewState(committed: "你")
    }

    func clear() async throws -> PreviewState {
        calls.append(.clear)
        return .empty
    }

    func close() async { calls.append(.close) }

    var opens: [Call] { calls.filter { if case .open = $0 { true } else { false } } }
}

/// 记下建过的所有假引擎
final class FakeEngines: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [FakePreviewEngine] = []

    var all: [FakePreviewEngine] { lock.withLock { made } }

    func make() -> any PreviewEngine {
        let engine = FakePreviewEngine()
        lock.withLock { made.append(engine) }
        return engine
    }
}

/// 编译时可以卡住（等测试放行）的假编译器；编译结果和 WritingCompiler 一样
final class GatedCompiler: RimeCompiler, @unchecked Sendable {
    private let lock = NSLock()
    private let inner = WritingCompiler(schemas: [(id: "py", name: "拼音"), (id: "wb_py", name: "五笔拼音")])
    private let gate = DispatchSemaphore(value: 0)
    private var blocking = false
    private var waiting = false

    var compiled: [URL] { inner.compiled }
    var isWaiting: Bool { lock.withLock { waiting } }

    func block() { lock.withLock { blocking = true } }

    func release() {
        lock.withLock { blocking = false }
        gate.signal()
    }

    func compile(_ directory: URL) throws -> CompileReport {
        if lock.withLock({ blocking }) {
            lock.withLock { waiting = true }
            gate.wait()
            lock.withLock { waiting = false }
        }
        return try inner.compile(directory)
    }
}

@MainActor @Suite struct PreviewModelTests {
    typealias T = TransferFixtures

    struct Setup {
        let machine: T.Machine
        let engines: FakeEngines
        let compiler: GatedCompiler
        var env: AppEnvironment

        func remove() { machine.dir.remove() }

        func stagingIsEmpty() -> Bool {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: machine.paths.staging.path)) ?? []
            return !names.contains { $0.hasPrefix("preview-") }
        }

        var engine: FakePreviewEngine { engines.all[0] }
    }

    /// 一台装好、部署过（有 build/）的假 Mac，引擎是假的
    func setup() throws -> Setup {
        let m = try T.machine()
        let rime = m.locations.rimeDirectory
        let build = rime.appending(path: "build", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try Data("schema_list:\n  - schema: wb_py\n  - schema: py\n".utf8).write(to: build.appending(path: "default.yaml"))
        try Data("schema:\n  schema_id: wb_py\n  name: 五笔拼音\n".utf8).write(to: build.appending(path: "wb_py.schema.yaml"))
        try Data("schema:\n  schema_id: py\n  name: 拼音\n".utf8).write(to: build.appending(path: "py.schema.yaml"))
        let engines = FakeEngines()
        let compiler = GatedCompiler()
        var env = m.environment()
        env.compiler = compiler
        env.previewEngine = { engines.make() }
        return Setup(machine: m, engines: engines, compiler: compiler, env: env)
    }

    var draft: Settings { T.settings }

    func exists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: 按键对照（设计 4.1）

    @Test func 按键对照() {
        #expect(PreviewKeyPress.translate(characters: "a", special: nil, commandLike: false) == .text("a"))
        #expect(PreviewKeyPress.translate(characters: "A", special: nil, commandLike: false) == .text("A"))
        #expect(PreviewKeyPress.translate(characters: " ", special: nil, commandLike: false) == .text(" "))
        #expect(PreviewKeyPress.translate(characters: "~", special: nil, commandLike: false) == .text("~"))
        #expect(PreviewKeyPress.translate(characters: "", special: .pageDown, commandLike: false) == .special(.pageDown))
        #expect(PreviewKeyPress.translate(characters: "\u{F72D}", special: .pageDown, commandLike: false) == .special(.pageDown))
        #expect(PreviewKeyPress.translate(characters: "w", special: nil, commandLike: true) == .ignored)
        #expect(PreviewKeyPress.translate(characters: "", special: .return, commandLike: true) == .ignored)
        // 非 ASCII（别的中文输入法、Option 组合出来的符号、emoji）一律忽略（Review Focus 3）
        #expect(PreviewKeyPress.translate(characters: "你", special: nil, commandLike: false) == .ignored)
        #expect(PreviewKeyPress.translate(characters: "é", special: nil, commandLike: false) == .ignored)
        #expect(PreviewKeyPress.translate(characters: "😀", special: nil, commandLike: false) == .ignored)
        #expect(PreviewKeyPress.translate(characters: "a你", special: nil, commandLike: false) == .ignored)
        #expect(PreviewKeyPress.translate(characters: "\t", special: nil, commandLike: false) == .ignored)
        #expect(PreviewKeyPress.translate(characters: "", special: nil, commandLike: false) == .ignored)
    }

    // MARK: 流程

    @Test func 进入页面() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        #expect(model.phase == .ready)
        #expect(model.source == .current)
        #expect(model.schemas.map(\.id) == ["wb_py", "py"])
        #expect(model.schema == "wb_py")
        #expect(model.librimeVersion == "1.16.1")
        let opens = await s.engine.opens
        guard case let .open(dir, schema)? = opens.first else { Issue.record("没有 open"); return }
        #expect(opens.count == 1 && schema == "wb_py")
        #expect(dir.path.hasPrefix(s.machine.paths.staging.path))
        #expect(exists(dir.appending(path: "build/py.schema.yaml")))
        await model.leave()
    }

    @Test func 打字和上屏累加() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        await model.press(.text("ni"))
        #expect(model.state.preedit == "ni")
        #expect(model.committedText == "")
        await s.engine.setInput(PreviewState(committed: "你"))
        await model.press(.text("a"))
        await model.press(.text("b"))
        #expect(model.committedText == "你你")
        await model.press(.ignored)
        await model.press(.special(.backspace))
        await model.clearInput()
        let calls = await s.engine.calls
        #expect(Array(calls.dropFirst()) == [.input("ni"), .input("a"), .input("b"), .key(.backspace), .clear])
        model.clearCommitted()
        #expect(model.committedText == "")
        await model.leave()
    }

    @Test func 点候选和翻页() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        await model.choose(2)
        #expect(model.committedText == "你")
        await model.pageDown()
        #expect(model.state.pageNo == 1)
        await model.pageUp()
        let calls = await s.engine.calls
        #expect(Array(calls.dropFirst()) == [.select(2), .key(.pageDown), .key(.pageUp)])
        await model.leave()
    }

    @Test func 换方案() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        await model.selectSchema("py")
        #expect(model.schema == "py" && model.phase == .ready)
        let opens = await s.engine.opens
        guard opens.count == 2, case let .open(first, _) = opens[0], case let .open(second, schema) = opens[1] else {
            Issue.record("open 次数不对：\(opens)"); return
        }
        #expect(first == second && schema == "py")
        #expect(s.engines.all.count == 1)
        await model.leave()
    }

    @Test func 换来源() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: true)
        await model.selectSchema("py")
        let opens = await s.engine.opens
        guard case let .open(oldDir, _)? = opens.first else { Issue.record("没有 open"); return }
        await model.switchSource(.pending, draft: draft, hasPending: true)
        #expect(model.phase == .ready)
        #expect(model.source == .pending)
        #expect(s.compiler.compiled.count == 1)
        let after = await s.engine.opens
        guard after.count == 3, case let .open(newDir, schema) = after[2] else { Issue.record("open 次数不对：\(after)"); return }
        #expect(newDir != oldDir && newDir == s.compiler.compiled.first)
        #expect(schema == "py")   // 新副本里也有，就留着用户选的方案
        #expect(!exists(oldDir))
        #expect(exists(newDir))
        #expect(s.engines.all.count == 1)
        await model.leave()
        #expect(s.stagingIsEmpty())
    }

    @Test func 应用后的样子缺方案包() async throws {
        var s = try setup(); defer { s.remove() }
        s.env.cachedPackage = { _ in nil }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: true)
        await model.switchSource(.pending, draft: draft, hasPending: true)
        guard case let .failed(problem) = model.phase else { Issue.record("应该失败：\(model.phase)"); return }
        #expect(problem.title.hasPrefix("这些方案还没下载过："))
        #expect(problem.title.contains("测试拼音") && problem.title.contains("测试五笔"))
        #expect(problem.title.hasSuffix("，应用改动时会下载"))
        #expect(s.compiler.compiled.isEmpty)
        // 旧副本和来源对不上了：先关掉还在用它的辅助程序，再删掉
        #expect(await s.engine.calls.last == .close)
        #expect(s.stagingIsEmpty())
        await model.leave()
        #expect(s.stagingIsEmpty())
    }

    @Test func 应用后的样子读不了文本替换() async throws {
        var s = try setup(); defer { s.remove() }
        s.env.textReplacements = { throw TextReplacementError.cannotOpen("没有权限") }
        var settings = draft
        settings.textReplacement.sync = true
        let model = PreviewModel(env: s.env)
        await model.enter(draft: settings, hasPending: true)
        #expect(model.notes.isEmpty)
        await model.switchSource(.pending, draft: settings, hasPending: true)
        #expect(model.phase == .ready)
        #expect(model.notes.count == 1)
        #expect(model.notes.first?.contains("文本替换") == true)
        await model.leave()
    }

    @Test func 离开页面() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        let opens = await s.engine.opens
        guard case let .open(dir, _)? = opens.first else { Issue.record("没有 open"); return }
        await model.leave()
        #expect(await s.engine.calls.last == .close)
        #expect(!exists(dir))
        #expect(s.stagingIsEmpty())
        #expect(model.phase == .idle)
        #expect(model.schemas.isEmpty && model.schema == nil)
    }

    /// Review Focus 5：编译「应用后的样子」时离开，结果丢掉、副本删掉、不留下辅助程序
    @Test func 准备时离开() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: true)

        // 换来源时离开
        s.compiler.block()
        let switching = Task { await model.switchSource(.pending, draft: draft, hasPending: true) }
        try await waitUntil { s.compiler.isWaiting }
        #expect(model.phase == .preparing("正在编译……"))
        await model.leave()
        s.compiler.release()
        await switching.value
        #expect(await s.engine.opens.count == 1)
        #expect(await s.engine.calls.last == .close)
        #expect(model.phase == .idle)
        #expect(s.stagingIsEmpty())

        // 来源停在「应用后的样子」，再进入时离开：一个引擎都没建
        s.compiler.block()
        let entering = Task { await model.enter(draft: draft, hasPending: true) }
        try await waitUntil { s.compiler.isWaiting }
        await model.leave()
        s.compiler.release()
        await entering.value
        #expect(s.engines.all.count == 1)
        #expect(await s.engine.opens.count == 1)
        #expect(model.phase == .idle)
        #expect(s.stagingIsEmpty())
        #expect(s.compiler.compiled.count == 2)
    }

    /// Review Focus 4：辅助程序卡住被杀掉以后，「重试」新建一个引擎重新开始
    @Test func 超时以后重试() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        await s.engine.failInput(.timedOut)
        await model.press(.text("n"))
        guard case let .failed(problem) = model.phase else { Issue.record("应该失败：\(model.phase)"); return }
        #expect(problem.title == "试打出错了" && problem.canRetry)
        // 失败以后打字不发给死掉的引擎
        await model.press(.text("i"))
        #expect(await s.engine.calls.filter { $0 == .input("i") }.isEmpty)
        await model.retry(draft: draft, hasPending: false)
        #expect(model.phase == .ready)
        #expect(s.engines.all.count == 2)
        let second = s.engines.all[1]
        let opens = await second.opens
        #expect(opens.count == 1)
        await model.press(.text("i"))
        #expect(await second.calls.last == .input("i"))
        await model.leave()
        #expect(s.stagingIsEmpty())
    }

    @Test func 找不到辅助程序() async throws {
        var s = try setup(); defer { s.remove() }
        s.env.previewEngine = { throw PreviewError.helperMissing }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        guard case .failed = model.phase else { Issue.record("应该失败：\(model.phase)"); return }
        await model.leave()
        #expect(s.stagingIsEmpty())
    }

    @Test func 需要重新载入() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        #expect(!model.needsReload(draft: draft))
        model.markCurrentChanged()
        #expect(!model.needsReload(draft: draft))   // 还没进入页面
        await model.enter(draft: draft, hasPending: true)
        #expect(!model.needsReload(draft: draft))
        model.markCurrentChanged()
        #expect(model.needsReload(draft: draft))
        await model.reload(draft: draft, hasPending: true)
        #expect(!model.needsReload(draft: draft))

        await model.switchSource(.pending, draft: draft, hasPending: true)
        model.markCurrentChanged()
        #expect(!model.needsReload(draft: draft))
        var changed = draft
        changed.appearance.fontPoint = 30
        #expect(model.needsReload(draft: changed))
        // 改回默认值不算改动
        var same = draft
        same.options["wubi"] = nil
        #expect(!model.needsReload(draft: same))

        // 细节 7：已经没有未应用的改动了，重新载入就切回「当前生效」
        await model.reload(draft: changed, hasPending: false)
        #expect(model.source == .current)
        #expect(model.phase == .ready)
        #expect(s.compiler.compiled.count == 1)
        await model.leave()
        #expect(s.stagingIsEmpty())
    }

    // MARK: 出错说明（设计第 5 节）

    @Test func 出错说明() {
        func d(_ error: any Error, installed: Bool = true, pending: Bool = false) -> PreviewProblem {
            PreviewProblem.describe(error, squirrelInstalled: installed, hasPending: pending)
        }
        #expect(d(PreviewError.notDeployed).title == "鼠须管还没部署过配置")
        #expect(d(PreviewError.notDeployed, pending: true).lines == d(PreviewError.notDeployed).lines + ["可以改看「应用后的样子」"])
        #expect(d(PreviewError.packagesNotCached(["测试拼音", "词库"])).title == "这些方案还没下载过：测试拼音、词库，应用改动时会下载")
        let compile = d(PreviewError.compileFailed(["第 1 行有问题"]))
        #expect(compile.title == "新配置编译不过" && compile.lines == ["第 1 行有问题"])
        let missing = d(PreviewError.failed(.schemaMissing, "副本里没有 build/wb_py.schema.yaml"))
        #expect(missing.title == "副本里找不到方案 wb_py")
        #expect(missing.lines.contains { $0.contains("重新载入") })
        #expect(d(PreviewError.failed(.schemaMissing, "选不了方案 py")).title == "副本里找不到方案 py")
        let team = d(PreviewError.failed(.loadFailed, "dlopen(...): code signature ... have different Team IDs"))
        #expect(team.title == "应用的签名有问题，试打用不了" && !team.canRetry)
        let load = d(PreviewError.failed(.loadFailed, "image not found"))
        #expect(load.title == "加载不了鼠须管的 librime" && load.lines.contains("image not found"))
        #expect(d(PreviewError.failed(.unsupportedVersion, "1.20.0")).title == "这个版本的鼠须管（librime 1.20.0）还没验证过，暂时不能试打")
        #expect(d(PreviewError.failed(.unsupportedVersion, "librime 2.0.1 还没验证过（要 1.16 或更新的 1.x）")).title
                == "这个版本的鼠须管（librime 2.0.1）还没验证过，暂时不能试打")
        let timedOut = d(PreviewError.timedOut)
        #expect(timedOut.title == "试打出错了" && timedOut.canRetry)
        let died = d(PreviewError.helperDied(status: 6, stderr: ["E1016 boom", "abort"]))
        #expect(died.title == "试打出错了" && died.canRetry)
        #expect(died.lines.contains { $0.contains("6") })
        #expect(died.lines.suffix(2) == ["E1016 boom", "abort"])
        let killed = d(PreviewError.helperDied(status: nil, stderr: []))
        #expect(killed.title == "试打出错了" && killed.canRetry && !killed.lines.isEmpty)
        let none = d(PreviewError.notDeployed, installed: false)
        #expect(none.title == "先安装鼠须管" && !none.canRetry)
        #expect(d(PreviewError.timedOut, installed: false).title == "先安装鼠须管")
    }

    // MARK: 接进主窗口

    @Test func 主窗口里的试打页() async throws {
        let pages = MainModel.Page.allCases
        let index = try #require(pages.firstIndex(of: .schemas))
        #expect(pages[index + 1] == .preview)
        #expect(MainModel.Page.preview.title == "试打")
        #expect(MainModel.Page.preview.symbol == "keyboard")

        let s = try setup(); defer { s.remove() }
        let model = try MainModel(env: s.env)
        await model.preview.enter(draft: model.draft, hasPending: model.hasPendingChanges)
        #expect(model.preview.phase == .ready)
        #expect(!model.preview.needsReload(draft: model.draft))
        model.draft.appearance.fontPoint = 26
        await model.apply()
        #expect(model.notice?.title == "改动已经生效")
        #expect(model.preview.needsReload(draft: model.draft))
        await model.preview.leave()
    }

    /// 等某个条件成立（最多 5 秒）
    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { Issue.record("等不到"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

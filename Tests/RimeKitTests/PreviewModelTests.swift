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
    /// 收到这些输入以后先停一会儿再回（测试按键顺序用）
    var inputDelays: [String: Duration] = [:]
    /// 打开这些方案时抛的错（每次都失败）
    let openFailures: [String: PreviewError]
    /// 开关的状态（没写的当作关着）
    let options: [String: Bool]

    init(openFailures: [String: PreviewError] = [:], options: [String: Bool] = [:]) {
        self.openFailures = openFailures
        self.options = options
    }

    func option(_ name: String) async throws -> Bool { options[name] ?? false }

    /// 这些序号的候选只对应前一段编码
    var partial: Set<Int> = []
    func setPartial(_ indices: Set<Int>) { partial = indices }
    func covers(_ index: Int) async throws -> Bool { !partial.contains(index) }

    func setInput(_ state: PreviewState) { inputState = state }
    func failInput(_ error: PreviewError?) { inputError = error }
    func setDelays(_ delays: [String: Duration]) { inputDelays = delays }

    func open(userDir: URL, schema: String) async throws -> PreviewOpened {
        calls.append(.open(userDir, schema))
        if let error = openFailures[schema] { throw error }
        return PreviewOpened(librimeVersion: "1.16.1", state: .empty)
    }

    func input(_ text: String) async throws -> PreviewState {
        // 先停再记：记下的是做完的先后。不排队的话，停得久的键会记在后面
        if let delay = inputDelays[text] { try? await Task.sleep(for: delay) }
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
    private var failures: [String: PreviewError] = [:]
    private var options: [String: Bool] = [:]

    var all: [FakePreviewEngine] { lock.withLock { made } }

    /// 之后建的引擎打开这些方案时都失败
    func failOpen(_ failures: [String: PreviewError]) { lock.withLock { self.failures = failures } }

    /// 之后建的引擎的开关状态
    func setOptions(_ options: [String: Bool]) { lock.withLock { self.options = options } }

    func make() -> any PreviewEngine {
        let engine = FakePreviewEngine(openFailures: lock.withLock { failures }, options: lock.withLock { options })
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

    @Test func 没有未应用的改动时来源不可切() async throws {
        #expect(PreviewModel.canSwitch(to: .current, hasPending: false))
        #expect(!PreviewModel.canSwitch(to: .pending, hasPending: false))
        #expect(PreviewModel.canSwitch(to: .pending, hasPending: true))
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        #expect(!model.sourcePickerEnabled(hasPending: false))
        #expect(model.sourcePickerEnabled(hasPending: true))
        await model.switchSource(.pending, draft: draft, hasPending: false)
        #expect(model.source == .current)
        #expect(await s.engine.opens.count == 1)
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

    @Test func 快速连按_引擎收到的顺序不变() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        // 前面的键让引擎多停一会儿：不排队的话后面的键会先到
        var delays: [String: Duration] = [:]
        let letters = (0..<40).map { "k\($0)" }
        for (i, key) in letters.enumerated() { delays[key] = .milliseconds((40 - i) % 7 * 3) }
        await s.engine.setDelays(delays)
        // 像视图那样：一个接一个提交，不等上一个做完
        for key in letters { model.submit(.press(.text(key))) }
        model.submit(.press(.special(.backspace)))
        model.submit(.choose(1))
        model.submit(.pageDown)
        model.submit(.clearInput)
        await model.press(.text("end"))
        let calls = await s.engine.calls
        let expected: [FakePreviewEngine.Call] = letters.map { .input($0) } + [.key(.backspace), .select(1), .key(.pageDown), .clear, .input("end")]
        #expect(Array(calls.dropFirst()) == expected)
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

        // 「应用后的样子」重新载入时离开：结果丢掉，不 open
        await model.enter(draft: draft, hasPending: true)
        await model.switchSource(.pending, draft: draft, hasPending: true)
        let engine = try #require(s.engines.all.last)
        let opensBefore = await engine.opens.count
        s.compiler.block()
        let reloading = Task { await model.reload(draft: draft, hasPending: true) }
        try await waitUntil { s.compiler.isWaiting }
        await model.leave()
        s.compiler.release()
        await reloading.value
        #expect(await engine.opens.count == opensBefore)
        #expect(await engine.calls.last == .close)
        #expect(model.phase == .idle)
        #expect(s.stagingIsEmpty())
        #expect(s.compiler.compiled.count == 3)
    }

    /// 设计 4.2：进入页面总是从「当前生效」开始，不记上次的来源（免得一进来就编译 10 秒）
    @Test func 再进入时从当前生效开始() async throws {
        let s = try setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: true)
        await model.switchSource(.pending, draft: draft, hasPending: true)
        #expect(model.source == .pending && s.compiler.compiled.count == 1)
        await model.leave()
        await model.enter(draft: draft, hasPending: true)
        #expect(model.source == .current)
        #expect(model.phase == .ready)
        #expect(model.schema == "wb_py")
        #expect(s.compiler.compiled.count == 1)   // 没有编译
        let engine = try #require(s.engines.all.last)
        guard case let .open(dir, _)? = await engine.opens.last else { Issue.record("没有 open"); return }
        #expect(dir.lastPathComponent == "user")   // 「当前生效」副本的目录
        await model.leave()
        #expect(s.stagingIsEmpty())
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

    /// 第一个方案每次都打不开：页面不能锁死，换第二个方案能用
    @Test(arguments: [PreviewError.helperDied(status: 6, stderr: []), .timedOut,
                      .failed(.schemaMissing, "选不了方案 wb_py")])
    func 第一个方案打不开时换方案(error: PreviewError) async throws {
        let s = try setup(); defer { s.remove() }
        s.engines.failOpen(["wb_py": error])
        let model = PreviewModel(env: s.env)
        await model.enter(draft: draft, hasPending: false)
        guard case .failed = model.phase else { Issue.record("应该失败：\(model.phase)"); return }
        #expect(model.schema == nil)
        #expect(model.canSelectSchema)
        // 失败时选回同一个方案也算再试一次
        await model.selectSchema("wb_py")
        guard case .failed = model.phase else { Issue.record("应该还是失败：\(model.phase)"); return }
        await model.selectSchema("py")
        #expect(model.phase == .ready)
        #expect(model.schema == "py")
        await model.press(.text("ni"))
        #expect(model.state.preedit == "ni")
        await model.leave()
        #expect(s.stagingIsEmpty())
    }

    @Test func 准备副本失败时不能换方案() async throws {
        let s = try setup(); defer { s.remove() }
        // 没部署过：准备副本就失败，没有副本可选
        try FileManager.default.removeItem(at: s.machine.locations.rimeDirectory.appending(path: "build"))
        let model = PreviewModel(env: s.env)
        #expect(!model.canSelectSchema)   // 还没进入页面
        await model.enter(draft: draft, hasPending: false)
        guard case .failed = model.phase else { Issue.record("应该失败：\(model.phase)"); return }
        #expect(!model.canSelectSchema)
        await model.selectSchema("py")
        guard case .failed = model.phase else { Issue.record("应该还是失败：\(model.phase)"); return }
        await model.leave()
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
        // 说的按钮要和界面上的一样（出错时只有「重试」）
        #expect(missing.canRetry && missing.lines == ["复制配置时鼠须管可能正在部署，点「重试」再试"])
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
        #expect(MainModel.Page.preview.title == "试打和置顶")
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

/// 候选置顶：哪些候选能置顶（候选置顶设计 5.4）
@MainActor @Suite struct PreviewPinTests {
    let kkkk = PreviewState(preedit: "kkkk",
                            candidates: ["串口", "叮叮咣咣", "口"].map { PreviewCandidate(text: $0, comment: "") },
                            input: "kkkk", wholeInput: true)
    let kou = Phrase(text: "口", code: "kkkk", weight: nil)

    func ready(_ s: PreviewModelTests.Setup, state: PreviewState) async -> PreviewModel {
        let model = PreviewModel(env: s.env)
        await model.enter(draft: TransferFixtures.settings, hasPending: false)
        await s.engine.setInput(state)
        await model.press(.text("kkkk"))
        return model
    }

    func put(_ s: PreviewModelTests.Setup, _ path: String, _ text: String) throws {
        let url = s.machine.locations.rimeDirectory.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func 整段编码的候选可以置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        let model = await ready(s, state: kkkk)
        #expect(model.pinBlock == nil)
        #expect(model.pinAvailability(at: 2, pinned: []) == .available(text: "口", code: "kkkk"))
        #expect(model.pinAvailability(at: 0, pinned: []) == .unavailable("已经是第一个了"))
        #expect(model.pinAvailability(at: 2, pinned: [kou]) == .unavailable("已经置顶了"))
        #expect(model.pinAvailability(at: 9, pinned: []) == .unavailable("这个候选不能置顶"))
        await model.leave()
    }

    @Test func 第二页的第一个可以置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        var state = kkkk
        state.pageNo = 1
        let model = await ready(s, state: state)
        #expect(model.pinAvailability(at: 0, pinned: []) == .available(text: "串口", code: "kkkk"))
        await model.leave()
    }

    @Test func 不是整段的候选不能置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        var state = kkkk
        state.wholeInput = false
        let model = await ready(s, state: state)
        #expect(model.pinAvailability(at: 2, pinned: []) == .unavailable("只能置顶整段编码的候选"))
        await model.leave()
    }

    @Test func 繁简转换开着时不能置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        try put(s, "build/wb_py.schema.yaml", """
            schema:
              schema_id: wb_py
              name: 五笔拼音
            engine:
              filters:
                - simplifier@tradition
                - uniquifier
            tradition:
              option_name: zh_trad

            """)
        s.engines.setOptions(["zh_trad": true])
        let model = await ready(s, state: kkkk)
        #expect(model.pinBlock == .conversion)
        #expect(model.pinAvailability(at: 2, pinned: []) == .unavailable("繁体方案里不能置顶，请换到简体方案再置顶"))
        await model.leave()

        let s2 = try PreviewModelTests().setup(); defer { s2.remove() }
        try put(s2, "build/wb_py.schema.yaml", "engine:\n  filters:\n    - simplifier@tradition\ntradition:\n  option_name: zh_trad\n")
        s2.engines.setOptions(["zh_trad": false])
        let off = await ready(s2, state: kkkk)
        #expect(off.pinBlock == nil)
        await off.leave()
    }

    @Test func 没写开关名的简繁过滤器用默认开关() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        try put(s, "build/wb_py.schema.yaml", "engine:\n  filters:\n    - simplifier\n")
        s.engines.setOptions(["simplification": true])
        let model = await ready(s, state: kkkk)
        #expect(model.pinBlock == .conversion)
        await model.leave()
    }

    @Test func 自带短语的方案不能置顶() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        try put(s, "wb_py.schema.yaml", "engine:\n  translators:\n    - table_translator@custom_phrase\n    - table_translator\n")
        let model = await ready(s, state: kkkk)
        #expect(model.pinBlock == .ownPhrases)
        #expect(model.pinAvailability(at: 2, pinned: []) == .unavailable("这个方案自带短语，置顶暂时只支持极点五笔这类方案"))
        await model.leave()
    }

    @Test func 看应用后的样子时改了置顶要重新载入() async throws {
        let s = try PreviewModelTests().setup(); defer { s.remove() }
        let model = PreviewModel(env: s.env)
        let draft = TransferFixtures.settings
        await model.enter(draft: draft, hasPending: true)
        model.markPersonalChanged()
        #expect(!model.needsReload(draft: draft))   // 在「当前生效」时不用
        await model.switchSource(.pending, draft: draft, hasPending: true)
        #expect(!model.needsReload(draft: draft))
        model.markPersonalChanged()
        #expect(model.needsReload(draft: draft))
        await model.reload(draft: draft, hasPending: true)
        #expect(!model.needsReload(draft: draft))
        await model.leave()
    }
}

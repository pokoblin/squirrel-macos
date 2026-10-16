import Foundation
import Observation
import RimeKit

/// 「五笔词库」页的逻辑（设计 4.1–4.6、第 5 节）。
/// 正本是 `personal/dicts/` 里的个人词库：加、改、删、导入、收回外面的修改都马上写进去，「应用改动」时才进 Rime 目录。
/// 读大词库、重建索引、编译检查用的副本都放在后台做；编辑的核心逻辑在 RimeKit 的 `WubiEditor`
@MainActor @Observable
public final class WubiDictModel {
    public enum Availability: Equatable, Sendable {
        case ready
        /// 没启用极点五笔的方案
        case notEnabled
        /// 本地没有极点五笔包的缓存（这一页不联网）
        case notDownloaded
        /// 主词库里没有组词规则：自动编码用不了，仍可手动填编码
        case badDict
        /// 个人词库文件读不了（带原因）。什么都不写
        case unreadable(String)

        /// 页面上的说明；ready 没有
        public var message: String? {
            switch self {
            case .ready: return nil
            case .notEnabled: return "先在「方案」页启用极点五笔"
            case .notDownloaded: return "还没下载极点五笔，先应用一次改动"
            case .badDict: return WubiEditProblem.noEncoder.description
            case .unreadable(let reason): return reason
            }
        }

        /// 能不能编辑（badDict 也能，只是要手填编码）
        public var canEdit: Bool { self == .ready || self == .badDict }
    }

    public private(set) var availability: Availability = .notEnabled
    /// 正在读词库
    public private(set) var isLoading = false
    /// 个人词库里的词条，和文件里的顺序一样
    public private(set) var entries: [DictEntry] = []
    /// 每个词条的编码（和 entries 一一对应）：写了的用写的，没写的是自动算出的第一个，算不出是 nil
    public private(set) var codes: [String?] = []
    /// 词条序号 → 在它的编码下排第几（从 1 起）。算不出的没有
    public private(set) var positions: [Int: Int] = [:]
    /// 搜索（按词或编码）
    public var searchText = ""
    /// 鼠须管目录里的个人词库在应用外被改过（页面顶部提示，按钮「把外面加的词收进来」）
    public private(set) var externallyChanged = false
    /// 有还没应用的词库改动（底部的「应用改动」）
    public private(set) var needsApply = false
    /// 词条序号 → 检查结果。词库一改就清空
    public private(set) var checkResults: [Int: CheckResult] = [:]
    public private(set) var isChecking = false
    /// 正在写文件（这时不接受别的修改）
    public private(set) var isSaving = false
    /// 结果、出错的说明
    public var message: String?

    // MARK: 加一个词的草稿

    /// 要加的词；改了就重新算编码
    public var draftText = "" {
        didSet { if draftText != oldValue { draftTextChanged() } }
    }
    /// 自动算编码的结果（没有编码器、没输入时是 nil）
    public private(set) var draftEncoding: WubiEncoding?
    /// 编码（自动算出的第一个，可以手动改）
    public var draftCode = "" {
        didSet { if draftCode != oldValue { draftCodeChanged() } }
    }
    /// 自动算出的所有可能编码（多个时让用户挑）
    public private(set) var draftCodeChoices: [String] = []
    /// 这个编码现在出什么（按顺序）
    public private(set) var existing: [IndexedWord] = []
    /// 排第几（从 1 起）；existing.count + 1 是最后（默认）
    public var draftPosition = 1 {
        didSet { if draftPosition != oldValue { updateDraftProblem() } }
    }
    /// 为什么加不了（算不出编码、编码不合法、已经加过了、词库里已经有了、这个位置放不进去）
    public private(set) var draftProblem: String?
    public private(set) var canAdd = false

    /// 可以选的位置：1 到 existing.count + 1（最后）
    public var draftPositions: ClosedRange<Int> { 1...(existing.count + 1) }

    let env: AppEnvironment
    let target = WubiDictTarget.jidian
    private var store: WubiUserDict { WubiUserDict(paths: env.paths, locations: env.locations, target: target) }
    /// 读好的编辑器（编码器、索引、个人词库）。不能编辑时是 nil
    private var editor: WubiEditor?
    /// 上次读的时候用的包和设置（应用、导入以后看要不要重新读）
    private var loadedPackage: CachedPackage?
    private var loadedSettings: Settings?
    /// 代号：每次读、每次改词库加一。后台的结果回来时代号对不上就丢掉
    private var generation = 0
    /// 正在读的那一次的代号（读完、或者被更新的一次读取接手时清掉）
    private var loadingGeneration: Int?
    /// editor 的个人词库对应的 personal 文件原文（还没有这个文件时是 nil）。
    /// 写之前核对磁盘上的还是它：不是的话（应用时采用了外面那份、rimectl 加了词）不覆盖，重新读
    private var base: Data?
    /// 测试用：合并、保存以后，记账之前调用（模拟这时外面又改了文件）
    var mergeHook: (@Sendable () -> Void)?

    public init(env: AppEnvironment) {
        self.env = env
        refresh()
    }

    /// Rime 目录里的个人词库的文件名（也是账本里的路径）
    public var rimeFileName: String { target.userDict }

    /// 读过（不管结果）
    public var isLoaded: Bool { loadedSettings != nil }

    /// 这个编码下现在出哪些词（按顺序，含个人词）。编码不合法或不能编辑时是空的。给「改编码和位置」用
    public func words(for code: String) -> [IndexedWord] {
        guard let editor, WubiEncoder.isValidCode(code) else { return [] }
        return editor.index.words(for: code)
    }

    /// 搜索后显示的词条序号
    public var visibleIndices: [Int] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(entries.indices) }
        return entries.indices.filter { i in
            entries[i].text.contains(query) || (codes[i]?.hasPrefix(query.lowercased()) ?? false)
        }
    }

    // MARK: 读

    /// 打开页面时读：settings 是现在的设置（草稿），用来看有没有启用极点五笔。只用本地缓存的包，不联网
    public func load(settings: Settings) async {
        generation += 1
        let current = generation
        loadedSettings = settings
        message = nil
        guard WubiCheck.checkSchema(in: settings, target: target) != nil else {
            reset(.notEnabled)
            return
        }
        guard let spec = env.catalog.package(target.packageID), let package = env.cachedPackage(spec) else {
            reset(.notDownloaded)
            return
        }
        isLoading = true
        loadingGeneration = current
        let store = self.store
        let target = self.target
        let result: Result<Loaded, LoadFailure> = await Task.detached {
            let userFile: DictFile
            let base: Data?
            do {
                // personal 里有文件时读一次原文，记下来写之前核对；没有时按起点规则读
                if FileManager.default.fileExists(atPath: store.personalFile.path) {
                    let data = try Data(contentsOf: store.personalFile)
                    base = data
                    userFile = try DictFile.parse(data: data)
                } else {
                    base = nil
                    userFile = try store.load(package: package)
                }
            } catch {
                return .failure(.personal(Self.reason(error)))
            }
            do {
                return .success(Loaded(
                    snapshot: Snapshot(try WubiEditor(package: package, userFile: userFile, target: target)), base: base))
            } catch {
                return .failure(.main("读不了极点五笔的主词库：\(error)"))
            }
        }.value
        if loadingGeneration == current {
            loadingGeneration = nil
            isLoading = false
        }
        // 这期间又开始了一次读取：结果交给那一次
        guard current == generation else { return }
        loadedPackage = package
        switch result {
        case .success(let loaded):
            base = loaded.base
            let snapshot = loaded.snapshot
            adopt(snapshot)
            availability = snapshot.editor.encoder == nil ? .badDict : .ready
            refresh()
        case .failure(.personal(let reason)), .failure(.main(let reason)):
            reset(.unreadable(reason))
        }
    }

    /// 应用改动、导入以后：个人词库或包变了就重新读，没变只更新「有没有改动」「外面改过」
    public func reloadIfChanged(settings: Settings) async {
        refresh()
        guard let previous = loadedSettings else { return }
        let enabled = WubiCheck.checkSchema(in: settings, target: target) != nil
        guard enabled else {
            if WubiCheck.checkSchema(in: previous, target: target) != nil { await load(settings: settings) }
            return
        }
        if let editor, let package = loadedPackage, let spec = env.catalog.package(target.packageID),
           env.cachedPackage(spec)?.filesDirectory == package.filesDirectory,
           (try? store.load(package: package))?.render() == editor.userFile.render() {
            loadedSettings = settings
            return
        }
        await load(settings: settings)
    }

    /// 重新看「有没有没应用的改动」「外面改过没有」（只算哈希，不读词库）。应用改动、还原以后由 MainModel 调用
    public func refresh() {
        let store = self.store
        needsApply = store.needsApply()
        externallyChanged = store.externalChange()
    }

    // MARK: 加、改、删

    public func add() async {
        guard canAdd, let editor else { return }
        let text = trimmedDraft
        guard case .success(let entry) = editor.plan(text: text, code: draftCode, position: planPosition) else { return }
        if await commit({ $0.applying([entry]) }) {
            draftText = ""
        }
        // 没写成时 commit 已经把原因放进 message
    }

    /// 改第 i 个词条的编码和位置（位置从 1 起，nil 是最后）
    public func update(at i: Int, code: String, position: Int?) async {
        guard let editor else {
            message = notEditable
            return
        }
        switch editor.planUpdate(at: i, code: code, position: position) {
        case .failure(let problem):
            message = problem.description
        case .success(let entry):
            message = nil
            guard entry != editor.userFile.entries[i] else { return }
            await commit { editor in
                var file = editor.userFile
                file.replaceEntry(at: i, with: entry)
                return editor.replacing(userFile: file)
            }
        }
    }

    public func remove(at i: Int) async {
        guard editor != nil else {
            message = notEditable
            return
        }
        guard entries.indices.contains(i) else {
            message = WubiEditProblem.noSuchEntry.description
            return
        }
        message = nil
        await commit { $0.replacing(userFile: WubiEditor.remove(indices: [i], from: $0.userFile)) }
    }

    // MARK: 批量导入

    /// 解析要导入的文本，列出每一行和状态（不写文件）
    /// 主词库认不出（badDict）时也能用：没写编码的行要手填，写了编码的行照样能加
    public func importRows(_ text: String) async -> [ImportRow] {
        guard let editor else { return [] }
        return await Task.detached { editor.parseImport(text) }.value
    }

    /// 把选中的行加进去。用户在表里可能改过编码：再查一次重，重复的跳过
    public func confirmImport(_ rows: [ImportRow]) async {
        guard let editor else {
            message = notEditable
            return
        }
        var kept: [DictEntry] = []
        var seen = Set<String>()
        for e in WubiImport.entries(from: rows) {
            let code = e.code ?? ""
            let found = editor.index.contains(text: e.text, code: code)
            guard !found.inPersonal, !found.inOthers, seen.insert(e.text + "\t" + code).inserted else { continue }
            kept.append(e)
        }
        guard !kept.isEmpty else {
            message = "没有可以加的词"
            return
        }
        let adding = kept
        if await commit({ $0.applying(adding) }) {
            message = "加入 \(adding.count) 个，可以点「检查能不能打出来」"
        }
    }

    // MARK: 外面改过

    /// 「把外面加的词收进来」：按词条合并，外面删掉的不跟着删；之后「应用改动」时这份文件不再算外部改动。
    /// 合并完又被改了，就再收一次；还是不行就说明。返回收成了没有（没收成时原因在 message 里）
    @discardableResult
    public func mergeExternal() async -> Bool {
        guard let editor else {
            message = notEditable
            return false
        }
        guard startSaving() else { return false }
        defer { isSaving = false }
        generation += 1
        let current = generation
        let store = self.store
        let start = self.base
        let hook = mergeHook
        let outcome: MergeOutcome = await Task.detached {
            var file = editor.userFile
            var base = start
            var added = 0
            var failure: String?
            for _ in 1...2 {
                do {
                    let result = try store.mergeExternal(into: file)
                    try Self.ensureUnchanged(store, base)
                    // 一个词都没加也要写：还没有 personal 里的文件时，起点就是外面那份
                    try store.save(result.merged)
                    file = result.merged
                    base = Data(file.render().utf8)
                    added += result.added
                    hook?()
                    try store.acknowledgeExternal(expectedSHA256: result.sourceSHA256)
                    failure = nil
                    break
                } catch is StaleFile {
                    return .stale
                } catch let error as WubiUserDictError {
                    failure = error.description
                } catch {
                    failure = "没能把外面加的词收进来：\(error)"
                    break
                }
            }
            return .done(Snapshot(editor.replacing(userFile: file)), base: base, added: added, failure: failure)
        }.value
        switch outcome {
        case .stale:
            await reloadAfterStale()
            return false
        case .done(let snapshot, let base, let added, let failure):
            guard current == generation else {
                message = "词库刚才重新读过了，请再收一次"
                return false
            }
            self.base = base
            adopt(snapshot)
            refresh()
            message = failure ?? "收进来 \(added) 个词"
            return failure == nil
        }
    }

    // MARK: 检查能不能打出来

    /// 用「应用后的样子」（按 draft 生成、编译一份副本）试打个人词库里的每个词。只用本地缓存的包，用完删掉副本
    public func check(draft: Settings) async {
        guard let editor, !isChecking else { return }
        guard let schema = WubiCheck.checkSchema(in: draft, target: target) else {
            message = Availability.notEnabled.message
            return
        }
        let entries = editor.entriesWithCodes
        guard !entries.isEmpty else {
            message = "个人词库里还没有词"
            return
        }
        isChecking = true
        defer { isChecking = false }
        message = nil
        checkResults = [:]
        let current = generation
        let env = self.env
        let index = editor.index
        do {
            let results = try await Task.detached {
                let (input, _) = try PreviewModel.pendingInput(draft, env: env)
                let copy = try PreviewWorkspace(paths: env.paths, locations: env.locations, compiler: env.compiler)
                    .preparePending(input)
                defer { copy.remove() }
                guard copy.schemas.contains(where: { $0.id == schema }) else { throw CheckFailure.noSchema(schema) }
                let engine = try env.previewEngine()
                do {
                    let results = try await WubiCheck.run(entries, index: index, engine: engine, userDir: copy.userDir, schema: schema)
                    await engine.close()
                    return results
                } catch {
                    await engine.close()
                    throw error
                }
            }.value
            guard current == generation else {
                message = "检查的时候词库改过了，请再检查一次"
                return
            }
            checkResults = Dictionary(uniqueKeysWithValues: results.enumerated().map { ($0.offset, $0.element) })
        } catch {
            let problem = PreviewProblem.describe(error, squirrelInstalled: env.locations.squirrelInstalled, hasPending: true)
            message = ([problem.title] + problem.lines).joined(separator: "\n")
        }
    }

    // MARK: 内部

    /// 后台算好的一份：编辑器，加上列表要显示的编码和位置
    private struct Snapshot: Sendable {
        let editor: WubiEditor
        let codes: [String?]
        let positions: [Int: Int]

        init(_ editor: WubiEditor) {
            self.editor = editor
            let coded = editor.entriesWithCodes
            codes = coded.map(\.code)
            var positions: [Int: Int] = [:]
            for (i, e) in coded.enumerated() {
                if let p = editor.position(of: e) { positions[i] = p }
            }
            self.positions = positions
        }
    }

    private struct Loaded: Sendable {
        let snapshot: Snapshot
        let base: Data?
    }

    private enum MergeOutcome: Sendable {
        /// personal 里的文件在应用外被改了，没有写
        case stale
        case done(Snapshot, base: Data?, added: Int, failure: String?)
    }

    /// personal 里的文件和读的时候不一样了
    private struct StaleFile: Error {}

    /// 写之前核对：磁盘上的 personal 文件还是 base（不在就是 nil）
    nonisolated private static func ensureUnchanged(_ store: WubiUserDict, _ base: Data?) throws {
        let now = FileManager.default.fileExists(atPath: store.personalFile.path)
            ? try? Data(contentsOf: store.personalFile) : nil
        guard now == base else { throw StaleFile() }
    }

    /// 不能编辑时（没读、没启用、读不了）给人看的原因
    private var notEditable: String {
        if isLoading { return "正在读五笔词库，等读完再试" }
        return availability.message ?? "五笔词库还没读好"
    }

    /// 开始写：正在读、正在写时不接受，说明原因
    private func startSaving() -> Bool {
        if isLoading {
            message = "正在读五笔词库，等读完再试"
            return false
        }
        if isSaving {
            message = "正在保存上一个改动，等一下再试"
            return false
        }
        isSaving = true
        return true
    }

    /// 个人词库在别处被改过：不覆盖，重新读，请用户再做一次
    private func reloadAfterStale() async {
        if let settings = loadedSettings { await load(settings: settings) }
        message = "五笔个人词库刚才在别处被改过（比如应用时采用了外面那份，或者用 rimectl 改了），已经重新读了，请再操作一次"
    }

    private enum LoadFailure: Error {
        case personal(String)
        case main(String)
    }

    private enum CheckFailure: Error, CustomStringConvertible {
        case noSchema(String)

        var description: String {
            switch self {
            case .noSchema(let id): return "编译出来的配置里没有方案「\(id)」"
            }
        }
    }

    /// 个人词库读不了的原因（给人看）
    nonisolated private static func reason(_ error: any Error) -> String {
        switch error as? DictFileError {
        case .notUTF8?: return "五笔个人词库读不了：文件不是 UTF-8 编码的文本"
        case .noHeader?: return "五笔个人词库读不了：文件开头没有「---」到「...」的头部"
        case nil: return "五笔个人词库读不了：\(error)"
        }
    }

    /// 写进 personal，换上新的编辑器。make 在后台跑（重建索引）
    @discardableResult
    /// 没写成时（正在读、正在写、文件在别处被改过、写不了）返回 false，原因放进 message
    private func commit(_ make: @escaping @Sendable (WubiEditor) -> WubiEditor) async -> Bool {
        guard let editor else {
            message = notEditable
            return false
        }
        guard startSaving() else { return false }
        defer { isSaving = false }
        generation += 1
        let current = generation
        let store = self.store
        let base = self.base
        do {
            let (snapshot, saved) = try await Task.detached {
                try Self.ensureUnchanged(store, base)
                let updated = make(editor)
                try store.save(updated.userFile)
                return (Snapshot(updated), Data(updated.userFile.render().utf8))
            }.value
            guard current == generation else {
                // 写进去了，但这期间页面重新读了词库：以重新读的为准
                message = "已经保存；词库刚才重新读过，请看一下刚才的改动"
                return false
            }
            self.base = saved
            adopt(snapshot)
            refresh()
            return true
        } catch is StaleFile {
            await reloadAfterStale()
            return false
        } catch {
            message = "没能保存五笔个人词库：\(error)"
            return false
        }
    }

    private func adopt(_ snapshot: Snapshot) {
        editor = snapshot.editor
        entries = snapshot.editor.userFile.entries
        codes = snapshot.codes
        positions = snapshot.positions
        checkResults = [:]
        refreshDraft()
    }

    private func reset(_ availability: Availability) {
        isLoading = false
        loadingGeneration = nil
        editor = nil
        base = nil
        entries = []
        codes = []
        positions = [:]
        checkResults = [:]
        self.availability = availability
        refreshDraft()
        refresh()
    }

    private var trimmedDraft: String { draftText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 选的位置交给 plan：最后就是 nil（不写权重）
    private var planPosition: Int? { draftPosition > existing.count ? nil : draftPosition }

    private func draftTextChanged() {
        let text = trimmedDraft
        draftEncoding = text.isEmpty ? nil : editor?.encoder?.encode(text)
        if case .codes(let list) = draftEncoding {
            draftCodeChoices = list
            draftCode = list[0]
        } else {
            draftCodeChoices = []
            draftCode = ""
        }
        updateDraftProblem()
    }

    private func draftCodeChanged() {
        existing = editor.flatMap { WubiEncoder.isValidCode(draftCode) ? $0.index.words(for: draftCode) : nil } ?? []
        draftPosition = existing.count + 1
        updateDraftProblem()
    }

    /// 词库变了（加了、改了、重新读了）：重新算草稿。位置还在范围里就留着
    private func refreshDraft() {
        let text = trimmedDraft
        draftEncoding = text.isEmpty ? nil : editor?.encoder?.encode(text)
        if case .codes(let list) = draftEncoding { draftCodeChoices = list } else { draftCodeChoices = [] }
        existing = editor.flatMap { WubiEncoder.isValidCode(draftCode) ? $0.index.words(for: draftCode) : nil } ?? []
        if !draftPositions.contains(draftPosition) { draftPosition = existing.count + 1 }
        updateDraftProblem()
    }

    private func updateDraftProblem() {
        let text = trimmedDraft
        guard let editor, !text.isEmpty else {
            draftProblem = nil
            canAdd = false
            return
        }
        guard !draftCode.isEmpty else {
            if case .failure(let problem) = editor.resolveCode(text: text, given: nil) {
                draftProblem = problem.description
            } else {
                draftProblem = nil
            }
            canAdd = false
            return
        }
        switch editor.plan(text: text, code: draftCode, position: planPosition) {
        case .success:
            draftProblem = nil
            canAdd = true
        case .failure(let problem):
            draftProblem = problem.description
            canAdd = false
        }
    }
}

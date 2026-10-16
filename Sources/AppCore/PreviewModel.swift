import Foundation
import Observation
import RimeKit

/// 输入区收到的一个按键翻成什么（设计 4.1）
public enum PreviewKeyPress: Equatable, Sendable {
    /// 可打印 ASCII，原样交给 librime
    case text(String)
    /// 退格、Esc、回车、翻页、上下
    case special(PreviewKey)
    /// 不处理（带 Ctrl/Option/Command 的组合键交给系统；非 ASCII 字符丢掉）
    case ignored

    /// characters：按键打出的字符；special：认出来的特殊键；commandLike：按着 Ctrl、Option 或 Command
    public static func translate(characters: String, special: PreviewKey?, commandLike: Bool) -> PreviewKeyPress {
        if commandLike { return .ignored }
        if let special { return .special(special) }
        // 只收 0x20–0x7e：系统里另一个中文输入法打出来的字、Option 组合出来的符号、emoji 都不要
        guard !characters.isEmpty, characters.unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else {
            return .ignored
        }
        return .text(characters)
    }
}

/// 「试打」页的逻辑（设计 4.2、4.3）。重活（复制、编译）放到后台；辅助程序由 PreviewEngine 管
@MainActor @Observable
public final class PreviewModel {
    public enum Source: Sendable {
        /// 当前生效：复制鼠须管正在用的配置
        case current
        /// 应用后的样子：按草稿生成、编译一份
        case pending
    }

    public enum Phase: Equatable {
        case idle
        /// 正在准备（文字显示在界面上）
        case preparing(String)
        case ready
        case failed(PreviewProblem)
    }

    public private(set) var source: Source = .current
    /// 副本里能试打的方案
    public private(set) var schemas: [PreviewSchema] = []
    /// 正在试打的方案
    public private(set) var schema: String?
    /// librime 给的编码、候选、页码
    public private(set) var state: PreviewState = .empty
    /// 已上屏的文字（选词、自动上屏的接在后面）
    public private(set) var committedText = ""
    public private(set) var phase: Phase = .idle
    /// 准备副本时的提醒（比如读不了文本替换）
    public private(set) var notes: [String] = []
    public private(set) var librimeVersion: String?

    let env: AppEnvironment
    private var engine: (any PreviewEngine)?
    private var copy: PreviewCopy?
    /// 代号：离开页面、换来源、重新载入时加一。后台结果回来时代号对不上，就丢掉结果、删掉副本
    private var generation = 0
    private var entered = false
    /// 「当前生效」在副本准备好以后又变了（应用改动、还原、导入）
    private var currentChanged = false
    /// 准备「应用后的样子」时用的设置
    private var pendingSettings: Settings?
    /// 上次准备、打开时有没有未应用的改动（出错说明里用）
    private var hasPending = false
    /// 出错以后「重试」只要重新打开方案（副本还能用，只是辅助程序没了）
    private var retryReopens = false

    public init(env: AppEnvironment) {
        self.env = env
    }

    // MARK: 进入、离开、换来源

    /// 进入页面：准备副本、打开第一个方案。上次停在「应用后的样子」但已经没有未应用的改动时，用「当前生效」
    public func enter(draft: Settings, hasPending: Bool) async {
        guard !entered else { return }
        entered = true
        if source == .pending && !hasPending { source = .current }
        await load(draft: draft, hasPending: hasPending)
    }

    /// 离开页面：丢掉正在准备的结果、关掉辅助程序、删掉副本
    public func leave() async {
        generation += 1
        entered = false
        let oldEngine = engine
        let oldCopy = copy
        engine = nil
        copy = nil
        schemas = []
        schema = nil
        state = .empty
        committedText = ""
        notes = []
        phase = .idle
        retryReopens = false
        // 先等辅助程序退出，再删它在用的目录
        await oldEngine?.close()
        oldCopy?.remove()
    }

    public func switchSource(_ s: Source, draft: Settings, hasPending: Bool) async {
        guard s != source else { return }
        if s == .pending && !hasPending { return }
        source = s
        guard entered else { return }
        await load(draft: draft, hasPending: hasPending)
    }

    /// 换方案：同一个辅助程序、同一份副本，只换方案
    public func selectSchema(_ id: String) async {
        guard phase == .ready, id != schema, schemas.contains(where: { $0.id == id }) else { return }
        generation += 1
        await open(id, generation: generation)
    }

    /// 「配置变了，重新载入」：重建副本。已经没有未应用的改动时切回「当前生效」（细节 7）
    public func reload(draft: Settings, hasPending: Bool) async {
        guard entered else { return }
        if source == .pending && !hasPending { source = .current }
        await load(draft: draft, hasPending: hasPending)
    }

    /// 出错后的「重试」：辅助程序没了就新建一个重新打开方案；别的错从准备副本重新来
    public func retry(draft: Settings, hasPending: Bool) async {
        guard entered else { return }
        if retryReopens, copy != nil {
            generation += 1
            await open(schema ?? schemas.first?.id ?? "", generation: generation)
        } else {
            await reload(draft: draft, hasPending: hasPending)
        }
    }

    // MARK: 打字

    public func press(_ p: PreviewKeyPress) async {
        switch p {
        case let .text(text): await send { try await $0.input(text) }
        case let .special(key): await send { try await $0.key(key) }
        case .ignored: return
        }
    }

    /// 点候选（本页第几个，从 0 开始）
    public func choose(_ index: Int) async {
        await send { try await $0.select(index) }
    }

    public func pageUp() async {
        await send { try await $0.key(.pageUp) }
    }

    public func pageDown() async {
        await send { try await $0.key(.pageDown) }
    }

    /// 清空输入区（没上屏的编码）
    public func clearInput() async {
        await send { try await $0.clear() }
    }

    public func clearCommitted() {
        committedText = ""
    }

    // MARK: 配置变了（细节 6）

    /// 应用改动、还原、导入成功以后由 MainModel 调用
    public func markCurrentChanged() {
        currentChanged = true
    }

    /// 要不要显示「配置变了，重新载入」
    public func needsReload(draft: Settings) -> Bool {
        guard entered else { return false }
        switch source {
        case .current:
            return currentChanged
        case .pending:
            guard let pendingSettings else { return false }
            return pendingSettings.normalized(for: env.catalog) != draft.normalized(for: env.catalog)
        }
    }

    // MARK: 准备副本、打开方案

    /// 按现在的来源准备一份新副本，打开方案；成功以后删掉旧副本
    private func load(draft: Settings, hasPending: Bool) async {
        generation += 1
        let current = generation
        self.hasPending = hasPending
        retryReopens = false
        state = .empty
        notes = []
        guard env.locations.squirrelInstalled else {
            phase = .failed(.notInstalled)
            await dropCopy()
            return
        }
        let source = self.source
        let env = self.env
        if source == .current {
            currentChanged = false
            phase = .preparing("正在复制配置……")
        } else {
            pendingSettings = draft
            phase = .preparing("正在编译……")
        }

        let made: (copy: PreviewCopy, notes: [String])
        do {
            made = try await Task.detached {
                let workspace = PreviewWorkspace(paths: env.paths, locations: env.locations, compiler: env.compiler)
                switch source {
                case .current:
                    return (try workspace.prepareCurrent(), [])
                case .pending:
                    let (input, notes) = try Self.pendingInput(draft, env: env)
                    return (try workspace.preparePending(input), notes)
                }
            }.value
        } catch {
            guard current == generation else { return }
            fail(error)
            await dropCopy()
            return
        }
        // 准备的时候离开了页面、换了来源：结果不要了
        guard current == generation else {
            made.copy.remove()
            return
        }
        let old = copy
        copy = made.copy
        schemas = made.copy.schemas
        notes = made.notes
        let keep = schema.flatMap { id in made.copy.schemas.contains { $0.id == id } ? id : nil }
        await open(keep ?? made.copy.schemas[0].id, generation: current)
        // 辅助程序已经换到新目录（或者已经关了），旧副本可以删了
        old?.remove()
    }

    /// 打开方案（没有辅助程序就新建一个）
    private func open(_ id: String, generation current: Int) async {
        guard let copy else { return }
        let engine: any PreviewEngine
        do {
            engine = try self.engine ?? env.previewEngine()
        } catch {
            fail(error)
            return
        }
        self.engine = engine
        if phase == .ready || isFailed { phase = .preparing("正在打开方案……") }
        do {
            let opened = try await engine.open(userDir: copy.userDir, schema: id)
            guard current == generation else { return }
            schema = id
            state = opened.state
            librimeVersion = opened.librimeVersion
            phase = .ready
        } catch {
            guard current == generation else { return }
            await engineFailed(error)
        }
    }

    /// 发一个打字的请求，结果放进状态；上屏的文字接到已上屏后面
    private func send(_ request: @Sendable (any PreviewEngine) async throws -> PreviewState) async {
        guard phase == .ready, let engine else { return }
        let current = generation
        do {
            let result = try await request(engine)
            guard current == generation else { return }
            if let committed = result.committed { committedText += committed }
            state = result
        } catch {
            guard current == generation else { return }
            await engineFailed(error)
        }
    }

    /// 辅助程序那边出的错。超时、退出以后这个引擎就不能用了，重试时新建一个
    private func engineFailed(_ error: any Error) async {
        var reopen = true
        switch error as? PreviewError {
        case .timedOut?, .helperDied?:
            let dead = engine
            engine = nil
            fail(error)
            retryReopens = true
            await dead?.close()
            return
        case .failed(.schemaMissing, _)?:
            // 副本本身缺东西：重试要重新准备副本
            reopen = false
        default:
            break
        }
        fail(error)
        retryReopens = reopen
    }

    private func fail(_ error: any Error) {
        retryReopens = false
        phase = .failed(PreviewProblem.describe(error, squirrelInstalled: env.locations.squirrelInstalled, hasPending: hasPending))
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// 准备失败时：旧副本和来源对不上了，删掉。辅助程序可能还在用它，先关掉（下次打开时新建）
    private func dropCopy() async {
        let oldEngine = engine
        let oldCopy = copy
        engine = nil
        copy = nil
        schemas = []
        await oldEngine?.close()
        oldCopy?.remove()
    }

    /// 「应用后的样子」的生成输入：只用本地缓存的方案包，不联网（设计 3.4）
    nonisolated static func pendingInput(_ settings: Settings, env: AppEnvironment) throws -> (GenerationInput, [String]) {
        let catalog = env.catalog
        try settings.validate(catalog)
        var packages: [String: CachedPackage] = [:]
        var missing: [String] = []
        for spec in try settings.requiredPackages(catalog) {
            if let cached = env.cachedPackage(spec) {
                packages[spec.id] = cached
            } else {
                missing.append(spec.name)
            }
        }
        guard missing.isEmpty else { throw PreviewError.packagesNotCached(missing) }
        var notes: [String] = []
        var replacements: [Phrase] = []
        if settings.textReplacement.sync {
            do {
                replacements = try env.textReplacements().usable
            } catch {
                notes.append("读不了 macOS 文本替换（\(error)），这里先不带文本替换的短语")
            }
        }
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: try PersonalContent.load(from: env.paths), textReplacementPhrases: replacements)
        return (input, notes)
    }
}

extension Settings {
    /// 包选项里和默认值一样的项去掉（改回默认值不算改动）
    func normalized(for catalog: Catalog) -> Settings {
        var copy = self
        for (packageID, choices) in options {
            guard let package = catalog.package(packageID) else { continue }
            let defaults = Dictionary(uniqueKeysWithValues: package.options.map { ($0.id, $0.defaultChoice) })
            let kept = choices.filter { defaults[$0.key] != $0.value }
            copy.options[packageID] = kept.isEmpty ? nil : kept
        }
        return copy
    }
}

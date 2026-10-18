import Foundation
import Observation
import RimeKit

/// 主窗口：设置草稿（改了点「应用改动」才生效），以及导出、导入、还原、检查等操作（见 MainModel+Actions）
@MainActor @Observable
public final class MainModel {
    public enum Page: String, CaseIterable, Identifiable, Sendable {
        case schemas, preview, wubiDict, appearance, textReplacement, transfer, backups, diagnostics

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .schemas: return "方案"
            case .preview: return "试打和置顶"
            case .wubiDict: return "五笔词库"
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
            case .preview: return "keyboard"
            case .wubiDict: return "character.book.closed"
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
    public var isDirty: Bool { normalized(draft) != normalized(saved) }
    /// 正在做的事（界面上显示）；nil 表示空闲
    public internal(set) var working: String?
    public var notice: Notice?
    /// 应用时遇到的外部改动：界面弹窗让用户选（覆盖 / 采用外面改过的个人词库 / 放弃）
    public internal(set) var pendingExternalChanges: [ExternalChange]?
    /// 外部改动里有个人词库被改过（弹窗里多一个「采用」）
    public internal(set) var pendingPersonalChanges = false
    /// 外部改动弹窗里要多说的一句（设计 4.4）：五笔个人词库在外面被改过、页面里又有没应用的改动时，
    /// 选「采用」会用外面那份整份替换 personal 里的，页面里的改动就没了
    public var adoptPersonalWarning: String? {
        guard pendingPersonalChanges, let changes = pendingExternalChanges,
              changes.contains(.modified(wubiDict.rimeFileName)), wubiDict.needsApply
        else { return nil }
        return "采用外面那份时，五笔词库页里还没应用的改动（新加、改过、删掉的词）会被换掉"
    }
    /// 上次应用用的选项（用户在弹窗里选了以后再用）；onlySync：只同步文本替换（应用已保存的设置，不带草稿）
    var lastApply = (options: ApplyOptions(), usingCache: false, onlySync: false)
    public internal(set) var colorSchemes: [ColorSchemeInfo] = []
    public internal(set) var textReplacementStatus: TextReplacementStatus?
    public internal(set) var backups: [BackupInfo] = []
    public internal(set) var checks: [DoctorCheck] = []
    /// 导出时带上输入习惯（默认带上）
    public var includeUserDB = true
    /// 生效的方案清单（检查更新、导入时会换）
    public internal(set) var catalogStatus: CatalogStatus
    public var catalog: Catalog { catalogStatus.catalog }
    /// 方案清单更新改到了正在用的包：要重新应用一次（存到磁盘，退出再打开还提醒）
    public internal(set) var catalogNeedsApply = false {
        didSet { if catalogNeedsApply != oldValue { savePending() } }
    }
    /// 「检查更新」查到上游有新版本、还没应用的包 id（存到磁盘，退出再打开还提醒）
    public internal(set) var packageUpdates: [String] = [] {
        didSet { if packageUpdates != oldValue { savePending() } }
    }
    /// 底部要不要显示「应用改动」：设置改了、方案清单要重新应用、方案包有新版本、五笔个人词库或置顶有没应用的改动
    public var hasPendingChanges: Bool {
        isDirty || catalogNeedsApply || !packageUpdates.isEmpty || wubiDict.needsApply || pins.needsApply
    }
    /// 应用时只有五笔个人词库在外面被改过：已经提示过一次「收进来」（再应用就按原来的外部改动流程问）
    var wubiMergeOffered = false

    /// 「试打」页
    public let preview: PreviewModel
    /// 「五笔词库」页
    public let wubiDict: WubiDictModel
    /// 候选置顶（在「试打和置顶」页）
    public let pins: PinsModel

    let env: AppEnvironment

    public init(env: AppEnvironment, welcome: [String] = []) throws {
        guard let settings = try SettingsStore(paths: env.paths).load() else { throw TransferError.noSettings }
        self.env = env
        preview = PreviewModel(env: env)
        wubiDict = WubiDictModel(env: env)
        pins = PinsModel(env: env)
        catalogStatus = env.catalogs.status
        saved = settings
        draft = settings
        let pending = PendingApply.load(env.paths)
        catalogNeedsApply = pending.catalog
        packageUpdates = pending.packages
        pins.refresh()
        if !welcome.isEmpty { notice = Notice(kind: .info, title: "设置好了", lines: welcome) }
        refreshColorSchemes()
    }

    /// 包选项里和默认值一样的项去掉（改回默认值不算改动）
    func normalized(_ settings: Settings) -> Settings {
        settings.normalized(for: catalog)
    }

    public func revert() {
        draft = saved
    }

    func savePending() {
        PendingApply(catalog: catalogNeedsApply, packages: packageUpdates).save(env.paths)
    }

    /// 底栏「应用改动」旁边的说明。设置没动时要说清楚要应用的是什么（不然「撤销」找不到，也不知道点了会怎样）
    public var pendingSummary: String {
        if isDirty {
            let others = [wubiDict.needsApply ? "五笔词库" : nil, pins.needsApply ? "置顶" : nil].compactMap { $0 }
            return others.isEmpty ? "有改动还没应用" : "有改动还没应用（「撤销」只撤销设置，不撤销\(others.joined(separator: "和"))的改动）"
        }
        var parts: [String] = []
        if catalogNeedsApply { parts.append("方案清单更新了") }
        if !packageUpdates.isEmpty { parts.append("\(packageUpdateNames.joined(separator: "、")) 有新版本") }
        if wubiDict.needsApply { parts.append(parts.isEmpty ? "五笔词库有改动" : "五笔词库也有改动") }
        if pins.needsApply { parts.append(parts.isEmpty ? "置顶有改动" : "置顶也有改动") }
        return parts.joined(separator: "，") + "，还没应用"
    }

    /// 导入会整份换掉设置和 personal：设置或置顶有没应用的改动时，导入前要提醒会丢掉
    public var importDropsUnappliedEdits: Bool { isDirty || pins.needsApply }

    /// 底栏「应用改动」旁边的说明里，有新版本的包叫什么
    public var packageUpdateNames: [String] {
        packageUpdates.map { catalog.package($0)?.name ?? $0 }
    }

    // MARK: 方案

    /// 有方案的包（方案页列出来让用户启用）。下架的不列，正在用的除外
    public var catalogPackages: [PackageSpec] {
        let used = Set((draft.schemas + saved.schemas).compactMap { catalog.packageOwning(schema: $0)?.id })
        return catalog.packages.filter { !$0.schemas.isEmpty && (!$0.deprecated || used.contains($0.id)) }
    }

    public func schemaName(_ id: String) -> String {
        catalog.packageOwning(schema: id)?.schemas.first { $0.id == id }?.name ?? id
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
        let packages = Set(draft.schemas.compactMap { catalog.packageOwning(schema: $0)?.id })
        guard packages.count > 1 else { return nil }
        return "同时启用了好几个方案包的方案，它们的默认短语、按键设置可能会互相影响"
    }

    // MARK: 包选项

    /// 用到的包里有选项的
    public var optionPackages: [PackageSpec] {
        ((try? draft.requiredPackages(catalog)) ?? []).filter { !$0.options.isEmpty }
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
        let packages = ((try? draft.requiredPackages(catalog)) ?? []).compactMap { env.cachedPackage($0) }
        colorSchemes = (try? ColorSchemes.available(in: packages)) ?? []
    }
}

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

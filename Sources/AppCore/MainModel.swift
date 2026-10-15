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
    /// 应用时遇到的外部改动：界面弹窗让用户选（覆盖 / 采用外面改过的个人词库 / 放弃）
    public internal(set) var pendingExternalChanges: [ExternalChange]?
    /// 外部改动里有个人词库被改过（弹窗里多一个「采用」）
    public internal(set) var pendingPersonalChanges = false
    /// 上次应用用的选项（用户在弹窗里选了以后再用）
    var lastApply = (options: ApplyOptions(), usingCache: false)
    public internal(set) var colorSchemes: [ColorSchemeInfo] = []
    public internal(set) var textReplacementStatus: TextReplacementStatus?
    public internal(set) var backups: [BackupInfo] = []
    public internal(set) var checks: [DoctorCheck] = []
    /// 导出时带上输入习惯（默认带上）
    public var includeUserDB = true

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

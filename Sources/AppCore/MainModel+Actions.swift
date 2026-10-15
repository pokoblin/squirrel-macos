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

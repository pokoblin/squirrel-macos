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
        await run(options, usingCache: usingCache, onlySync: false)
    }

    /// 只同步文本替换：按已保存的设置（打开同步）重新写入，草稿里别的改动留着
    public func syncTextReplacement() async {
        await run(ApplyOptions(), usingCache: false, onlySync: true)
    }

    func run(_ options: ApplyOptions, usingCache: Bool, onlySync: Bool) async {
        guard working == nil else { return }
        var settings = onlySync ? saved : draft
        if onlySync { settings.textReplacement.sync = true }
        do {
            try settings.validate(catalog)
        } catch {
            notice = Notice(kind: .error, title: "设置有问题", lines: ["\(error)"])
            return
        }
        working = "正在准备……"
        defer { working = nil }
        lastApply = (options, usingCache, onlySync)
        pendingExternalChanges = nil
        do {
            guard let packages = try await packages(for: settings, usingCache: usingCache) else { return }
            let replacements: [Phrase]
            if settings.textReplacement.sync {
                do {
                    replacements = try env.textReplacements().usable
                } catch {
                    notice = Notice(kind: .error, title: "读不了 macOS 文本替换，没有写入",
                                    lines: ["\(error)", "可以去「系统设置 → 隐私与安全性」检查权限；或者先在「文本替换」页关掉同步，再应用改动"])
                    return
                }
            } else {
                replacements = []
            }
            let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
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
                catalogNeedsApply = false
                wubiMergeOffered = false
                preview.markCurrentChanged()
                if onlySync {
                    draft.textReplacement.lastSyncedHash = updated.textReplacement.lastSyncedHash
                    draft.textReplacement.syncedEntries = updated.textReplacement.syncedEntries
                } else {
                    draft = updated
                }
                refreshColorSchemes()   // 这次可能新下载了包
                notice = Self.notice(for: report)
                // 账本更新了；采用了外面的个人词库、包换了新版本时，五笔词库页要重新读
                await wubiDict.reloadIfChanged(settings: draft)
            case .compileFailed(let errors):
                notice = Notice(kind: .error, title: "新配置编译不过，没有写入", lines: errors)
            case .externalChanges(let changes):
                if options.overwriteExternalChanges || changes.allSatisfy({ if case .outsideRimeDirectory = $0 { true } else { false } }) {
                    // 已经要求覆盖了还是不能写，或者只有覆盖也没用的改动：所在目录是指到 Rime 目录外面的链接
                    notice = Notice(kind: .error, title: "这些文件不能写，没有写入", lines: changes.map(\.description))
                } else if !wubiMergeOffered, changes == [.modified(wubiDict.rimeFileName)],
                          WubiCheck.checkSchema(in: settings, target: .jidian) != nil {
                    // 只有五笔个人词库在外面被改过：先建议按词条收进来（设计 4.4），两边的词都留下。
                    // 不收的话再点一次「应用改动」，按原来的外部改动流程问（覆盖 / 采用外面那份）
                    wubiMergeOffered = true
                    wubiDict.refresh()
                    notice = Notice(kind: .warning, title: "鼠须管目录里的五笔个人词库在应用外被改过",
                                    lines: ["可以先把外面加的词收进来再应用，两边的词都会留下",
                                            "不收的话，再点一次「应用改动」，可以选覆盖或者采用外面那份"],
                                    action: .mergeWubiDict, actionTitle: "把外面加的词收进来")
                } else {
                    let ledger = try Ledger.load(env.paths)
                    pendingPersonalChanges = changes.contains {
                        guard case .modified(let path) = $0 else { return false }
                        return ledger.entries[path]?.origin == FileOrigin.personal.ledgerValue
                    }
                    // 弹窗里要不要说「采用会换掉五笔词库页里没应用的改动」看这个，先更新
                    wubiDict.refresh()
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
        for spec in try settings.requiredPackages(catalog) {
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

    /// 取用到的包；下载失败时直接用本地旧版本，返回提醒。没有旧版本就抛错
    func packagesFallingBack(for settings: Settings) async throws -> ([String: CachedPackage], [String]) {
        var result: [String: CachedPackage] = [:]
        var notes: [String] = []
        for spec in try settings.requiredPackages(catalog) {
            working = "正在下载方案：\(spec.name)……"
            do {
                result[spec.id] = try await env.fetchPackage(spec)
            } catch where PackageStore.isDownloadFailure(error) {
                guard let old = env.cachedPackage(spec) else { throw error }
                notes.append("\(spec.name) 没下载成（\(error)），先用了本地以前下载的版本")
                result[spec.id] = old
            }
        }
        return (result, notes)
    }

    static func notice(for report: ApplyReport) -> Notice {
        var lines = ["写入 \(report.written.count) 个文件，没变 \(report.unchanged) 个，删掉 \(report.removed.count) 个"]
        lines += report.warnings
        if !report.deploy.finished {
            lines.append(report.deploy.notFinishedNote)
            return Notice(kind: .warning, title: report.deploy.notified ? "改动已经写入，但还没看到部署完成" : "改动已经写入，但没通知到鼠须管", lines: lines,
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
            await run(ApplyOptions(overwriteExternalChanges: true), usingCache: usingCache, onlySync: lastApply.onlySync)
        case .adoptPersonal:
            await run(ApplyOptions(overwriteExternalChanges: true, adoptPersonalChanges: true), usingCache: usingCache,
                      onlySync: lastApply.onlySync)
        }
    }

    /// 外部改动弹窗被关掉（按 Esc 等）：等于放弃这次改动，草稿留着
    public func dismissExternalChanges() {
        pendingExternalChanges = nil
    }

    /// 消息里的按钮
    public func perform(_ action: Notice.Action) async {
        notice = nil
        switch action {
        case .applyUsingCache:
            await run(lastApply.options, usingCache: true, onlySync: lastApply.onlySync)
        case .restore(let id):
            await restore(id)
        case .syncTextReplacement:
            await syncTextReplacement()
        case .mergeWubiDict:
            await mergeWubiDictAndApply()
        }
    }

    /// 消息里的「把外面加的词收进来」：收进来以后接着把刚才那次应用做完
    func mergeWubiDictAndApply() async {
        guard working == nil else {
            notice = Self.busyMergeNotice(working)
            return
        }
        if !wubiDict.availability.canEdit { await wubiDict.load(settings: draft) }
        guard await wubiDict.mergeExternal() else {
            notice = Notice(kind: .error, title: "没能把外面加的词收进来",
                            lines: [wubiDict.message ?? wubiDict.availability.message ?? "请到「五笔词库」页再试一次"])
            return
        }
        // 收的时候开始了别的事：这次先不应用，免得什么都没发生
        guard working == nil else {
            notice = Notice(kind: .info, title: "外面加的词已经收进来了", lines: ["等「\(working ?? "")」做完，再点「应用改动」"])
            return
        }
        await run(lastApply.options, usingCache: lastApply.usingCache, onlySync: lastApply.onlySync)
    }

    /// 正在忙别的事时点了「把外面加的词收进来」：留着按钮，等一下再点
    static func busyMergeNotice(_ working: String?) -> Notice {
        Notice(kind: .warning, title: "鼠须管目录里的五笔个人词库在应用外被改过",
               lines: ["正在做别的事（\(working ?? "")），做完再点一次"],
               action: .mergeWubiDict, actionTitle: "把外面加的词收进来")
    }

    // MARK: 还原（任务 5 补全备份列表）

    public func restore(_ id: String) async {
        guard working == nil else { return }
        working = "正在还原……"
        defer { working = nil }
        defer { loadBackups() }
        let deployer = env.deployer()
        do {
            let report = try await offMain { try await deployer.restore(id) }
            preview.markCurrentChanged()
            wubiDict.refresh()
            // 还原会清掉文本替换的同步记录：重新读设置；没应用的改动留着，只换同步记录
            if let now = try SettingsStore(paths: env.paths).load() {
                saved = now
                draft.textReplacement.lastSyncedHash = now.textReplacement.lastSyncedHash
                draft.textReplacement.syncedEntries = now.textReplacement.syncedEntries
            }
            var lines = ["还原前的状态也备份了：\(report.safetyBackup.id)",
                         "应用里的设置没有变；之后再「应用改动」会按应用里的设置重新写入"]
            lines += report.deploy.errors.map { "部署时有错误：\($0)" }
            lines += report.warnings   // rimectl 的说法在 Notice 里换掉
            notice = Notice(kind: report.deploy.errors.isEmpty ? .info : .warning,
                            title: "已还原到 \(report.restored.id)（\(report.restored.reason)）", lines: lines)
        } catch {
            notice = Notice(kind: .error, title: "没能还原", lines: ["\(error)"])
        }
    }

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

    /// 打开应用时检查一次文本替换（设计 6.5）：同步开着、有变化就问要不要同步。已经有消息时不打扰
    public func checkTextReplacementAtLaunch() async {
        guard saved.textReplacement.sync else { return }
        await checkTextReplacement()
        guard notice == nil, let status = textReplacementStatus, status.error == nil else { return }
        let line: String
        if let changes = status.changes {
            guard !changes.isEmpty else { return }
            line = "和上次同步比：新增 \(changes.added) 条，删掉 \(changes.removed) 条"
        } else {
            line = "文本替换还没同步过"
        }
        notice = Notice(kind: .info, title: "macOS 文本替换有变化", lines: [line, "要现在同步吗？只同步文本替换，别的设置不变。"],
                        action: .syncTextReplacement, actionTitle: "现在同步")
    }

    // MARK: 方案清单（在线方案清单设计 4.2）

    public func checkCatalog() async {
        guard working == nil else { return }
        working = "正在检查方案清单更新……"
        defer { working = nil }
        let store = env.catalogStore
        let inUse = saved
        switch await store.check(inUse: inUse) {
        case .upToDate:
            notice = Notice(kind: .info, title: "方案清单已经是最新的", lines: [])
        case .updated(let diff, let status):
            adoptCatalog(status)
            if diff.affectsInUse { catalogNeedsApply = true }
            notice = Notice(kind: .info, title: "方案清单更新了", lines: diff.lines)
        case .rejected(let reason):
            notice = Notice(kind: .warning, title: "没有用上新的方案清单", lines: [reason, "继续用现在的方案清单"])
        }
    }

    /// 换成新的方案清单；引导和主窗口共用一份
    func adoptCatalog(_ status: CatalogStatus) {
        env.catalogs.update(status)
        catalogStatus = status
        refreshColorSchemes()
    }

    // MARK: 导出（设计 6.3）

    public func export(to file: URL) async {
        guard working == nil else { return }
        working = includeUserDB ? "正在导出（输入法会暂停几秒）……" : "正在导出……"
        defer { working = nil }
        do {
            let versions = try saved.requiredPackages(catalog).compactMap { spec in
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
            let catalogStore = env.catalogStore
            let current = catalog
            let inUse = saved
            let opened = try await offMain {
                try await catalogStore.openArchive(file, catalog: current, inUse: inUse, into: work,
                                                   checking: { await MainActor.run { self.working = "正在更新方案清单……" } })
            }
            var catalogNote: [String] = []
            if let updated = opened.updated {
                adoptCatalog(updated)
                catalogNote = ["导出文件里有现在的方案清单不认识的方案，已经更新了方案清单"]
            }
            let archive = opened.archive
            let catalog = self.catalog
            let settings = archive.manifest.settings
            // 导入是一次性的：下载不了就直接用本地旧版本，结果里提醒（和第一次打开时的导入一样）
            let (packages, fallback) = try await packagesFallingBack(for: settings)
            var lines = catalogNote + archive.warnings + fallback
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
            lines += report.warnings
            switch report.outcome {
            case .applied(let applied):
                catalogNeedsApply = false
                preview.markCurrentChanged()
                if let note = reloadSettingsAfterImport() { lines.append(note) }
                refreshColorSchemes()
                await wubiDict.reloadIfChanged(settings: draft)
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

    /// 导入成功后重新读设置。读不了时返回提醒（导入本身已经成功）
    func reloadSettingsAfterImport() -> String? {
        do {
            if let now = try SettingsStore(paths: env.paths).load() {
                saved = now
                draft = now
            }
            return nil
        } catch {
            return "配置已经导入好了，但应用重新读设置时出错（\(error)）。请退出应用再打开"
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
}

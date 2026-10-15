import Foundation

public struct ImportReport: Sendable, Equatable {
    public let outcome: ApplyOutcome
    /// 导入前应用里原来的设置和个人内容另存的文件（原来没有设置时为 nil）
    public let previous: URL?
    /// 合并了哪些输入习惯
    public let mergedUserDB: [String]
    /// 输入习惯没合并上的原因（这时配置已经导入好了）
    public let userDBError: String?
    /// 不影响结果的提醒（例如最后重新启动鼠须管失败）
    public let warnings: [String]

    public init(outcome: ApplyOutcome, previous: URL?, mergedUserDB: [String], userDBError: String?, warnings: [String] = []) {
        self.outcome = outcome
        self.previous = previous
        self.mergedUserDB = mergedUserDB
        self.userDBError = userDBError
        self.warnings = warnings
    }
}

/// 一键导入（设计 6.4）：另存原来的设置 → 按 6.1 写入导出文件里的配置 → 合并输入习惯
public struct Importer: Sendable {
    let deployer: Deployer
    /// nil：不合并输入习惯
    let userDB: UserDBTransfer?
    let now: @Sendable () -> Date

    public init(deployer: Deployer, userDB: UserDBTransfer?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.deployer = deployer
        self.userDB = userDB
        self.now = now
    }

    public func run(_ archive: ImportArchive, catalog: Catalog, packages: [String: CachedPackage],
                    textReplacement: [Phrase]) async throws -> ImportReport {
        let paths = deployer.paths

        // 1. Rime 目录的备份不含应用里的设置和个人内容：原来有就先另存一份，导错了文件还能找回
        var previous: URL?
        if FileManager.default.fileExists(atPath: paths.settingsFile.path) {
            let file = Self.uniqueFile(in: paths.beforeImport, stamp: Self.stamp(now()))
            _ = try await Exporter(paths: paths, locations: deployer.locations, userDB: nil, now: now)
                .export(to: file, packages: [], overwrite: true)
            Self.pruneBeforeImport(paths.beforeImport, keep: 10, protecting: file)
            previous = file
        }

        // 2. 走 6.1。导入就是要换成导出文件里的配置：应用外的改动、同名文件都覆盖（先备份，永久保留）。
        //    写好后、通知鼠须管前保存设置和个人内容
        let imported = archive.manifest.settings
        let dicts = archive.personalDicts
        let phrases = archive.phrases
        let replacements = imported.textReplacement.sync ? textReplacement : []
        // 记下这次用的文本替换（同步关着时清掉记录）
        let settings = imported.recordingTextReplacement(replacements)
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: PersonalContent(dicts: dicts, phrases: phrases),
                                    textReplacementPhrases: replacements)
        // 应用还没管过 Rime 目录时（账本是空的），原来的配置不是应用写的：备份永久保留（设计 6.4）；
        // 已经由应用管理时，普通备份就够了，跟着最近 10 份轮换
        let firstTime = try Ledger.load(paths).entries.isEmpty
        let options = firstTime
            ? ApplyOptions(overwriteExternalChanges: true, permanentBackupReason: "导入前")
            : ApplyOptions(overwriteExternalChanges: true, backupReason: "导入前")
        let outcome: ApplyOutcome
        do {
            outcome = try await deployer.apply(
                input, options: options,
                afterWrite: { try AppDataWriter.replace(settings: settings, dicts: dicts, phrases: phrases, paths: paths) })
        } catch {
            // 出错时告诉用户原来的设置另存在哪里
            guard let previous else { throw error }
            throw TransferError.importFailed(String(describing: error), previous: previous.path)
        }

        // 3. 合并输入习惯（合并，不是覆盖）；合并不上不影响已经导入的配置
        guard case .applied(let applied) = outcome, let userDB, !archive.userDB.isEmpty else {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], userDBError: nil)
        }
        guard applied.deploy.finished else {
            // 合并要退出鼠须管：还在部署时不打断它
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [],
                                userDBError: "等了很久还没看到鼠须管部署完成，输入习惯先没合并。部署好以后再导入一次这个文件就行（配置不会重复）")
        }
        do {
            let merged = try await userDB.importAll(archive.userDB)
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: merged.names, userDBError: nil,
                                warnings: merged.warning.map { [$0] } ?? [])
        } catch {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], userDBError: String(describing: error))
        }
    }

    /// 同一秒导入两次时加后缀，不覆盖
    static func uniqueFile(in dir: URL, stamp: String) -> URL {
        var file = dir.appending(path: "\(stamp).zip")
        var n = 2
        while FileManager.default.fileExists(atPath: file.path) {
            file = dir.appending(path: "\(stamp)-\(n).zip")
            n += 1
        }
        return file
    }

    /// 另存的导入前文件只留最近 keep 个（按修改时间），刚写的这个一定留着
    static func pruneBeforeImport(_ dir: URL, keep: Int, protecting: URL) {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".zip") }) ?? []
        let dated = names.map { name -> (String, Date) in
            let date = (try? fm.attributesOfItem(atPath: dir.appending(path: name).path))?[.modificationDate] as? Date ?? .distantPast
            return (name, date)
        }.sorted { $0.1 > $1.1 }
        for (name, _) in dated.dropFirst(keep) where name != protecting.lastPathComponent {
            try? fm.removeItem(at: dir.appending(path: name))
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

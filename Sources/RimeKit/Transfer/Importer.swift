import Foundation

public struct ImportReport: Sendable, Equatable {
    public let outcome: ApplyOutcome
    /// 导入前应用里原来的设置和个人内容另存的文件（原来没有设置时为 nil）
    public let previous: URL?
    /// 合并了哪些输入习惯
    public let mergedUserDB: [String]
    /// 输入习惯没合并上的原因（这时配置已经导入好了）
    public let userDBError: String?
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
            let file = paths.beforeImport.appending(path: "\(Self.stamp(now())).zip")
            _ = try await Exporter(paths: paths, locations: deployer.locations, userDB: nil, now: now)
                .export(to: file, packages: [], overwrite: true)
            previous = file
        }

        // 2. 走 6.1。导入就是要换成导出文件里的配置：应用外的改动、同名文件都覆盖（先备份，永久保留）。
        //    写好后、通知鼠须管前保存设置和个人内容
        let settings = archive.manifest.settings
        let dicts = archive.personalDicts
        let phrases = archive.phrases
        let input = GenerationInput(settings: settings, catalog: catalog, packages: packages,
                                    personal: PersonalContent(dicts: dicts, phrases: phrases),
                                    textReplacementPhrases: settings.textReplacement.sync ? textReplacement : [])
        let outcome = try await deployer.apply(
            input, options: ApplyOptions(overwriteExternalChanges: true, permanentBackupReason: "导入前"),
            afterWrite: { try AppDataWriter.replace(settings: settings, dicts: dicts, phrases: phrases, paths: paths) })

        // 3. 合并输入习惯（合并，不是覆盖）；合并不上不影响已经导入的配置
        guard case .applied = outcome, let userDB, !archive.userDB.isEmpty else {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], userDBError: nil)
        }
        do {
            let merged = try await userDB.importAll(archive.userDB)
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: merged, userDBError: nil)
        } catch {
            return ImportReport(outcome: outcome, previous: previous, mergedUserDB: [], userDBError: String(describing: error))
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

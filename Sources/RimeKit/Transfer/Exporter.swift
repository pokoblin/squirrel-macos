import Foundation

public struct ExportReport: Sendable, Equatable {
    public let file: URL
    public let manifest: ExportManifest
    public let warnings: [String]
}

/// 一键导出（设计 6.3）：设置 + personal/ + 输入习惯快照（可选）→ 一个 zip。不放任何上游方案文件
public struct Exporter: Sendable {
    public let paths: AppPaths
    let locations: RimeLocations
    /// nil：不带输入习惯
    let userDB: UserDBTransfer?
    let now: @Sendable () -> Date

    public init(paths: AppPaths, locations: RimeLocations, userDB: UserDBTransfer?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.locations = locations
        self.userDB = userDB
        self.now = now
    }

    public func export(to target: URL, packages: [ExportManifest.Package], overwrite: Bool = false) async throws -> ExportReport {
        let fm = FileManager.default
        // 已经有东西时：只有普通文件才可以覆盖（目录、链接等一律不动，加 --force 也不行）
        if let type = (try? fm.attributesOfItem(atPath: target.path))?[.type] as? FileAttributeType {
            guard type == .typeRegular else { throw TransferError.targetNotAFile(target.path) }
            if !overwrite { throw TransferError.targetExists(target.path) }
        }
        // 和应用改动互斥：导出输入习惯时要退出鼠须管
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        guard let settings = try SettingsStore(paths: paths).load() else { throw TransferError.noSettings }
        let personal = try PersonalContent.load(from: paths)

        let work = paths.staging.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: work) }
        let content = work.appending(path: "content", directoryHint: .isDirectory)
        let dicts = content.appending(path: "personal/dicts", directoryHint: .isDirectory)
        try fm.createDirectory(at: dicts, withIntermediateDirectories: true)
        for url in personal.dicts {
            try fm.copyItem(at: url.resolvingSymlinksInPath(), to: dicts.appending(path: url.lastPathComponent))
        }
        if !personal.phrases.isEmpty {
            try Data((PhraseFile.header + PhraseFile.render(personal.phrases)).utf8)
                .write(to: content.appending(path: "personal/phrases.txt"))
        }

        var warnings: [String] = []
        let ledger = try Ledger.load(paths)
        let edited = ledger.externalChanges(in: locations.rimeDirectory).compactMap { change -> String? in
            guard case .modified(let path) = change, ledger.entries[path]?.origin == FileOrigin.personal.ledgerValue else { return nil }
            return path
        }
        if !edited.isEmpty {
            warnings.append("Rime 目录里的 \(edited.joined(separator: "、")) 在应用外改过，导出的是应用里保存的版本。要带上外面的修改，先运行 rimectl apply --adopt-personal")
        }

        let userDBResult = try await userDB?.exportAll(into: content.appending(path: "userdb", directoryHint: .isDirectory))
        let userDBNames = userDBResult?.names ?? []
        if let warning = userDBResult?.warning { warnings.append(warning) }
        let manifest = ExportManifest(formatVersion: ExportManifest.currentFormatVersion, exportedAt: now(), settings: settings.withoutTextReplacementRecord,
                                      packages: packages, personalDicts: personal.dicts.map(\.lastPathComponent),
                                      phrases: personal.phrases.count, userDB: userDBNames)
        try JSONCoding.encoder.encode(manifest).write(to: content.appending(path: "manifest.json"))

        let zip = work.appending(path: "export.zip")
        try Zipper().zip(content, to: zip)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: zip)   // 原子地换掉旧文件，不会先删
        } else {
            try fm.moveItem(at: zip, to: target)
        }
        return ExportReport(file: target, manifest: manifest, warnings: warnings)
    }
}

import Foundation

public struct BackupInfo: Sendable, Equatable, Codable {
    public let id: String
    public let createdAt: Date
    public let reason: String
    /// 永久保留，清理时不删（第一次应用前的那份）
    public let permanent: Bool
    public let files: [String]
    /// 备份时的 ledger，还原时一起恢复
    public let ledger: Ledger
}

public enum BackupError: Error, Equatable, Sendable, CustomStringConvertible {
    case notFound(String)
    case incomplete(String, missing: [String])

    public var description: String {
        switch self {
        case .notFound(let id): return "找不到备份 \(id)"
        case let .incomplete(id, missing):
            return "备份 \(id) 不完整，缺少 \(missing.count) 个文件（例如 \(missing[0])），没有还原"
        }
    }
}

/// ~/Library/Rime 配置文件的备份（设计第 7 节）。只备份配置文件，不备份 Rime 自己的运行文件。
public struct BackupStore: Sendable {
    public let paths: AppPaths
    let now: @Sendable () -> Date

    public init(paths: AppPaths, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.now = now
    }

    public func create(from rimeDirectory: URL, reason: String, permanent: Bool, ledger: Ledger) throws -> BackupInfo {
        let fm = FileManager.default
        let date = now()
        let id = Self.idFormatter.string(from: date) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
        let partial = paths.backups.appending(path: "\(id).partial", directoryHint: .isDirectory)
        let filesDir = partial.appending(path: "files", directoryHint: .isDirectory)
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
        let files = try RimeFiles.configFiles(in: rimeDirectory)
        for path in files {
            let target = filesDir.appending(path: path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: rimeDirectory.appending(path: path), to: target)
        }
        let info = BackupInfo(id: id, createdAt: date, reason: reason, permanent: permanent, files: files, ledger: ledger)
        try JSONCoding.encoder.encode(info).write(to: partial.appending(path: "meta.json"))
        try fm.moveItem(at: partial, to: paths.backups.appending(path: id, directoryHint: .isDirectory))
        // 从磁盘再读一次：JSON 里的时间只精确到秒，这样和以后读出来的一样
        return self.info(id) ?? info
    }

    /// 所有备份，新的在前
    public func list() -> [BackupInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: paths.backups.path)) ?? []
        return names.filter { !$0.hasSuffix(".partial") }
            .compactMap(info)
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func info(_ id: String) -> BackupInfo? {
        let meta = paths.backups.appending(path: id, directoryHint: .isDirectory).appending(path: "meta.json")
        guard let data = try? Data(contentsOf: meta) else { return nil }
        return try? JSONCoding.decoder.decode(BackupInfo.self, from: data)
    }

    /// 普通备份只留最近 keep 份；永久的都留。返回删掉的 id。
    public func prune(keep: Int = 10) throws -> [String] {
        let removable = list().filter { !$0.permanent }.dropFirst(keep).map(\.id)
        for id in removable {
            try FileManager.default.removeItem(at: paths.backups.appending(path: id, directoryHint: .isDirectory))
        }
        return removable
    }

    /// 把备份里的文件放回 Rime 目录。只删「备份里有的」和 managed（应用管理的）文件，
    /// 用户后来加的、应用不认识的文件不动；Rime 自己的运行文件也不动。
    /// 先确认备份里的文件都在，不全就什么都不动。
    public func restore(_ id: String, to rimeDirectory: URL, managed: Set<String>) throws -> BackupInfo {
        guard let info = info(id) else { throw BackupError.notFound(id) }
        let fm = FileManager.default
        let filesDir = paths.backups.appending(path: id, directoryHint: .isDirectory).appending(path: "files", directoryHint: .isDirectory)
        let missing = info.files.filter { (try? fm.attributesOfItem(atPath: filesDir.appending(path: $0).path)) == nil }
        guard missing.isEmpty else { throw BackupError.incomplete(id, missing: missing) }
        for path in Set(info.files).union(managed).sorted() where Ledger.exists(rimeDirectory.appending(path: path)) {
            try fm.removeItem(at: rimeDirectory.appending(path: path))
        }
        for path in info.files {
            let target = rimeDirectory.appending(path: path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: filesDir.appending(path: path), to: target)
        }
        return info
    }

    /// DateFormatter 不是 Sendable，每次用时新建一个
    static var idFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }
}

import Foundation

public struct LedgerEntry: Sendable, Equatable, Codable {
    public let sha256: String
    /// package:<包 id>、generated、personal
    public let origin: String

    public init(sha256: String, origin: String) {
        self.sha256 = sha256
        self.origin = origin
    }
}

public enum LedgerError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedFormat(Int)

    public var description: String {
        switch self {
        case .unsupportedFormat(let v):
            return "ledger.json 的格式版本是 \(v)，这个版本的应用只认识 \(Ledger.currentFormatVersion)，请更新应用"
        }
    }
}

/// 应用写进 ~/Library/Rime 的文件：相对路径 → 哈希、来源。用来发现外部改动、删掉不再需要的文件（设计第 5 节）。
public struct Ledger: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var appliedAt: Date?
    public var entries: [String: LedgerEntry]
    /// 这次应用时用的上游包：包 id → 版本（「检查更新」拿它和上游比）。0.2.1 以前写的账本没有这一项
    public var packages: [String: String]?
    /// 这次应用时手动短语的指纹（`PhraseFile.fingerprint`）。跟着账本备份、还原；0.2.1 以前写的账本没有这一项
    public var phrasesSHA256: String?

    public init(entries: [String: LedgerEntry] = [:], appliedAt: Date? = nil) {
        self.formatVersion = Self.currentFormatVersion
        self.entries = entries
        self.appliedAt = appliedAt
    }

    public static func load(_ paths: AppPaths) throws -> Ledger {
        guard FileManager.default.fileExists(atPath: paths.ledgerFile.path) else { return Ledger() }
        let data = try Data(contentsOf: paths.ledgerFile)
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONCoding.decoder.decode(Header.self, from: data)
        guard header.formatVersion == currentFormatVersion else { throw LedgerError.unsupportedFormat(header.formatVersion) }
        return try JSONCoding.decoder.decode(Ledger.self, from: data)
    }

    public func save(_ paths: AppPaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(self).write(to: paths.ledgerFile, options: .atomic)
    }

    /// 「外面改过的这份已经看过了」：只把已有条目的哈希改成 sha256，来源不变；账本里没有这个路径就不动
    public mutating func acknowledge(path: String, sha256: String) {
        guard let old = entries[path] else { return }
        entries[path] = LedgerEntry(sha256: sha256, origin: old.origin)
    }

    /// 应用写过的文件里，在应用外被改过或删掉的（按路径排序）
    public func externalChanges(in rimeDirectory: URL) -> [ExternalChange] {
        entries.keys.sorted().compactMap { path in
            let url = rimeDirectory.appending(path: path)
            guard Self.exists(url) else { return .deleted(path) }
            let current = try? Hashing.sha256(of: url)
            return current == entries[path]?.sha256 ? nil : .modified(path)
        }
    }

    /// 这次要写的文件里，应用之前没写过、但目录里已经有的（按路径排序）
    public func unmanagedOverwrites(_ newPaths: [String], in rimeDirectory: URL) -> [ExternalChange] {
        newPaths.sorted().compactMap { path in
            guard entries[path] == nil, Self.exists(rimeDirectory.appending(path: path)) else { return nil }
            return .unmanaged(path)
        }
    }

    /// 文件、目录、符号链接（包括指向不存在的链接）都算存在
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

public enum ExternalChange: Sendable, Equatable, CustomStringConvertible {
    case modified(String)
    case deleted(String)
    case unmanaged(String)
    /// 所在目录是指向 Rime 目录外面的符号链接，加 --overwrite 也不写
    case outsideRimeDirectory(String)

    public var path: String {
        switch self {
        case .modified(let p), .deleted(let p), .unmanaged(let p), .outsideRimeDirectory(let p): return p
        }
    }

    public var description: String {
        switch self {
        case .modified(let p): return "\(p)：在应用外被改过"
        case .deleted(let p): return "\(p)：在应用外被删了"
        case .unmanaged(let p): return "\(p)：不是应用写的，这次会被覆盖"
        case .outsideRimeDirectory(let p): return "\(p)：所在目录是指向 Rime 目录外面的链接，不能往里写（请先处理这个链接）"
        }
    }
}

extension FileOrigin {
    /// 写进 ledger 的来源
    public var ledgerValue: String {
        switch self {
        case .package(let id): return "package:\(id)"
        case .generated: return "generated"
        case .personal: return "personal"
        }
    }
}

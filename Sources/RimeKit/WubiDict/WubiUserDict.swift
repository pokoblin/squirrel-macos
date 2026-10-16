import Foundation

/// 五笔个人词库的存储（设计 4.4）：正本在 `personal/dicts/<个人词库>`，
/// 「应用改动」时才写进 Rime 目录。这里管起点、保存、有没有没应用的改动、外面改过的检测和合并
public struct WubiUserDict: Sendable {
    public let paths: AppPaths
    public let locations: RimeLocations
    public let target: WubiDictTarget

    public init(paths: AppPaths, locations: RimeLocations, target: WubiDictTarget = .jidian) {
        self.paths = paths
        self.locations = locations
        self.target = target
    }

    /// 正本：personal/dicts/<个人词库>
    public var personalFile: URL { paths.personalDicts.appending(path: target.userDict) }
    /// Rime 目录里那份（也是账本里的路径）
    public var rimeFile: URL { locations.rimeDirectory.appending(path: ledgerPath) }
    /// 在 Rime 目录里的相对路径：个人词库直接放在 Rime 目录顶层
    var ledgerPath: String { target.userDict }

    /// 读个人词库。personal 里还没有时按设计 4.4 定起点：
    /// Rime 目录里那份和包里的一样（或不存在）→ 包里的；不一样（在应用外手改过）→ Rime 目录里的。
    /// 只读不写：第一次保存时才在 personal 里生成文件
    public func load(package: CachedPackage) throws -> DictFile {
        let fm = FileManager.default
        if fm.fileExists(atPath: personalFile.path) {
            return try DictFile.parse(data: Data(contentsOf: personalFile))
        }
        let packageFile = package.filesDirectory.appending(path: target.userDict)
        let packageData = fm.fileExists(atPath: packageFile.path) ? try Data(contentsOf: packageFile) : nil
        if fm.fileExists(atPath: rimeFile.path) {
            let rimeData = try Data(contentsOf: rimeFile)
            if rimeData != packageData { return try DictFile.parse(data: rimeData) }
        }
        // 包里没有这个文件、Rime 目录里也没有时，这里会抛「文件不存在」
        return try DictFile.parse(data: packageData ?? Data(contentsOf: packageFile))
    }

    /// 写进 personal（先写同目录的临时文件再换过去，不会留下写了一半的文件）
    public func save(_ file: DictFile) throws {
        try FileManager.default.createDirectory(at: paths.personalDicts, withIntermediateDirectories: true)
        try Data(file.render().utf8).write(to: personalFile, options: .atomic)
    }

    /// 有没有还没应用的词库改动（计划细节 2）：personal 里有这个文件，且哈希和账本里这个路径记的不一样。
    /// 不另存状态，应用重启后也对
    public func needsApply() -> Bool {
        guard let current = try? Hashing.sha256(of: personalFile) else { return false }
        let ledger = try? Ledger.load(paths)
        return ledger?.entries[ledgerPath]?.sha256 != current
    }

    /// Rime 目录里的个人词库在应用外被改过：账本里有这个路径，文件还在，哈希和账本里的不一样。
    /// 文件被删了不算（没有可以收回的词，「应用改动」时按原来的外部改动流程处理）
    public func externalChange() -> Bool {
        guard let recorded = (try? Ledger.load(paths))?.entries[ledgerPath]?.sha256,
              let current = try? Hashing.sha256(of: rimeFile)
        else { return false }
        return current != recorded
    }

    /// 把 Rime 目录里那份有、`file` 里没有的词条按原来的顺序加在 `file` 末尾。
    /// 同词同码算同一条（权重不比）；外面那条没写编码时只比词；外面那条写了编码、这边同一个词没写编码的，要加进来
    /// （手写编码往往是因为自动编码不对）。外面删掉的词不跟着删。
    /// 返回值里带着合并时读到的那份的哈希，交给 `acknowledgeExternal(expectedSHA256:)`
    public func mergeExternal(into file: DictFile) throws -> MergeResult {
        let data = try Data(contentsOf: rimeFile)
        let outside = try DictFile.parse(data: data)
        var merged = file
        var keys = EntryKeys(file.entries)
        var added = 0
        for e in outside.entries where !keys.contains(e) {
            merged.append(e)
            keys.insert(e)
            added += 1
        }
        return MergeResult(merged: merged, added: added, sourceSHA256: Hashing.sha256(of: data))
    }

    /// 合并以后（计划细节 3）：在应用锁里把账本这个路径的哈希改成 Rime 目录里那份现在的哈希，
    /// 下次「应用改动」时它不再算外部改动，会被 personal 里合并后的版本覆盖。
    /// `expectedSHA256` 是合并时读到的那份的哈希：文件在这之后又被改了，就抛 `changedAgain`，不记账（要重新合并），
    /// 免得把没收进来的版本当成「看过了」，下次应用时把那些词覆盖掉
    public func acknowledgeExternal(expectedSHA256: String) throws {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let current = try Hashing.sha256(of: rimeFile)
        guard current == expectedSHA256 else { throw WubiUserDictError.changedAgain }
        var ledger = try Ledger.load(paths)
        ledger.acknowledge(path: ledgerPath, sha256: current)
        try ledger.save(paths)
    }
}

/// `mergeExternal` 的结果
public struct MergeResult: Sendable {
    public var merged: DictFile
    /// 加了几条
    public var added: Int
    /// 合并时读到的 Rime 目录里那份的哈希
    public var sourceSHA256: String
}

public enum WubiUserDictError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 合并以后，鼠须管目录里的个人词库又在应用外被改了
    case changedAgain

    public var description: String {
        switch self {
        case .changedAgain: return "鼠须管目录里的五笔个人词库刚才又被改了，请再收一次"
        }
    }
}

/// 合并时判断外面那条「已经有了」：同词同码算同一条；外面那条没写编码时只比词
private struct EntryKeys {
    struct Key: Hashable {
        let text: String
        let code: String
    }

    /// 有编码的词条：词 + 编码
    private var coded: Set<Key> = []
    /// 出现过的词（不管有没有编码）
    private var texts: Set<String> = []

    init(_ entries: [DictEntry]) {
        for e in entries { insert(e) }
    }

    mutating func insert(_ e: DictEntry) {
        texts.insert(e.text)
        if let code = e.code, !code.isEmpty {
            coded.insert(Key(text: e.text, code: code))
        }
    }

    func contains(_ e: DictEntry) -> Bool {
        guard let code = e.code, !code.isEmpty else { return texts.contains(e.text) }
        return coded.contains(Key(text: e.text, code: code))
    }
}

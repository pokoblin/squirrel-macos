import Foundation

/// 某个编码下的一个词
public struct IndexedWord: Sendable, Equatable {
    public var text: String
    /// 没写权重是 nil（排序时算 0，负数也算 0）
    public var weight: Int?
    /// 来自个人词库
    public var isPersonal: Bool

    public init(text: String, weight: Int?, isPersonal: Bool) {
        self.text = text
        self.weight = weight
        self.isPersonal = isPersonal
    }
}

/// 放在某个位置要写的权重
public enum WeightChoice: Equatable, Sendable {
    case weight(Int)
    /// 放最后：不写权重
    case noWeight
    /// 前后两个词的权重之间没有空档，放不进去（不改别人的权重）
    case noRoom
}

/// 编码 → 已有的词和权重（主词库加它导入的词库），顺序和 librime 编译出来的一样：
/// 先按权重从大到小（没写权重、负权重都算 0）；一样大时按读到的先后：主词库在前，导入表按 `import_tables` 的顺序，同一文件按行的顺序。
/// 同一个词、同一个编码出现多次时只算第一次读到的那条（librime 编译时也是这样）。
public struct WubiCodeIndex: Sendable {
    /// 一个词条和它读到的先后
    private struct Item: Sendable {
        var text: String
        var weight: Int?
        var isPersonal: Bool
        var order: Int
    }

    /// 每个编码下的所有词条（按读到的先后，没去重）
    private var byCode: [String: [Item]] = [:]

    /// imports：按读的先后排好的导入表；名字是 `personalTable` 的那个算个人词库
    public init(main: DictFile, imports: [(name: String, file: DictFile)],
                personalTable: String = WubiDictTarget.jidian.userTable) {
        var order = 0
        func add(_ file: DictFile, personal: Bool) {
            for e in file.entries {
                // 没写编码的词由 librime 编译时自己算，这里不知道编码，不进索引
                guard let code = e.code, !code.isEmpty else { continue }
                byCode[code, default: []].append(
                    Item(text: e.text, weight: e.weight, isPersonal: personal, order: order))
                order += 1
            }
        }
        add(main, personal: false)
        for t in imports { add(t.file, personal: t.name == personalTable) }
    }

    /// 排序时用的权重：没写和负数都算 0（实测 librime 就是这样，verified-facts 8.2）
    private static func effective(_ w: Int?) -> Int { max(w ?? 0, 0) }

    /// 这个编码下的词，按 librime 的顺序
    public func words(for code: String) -> [IndexedWord] {
        var seen = Set<String>()
        let unique = (byCode[code] ?? []).filter { seen.insert($0.text).inserted }
        return unique
            .sorted { a, b in
                let wa = Self.effective(a.weight), wb = Self.effective(b.weight)
                return wa != wb ? wa > wb : a.order < b.order
            }
            .map { IndexedWord(text: $0.text, weight: $0.weight, isPersonal: $0.isPersonal) }
    }

    /// 这个词、这个编码在个人词库里有没有，在别的词库里有没有
    public func contains(text: String, code: String) -> (inPersonal: Bool, inOthers: Bool) {
        let items = (byCode[code] ?? []).filter { $0.text == text }
        return (items.contains { $0.isPersonal }, items.contains { !$0.isPersonal })
    }

    /// 放在第 n 个（从 0 起）要写的权重。n ≥ 词数就是放最后。
    /// 放第一个前面：第一个的权重 + 10；放中间：前后两个的权重差 ≥ 2 时取中间（向下取整），否则放不进去；放最后：不写权重。
    /// excluding：改个人词库里已有的词的位置时，先把它自己从列表里去掉
    public func weight(forPosition n: Int, code: String, excluding: DictEntry? = nil) -> WeightChoice {
        var list = words(for: code)
        if let me = excluding, me.code == nil || me.code == code,
            let i = list.firstIndex(where: { $0.isPersonal && $0.text == me.text && $0.weight == me.weight }) {
            list.remove(at: i)
        }
        guard n < list.count else { return .noWeight }
        if n <= 0 { return .weight(Self.effective(list[0].weight) + 10) }
        let above = Self.effective(list[n - 1].weight)
        let below = Self.effective(list[n].weight)
        guard above - below >= 2 else { return .noRoom }
        return .weight(below + (above - below) / 2)
    }

    /// 从缓存包里读：主词库，加上它 `import_tables` 里列的词库。
    /// 只读主词库头部列的那一层：导入表自己的 `import_tables` librime 不读（实测，verified-facts 8.2），这里也不读。
    /// 个人词库用 personalUserDict（给了而且文件在的话），其他用包里的文件；包里没有的导入表跳过
    public static func load(from package: CachedPackage, personalUserDict: URL?,
                            target: WubiDictTarget) throws -> WubiCodeIndex {
        let dir = package.filesDirectory
        let main = try DictFile.parse(data: Data(contentsOf: dir.appending(path: target.mainDict)))
        let fm = FileManager.default

        var imports: [(name: String, file: DictFile)] = []
        var seen: Set<String> = [WubiDictTarget.tableName(target.mainDict)]
        for name in main.importTables where seen.insert(name).inserted {
            var url = dir.appending(path: name + ".dict.yaml")
            if name == target.userTable, let personalUserDict, fm.fileExists(atPath: personalUserDict.path) {
                url = personalUserDict
            }
            guard fm.fileExists(atPath: url.path) else { continue }
            imports.append((name: name, file: try DictFile.parse(data: Data(contentsOf: url))))
        }
        return WubiCodeIndex(main: main, imports: imports, personalTable: target.userTable)
    }
}

extension WubiCodeIndex {
    /// 主词库，和它 `import_tables` 里列的词库（和 `load` 读的一样）。
    /// 个人词库一定在里面（包里没有这个文件时是个空的），好让调用方换成自己手上的那份
    static func loadTables(from package: CachedPackage, target: WubiDictTarget) throws
        -> (main: DictFile, imports: [(name: String, file: DictFile)]) {
        let dir = package.filesDirectory
        let main = try DictFile.parse(data: Data(contentsOf: dir.appending(path: target.mainDict)))
        let fm = FileManager.default
        var imports: [(name: String, file: DictFile)] = []
        var seen: Set<String> = [WubiDictTarget.tableName(target.mainDict)]
        for name in main.importTables where seen.insert(name).inserted {
            let url = dir.appending(path: name + ".dict.yaml")
            if fm.fileExists(atPath: url.path) {
                imports.append((name: name, file: try DictFile.parse(data: Data(contentsOf: url))))
            } else if name == target.userTable {
                imports.append((name: name, file: try DictFile.parse("---\nname: \(name)\n...\n")))
            }
        }
        return (main, imports)
    }
}

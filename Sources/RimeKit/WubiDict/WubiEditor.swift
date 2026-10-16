import Foundation

/// 加词、删词、导入、检查时出的问题。`description` 是给人看的原话
public enum WubiEditProblem: Error, Equatable, Sendable, CustomStringConvertible {
    /// 词是空的，或者含制表符、换行（写进词库会弄坏那一行），或者以 # 开头（写进词库是注释行，打不出来）
    case invalidText
    /// 编码不是 1 到 4 个 a–y 的小写字母
    case invalidCode
    /// 有字算不出（不是汉字，或主词库里没有）
    case cannotEncode([Character])
    /// 这个长度没有组词规则
    case lengthUnsupported
    /// 一个字的词，编码要自己填
    case singleCharacterNeedsCode
    /// 主词库里没有组词规则，自动编码用不了
    case noEncoder
    /// 个人词库里已经有了
    case alreadyPersonal
    /// 主词库或别的导入词库里已经有了
    case alreadyInDict
    /// 这个位置前后的权重没有空档
    case noRoom
    /// 位置要从 1 起
    case invalidPosition
    /// 个人词库里没有这一条（序号不对，比如列表已经变了）
    case noSuchEntry

    public var description: String {
        switch self {
        case .invalidText: return "词不能是空的，不能含有制表符或换行，也不能以 # 开头"
        case .invalidCode: return "编码只能是 a–y 的小写字母，1 到 4 个"
        case .cannotEncode(let chars):
            return "算不出编码" + (chars.isEmpty ? "" : "（\(chars.map(String.init).joined(separator: "、"))）") + "，请自己填编码"
        case .lengthUnsupported: return "算不出编码，请自己填编码"
        case .singleCharacterNeedsCode: return "只有一个字的词要自己填编码"
        case .noEncoder: return "认不出这个版本的极点五笔词库，自动编码用不了"
        case .alreadyPersonal: return "已经加过了"
        case .alreadyInDict: return "词库里已经有了"
        case .noRoom: return "这个位置放不进去"
        case .invalidPosition: return "位置要从 1 起"
        case .noSuchEntry: return "个人词库里没有这个词了，请重新打开这一页"
        }
    }
}

/// 五笔个人词库的编辑逻辑（命令行和应用共用）：算编码、查重、算权重、找要删的词、检查用的输入。
/// 没写编码的个人词条按自动编码的第一个算（和「列出」里显示的「自动」一致），查重、排位置、检查都这样看。
/// 它只拿着一份当时的词库，不写文件；加了词用 `applying` 得到新的编辑器，写文件由调用方做。
public struct WubiEditor: Sendable {
    public let target: WubiDictTarget
    /// 主词库里没有组词规则时是 nil：自动编码用不了，仍可手填编码
    public let encoder: WubiEncoder?
    /// 现在的个人词库
    public let userFile: DictFile
    /// 编码索引：主词库、导入词库，个人词库用 `userFile`（没写编码的按自动编码算）
    public let index: WubiCodeIndex

    /// 主词库、导入词库的词条（读一次留着，换个人词库时不再拆文件）
    private let mainEntries: [DictEntry]
    private let importEntries: [(name: String, entries: [DictEntry])]
    /// userFile.entries（取一次留着：每次取都要把整个文件过一遍）
    private let userEntries: [DictEntry]
    /// userEntries 补上自动编码（算不出的还是没有）
    private let codedEntries: [DictEntry]

    public init(package: CachedPackage, userFile: DictFile, target: WubiDictTarget = .jidian) throws {
        let tables = try WubiCodeIndex.loadTables(from: package, target: target)
        self.init(encoder: try? WubiEncoder(mainDict: tables.main), mainEntries: tables.main.entries,
                  importEntries: tables.imports.map { (name: $0.name, entries: $0.file.entries) },
                  userFile: userFile, target: target)
    }

    /// 花的时间和词库大小成正比（个人词库的每个词条只看一遍）
    private init(encoder: WubiEncoder?, mainEntries: [DictEntry], importEntries: [(name: String, entries: [DictEntry])],
                 userFile: DictFile, target: WubiDictTarget) {
        self.target = target
        self.encoder = encoder
        self.mainEntries = mainEntries
        self.importEntries = importEntries
        self.userFile = userFile
        let entries = userFile.entries
        userEntries = entries
        let coded = Self.fill(entries, encoder: encoder)
        codedEntries = coded
        self.index = WubiCodeIndex(
            main: mainEntries,
            imports: importEntries.map { $0.name == target.userTable ? (name: $0.name, entries: coded) : $0 },
            personalTable: target.userTable)
    }

    private static func fill(_ entries: [DictEntry], encoder: WubiEncoder?) -> [DictEntry] {
        entries.map { e in
            var e = e
            if e.code?.isEmpty ?? true, let encoder, case .codes(let list) = encoder.encode(e.text) { e.code = list[0] }
            return e
        }
    }

    /// 自动算出的第一个编码；算不出是 nil
    public func autoCode(_ text: String) -> String? {
        guard let encoder, case .codes(let list) = encoder.encode(text) else { return nil }
        return list.first
    }

    /// 个人词库里的词条，没写编码的补上自动编码（算不出的还是没有）。检查时用这个
    public var entriesWithCodes: [DictEntry] { codedEntries }

    static func isValidText(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("#")
            && !text.contains { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }
    }

    /// 这个词可以用的编码：给了就用给的（要合法），没给就自动算（可能有好几个，第一个是默认）
    public func resolveCode(text: String, given: String?) -> Result<[String], WubiEditProblem> {
        guard Self.isValidText(text) else { return .failure(.invalidText) }
        if let given {
            return WubiEncoder.isValidCode(given) ? .success([given]) : .failure(.invalidCode)
        }
        guard let encoder else { return .failure(.noEncoder) }
        switch encoder.encode(text) {
        case .codes(let list): return .success(list)
        case .singleCharacter: return .failure(.singleCharacterNeedsCode)
        case .unknown(let chars): return .failure(chars.isEmpty ? .lengthUnsupported : .cannotEncode(chars))
        }
    }

    /// 要加的词条：查重（个人词库里的、主词库和导入词库里的），再按位置（从 1 起，nil 是最后）算权重
    public func plan(text: String, code: String, position: Int?) -> Result<DictEntry, WubiEditProblem> {
        guard Self.isValidText(text) else { return .failure(.invalidText) }
        guard WubiEncoder.isValidCode(code) else { return .failure(.invalidCode) }
        let found = index.contains(text: text, code: code)
        if found.inPersonal { return .failure(.alreadyPersonal) }
        if found.inOthers { return .failure(.alreadyInDict) }
        var weight: Int?
        if let position {
            guard position >= 1 else { return .failure(.invalidPosition) }
            switch index.weight(forPosition: position - 1, code: code) {
            case .weight(let w): weight = w
            case .noWeight: weight = nil
            case .noRoom: return .failure(.noRoom)
            }
        }
        return .success(DictEntry(text: text, code: code, weight: weight))
    }

    /// 把词条加在个人词库末尾，得到新的编辑器（索引跟着更新）
    public func applying(_ entries: [DictEntry]) -> WubiEditor {
        var file = userFile
        for e in entries { file.append(e) }
        return replacing(userFile: file)
    }

    /// 换成另一份个人词库（改了、删了、合并了以后），主词库和导入词库不重新读。
    /// 索引整个重建，花的时间和主词库大小成正比，别在主线程上做
    public func replacing(userFile file: DictFile) -> WubiEditor {
        WubiEditor(encoder: encoder, mainEntries: mainEntries, importEntries: importEntries, userFile: file, target: target)
    }

    /// 改个人词库里第 i 个词条（`userFile.entries` 里的序号）的编码和位置（从 1 起，nil 是最后）。
    /// 查重时不算它自己；编码、位置都没变时原样返回（权重不动）。返回的词条一定写着编码
    public func planUpdate(at i: Int, code: String, position: Int?) -> Result<DictEntry, WubiEditProblem> {
        let entries = userEntries
        guard entries.indices.contains(i) else { return .failure(.noSuchEntry) }
        guard WubiEncoder.isValidCode(code) else { return .failure(.invalidCode) }
        let old = entries[i]
        let coded = codedEntries
        if coded.indices.contains(where: { $0 != i && coded[$0].text == old.text && coded[$0].code == code }) {
            return .failure(.alreadyPersonal)
        }
        if index.contains(text: old.text, code: code).inOthers { return .failure(.alreadyInDict) }
        // 它自己现在的样子（没写编码的按自动编码）：算位置时先把它去掉
        let me = DictEntry(text: old.text, code: coded[i].code, weight: old.weight)
        if me.code == code, let position, position == self.position(of: me) {
            return .success(me)
        }
        var weight: Int?
        if let position {
            guard position >= 1 else { return .failure(.invalidPosition) }
            switch index.weight(forPosition: position - 1, code: code, excluding: me) {
            case .weight(let w): weight = w
            case .noWeight: weight = nil
            case .noRoom: return .failure(.noRoom)
            }
        }
        return .success(DictEntry(text: old.text, code: code, weight: weight))
    }

    /// 这个词条在它的编码下排第几（从 1 起），在 `applying` 之后的编辑器上问
    public func position(of entry: DictEntry) -> Int? {
        guard let code = entry.code, !code.isEmpty else { return nil }
        return index.words(for: code).firstIndex { $0.isPersonal && $0.text == entry.text }.map { $0 + 1 }
    }

    /// 要删的词条在 `userFile.entries` 里的序号：词一样，而且（没给编码，或者编码一样，没写编码的词条按自动编码比）
    public func removeMatches(text: String, code: String?) -> [Int] {
        let coded = codedEntries
        return userEntries.indices.filter { i in
            let e = userEntries[i]
            guard e.text == text else { return false }
            guard let code else { return true }
            return coded[i].code == code
        }
    }

    /// 删掉这些序号（`userFile.entries` 里的）的词条，其余行不动
    public static func remove(indices: [Int], from file: DictFile) -> DictFile {
        let doomed = Set(indices)
        var n = -1
        var out = file
        out.removeEntries { _ in
            n += 1
            return doomed.contains(n)
        }
        return out
    }

    /// 解析批量导入的文本。查重把没写编码的个人词条也算在内。
    /// 没有编码器时只是算不了编码：没写编码的行要手填，写了编码的行照样能加
    public func parseImport(_ text: String) -> [ImportRow] {
        WubiImport.parse(text, encoder: encoder, index: index)
    }
}

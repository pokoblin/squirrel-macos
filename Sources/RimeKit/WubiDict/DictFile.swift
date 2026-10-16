import Foundation
import Yams

/// 词库里的一个词条（一行）。`code`、`weight` 没写就是 nil
public struct DictEntry: Equatable, Sendable {
    public var text: String
    public var code: String?
    public var weight: Int?

    public init(text: String, code: String? = nil, weight: Int? = nil) {
        self.text = text
        self.code = code
        self.weight = weight
    }
}

public enum DictFileError: Error, Equatable, Sendable {
    /// 没有 `---` … `...` 头部（或头部读不懂）
    case noHeader
    /// 文件不是 UTF-8
    case notUTF8
}

/// Rime 的 `.dict.yaml`：头部（`---` 到 `...`）加正文。
/// 每一行都按原文存着：没改过的行渲染时逐字输出，词条、注释、空行、认不出的行都不会丢
public struct DictFile: Equatable, Sendable {
    /// 正文里的一行
    private enum Line: Equatable, Sendable {
        /// 注释、空行、认不出的行：原样保留
        case raw(String)
        /// 词条；`original` 是读进来的原文（没改过就原样输出），新加或改过的是 nil
        case entry(DictEntry, original: String?)
    }

    public private(set) var columns: [String]
    public private(set) var importTables: [String]
    public private(set) var sort: String?

    /// 头部原文：第一行到 `...` 那一行（含开头的注释），不含换行
    private var headerLines: [String]
    private var body: [Line]
    private var hasBOM: Bool
    private var eol: String
    private var endsWithNewline: Bool

    public static let defaultColumns = ["text", "code", "weight"]

    public var entries: [DictEntry] {
        body.compactMap { if case .entry(let e, _) = $0 { return e } else { return nil } }
    }

    // MARK: 读

    public static func parse(data: Data) throws -> DictFile {
        guard let s = String(data: data, encoding: .utf8) else { throw DictFileError.notUTF8 }
        return try parse(s)
    }

    public static func parse(_ text: String) throws -> DictFile {
        var text = text
        var bom = false
        if text.hasPrefix("\u{FEFF}") {
            bom = true
            text.removeFirst()
        }
        let eol = text.contains("\r\n") ? "\r\n" : "\n"
        var all = text.components(separatedBy: "\n")
        var endsWithNewline = false
        if all.last == "" {
            all.removeLast()
            endsWithNewline = true
        }
        // 去掉行尾的 \r（Windows 换行），渲染时再按 eol 补回
        if eol == "\r\n" {
            all = all.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        }

        guard let start = all.firstIndex(where: { isMarker($0, "---") }),
            let end = all[(start + 1)...].firstIndex(where: { isMarker($0, "...") })
        else { throw DictFileError.noHeader }

        let yaml = all[(start + 1)..<end].joined(separator: "\n")
        let parsed: [String: Any]
        do {
            parsed = (try Yams.load(yaml: yaml) as? [String: Any]) ?? [:]
        } catch {
            throw DictFileError.noHeader
        }
        let columns = (parsed["columns"] as? [Any])?.compactMap { $0 as? String } ?? defaultColumns
        let importTables = (parsed["import_tables"] as? [Any])?.compactMap { $0 as? String } ?? []
        let sort = parsed["sort"] as? String

        let layout = Layout(columns: columns)
        let body = all[(end + 1)...].map { layout.classify($0) }

        return DictFile(
            columns: columns, importTables: importTables, sort: sort,
            headerLines: Array(all[...end]), body: Array(body),
            hasBOM: bom, eol: eol, endsWithNewline: endsWithNewline)
    }

    private static func isMarker(_ line: String, _ marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == marker
    }

    // MARK: 写

    public func render() -> String {
        var lines = headerLines
        for l in body {
            switch l {
            case .raw(let s): lines.append(s)
            case .entry(let e, let original): lines.append(original ?? Layout(columns: columns).format(e))
            }
        }
        var out = lines.joined(separator: eol)
        if endsWithNewline { out += eol }
        return (hasBOM ? "\u{FEFF}" : "") + out
    }

    /// 加在文件末尾。原来末尾没有换行的，补上
    public mutating func append(_ e: DictEntry) {
        body.append(.entry(e, original: nil))
        endsWithNewline = true
    }

    /// 删掉满足条件的词条行，其余行不动
    public mutating func removeEntries(where shouldRemove: (DictEntry) -> Bool) {
        body.removeAll { line in
            if case .entry(let e, _) = line { return shouldRemove(e) }
            return false
        }
    }

    /// 把第 `index` 个词条（`entries` 里的序号）换成 `e`，只改那一行
    public mutating func replaceEntry(at index: Int, with e: DictEntry) {
        var n = 0
        for i in body.indices {
            guard case .entry(let old, let original) = body[i] else { continue }
            if n == index {
                // 内容没变就保留原文（比如带 stem 的行）
                body[i] = old == e ? .entry(old, original: original) : .entry(e, original: nil)
                return
            }
            n += 1
        }
    }

    // MARK: 列

    /// 按头部的 `columns` 拆行、拼行
    private struct Layout {
        let textIdx: Int?
        let codeIdx: Int?
        let weightIdx: Int?

        init(columns: [String]) {
            textIdx = columns.firstIndex(of: "text")
            codeIdx = columns.firstIndex(of: "code")
            weightIdx = columns.firstIndex(of: "weight")
        }

        func classify(_ line: String) -> Line {
            guard let textIdx, !line.isEmpty, !line.hasPrefix("#"),
                !line.trimmingCharacters(in: .whitespaces).isEmpty
            else { return .raw(line) }
            let fields = line.components(separatedBy: "\t")
            // 没有 Tab 又带空格的行（「奇怪 的行」）不认，原样保留
            if fields.count == 1 && line.contains(" ") { return .raw(line) }
            guard textIdx < fields.count, !fields[textIdx].isEmpty else { return .raw(line) }

            var code: String?
            if let codeIdx, codeIdx < fields.count, !fields[codeIdx].isEmpty { code = fields[codeIdx] }
            var weight: Int?
            if let weightIdx, weightIdx < fields.count, !fields[weightIdx].isEmpty {
                // 权重读不出来就整行原样保留，不去猜
                guard let w = Int(fields[weightIdx]) else { return .raw(line) }
                weight = w
            }
            return .entry(DictEntry(text: fields[textIdx], code: code, weight: weight), original: line)
        }

        func format(_ e: DictEntry) -> String {
            guard let textIdx else { return e.text }
            var cells: [Int: String] = [textIdx: e.text]
            if let codeIdx, let code = e.code { cells[codeIdx] = code }
            if let weightIdx, let w = e.weight { cells[weightIdx] = String(w) }
            let last = cells.keys.max() ?? 0
            return (0...last).map { cells[$0] ?? "" }.joined(separator: "\t")
        }
    }
}

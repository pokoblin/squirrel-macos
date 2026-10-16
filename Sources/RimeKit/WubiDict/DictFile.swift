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

    /// 头部原文：第一行到 `...` 那一行（含开头的注释）。每行自带的 `\r` 留在行尾，换行符 `\n` 不含
    private var headerLines: [String]
    private var body: [Line]
    private var hasBOM: Bool
    /// 新写的行用 CRLF 还是 LF（按原文里哪种多；没有已有的行时用 LF）
    private var crlf: Bool
    private var endsWithNewline: Bool

    /// 头部 `---` 和 `...` 之间的 YAML 原文（只读，给读 `encoder` 这类段用）
    public var headerYAML: String {
        guard let start = headerLines.firstIndex(where: { Self.isMarker($0, "---") }),
            let end = headerLines[(start + 1)...].firstIndex(where: { Self.isMarker($0, "...") })
        else { return "" }
        return headerLines[(start + 1)..<end].map(Self.stripCR).joined(separator: "\n")
    }

    public static let defaultColumns = ["text", "code", "weight"]

    public var entries: [DictEntry] {
        body.compactMap { if case .entry(let e, _) = $0 { return e } else { return nil } }
    }

    // MARK: 读

    public static func parse(data: Data) throws -> DictFile {
        // String(data:) 会吞掉开头的 BOM，所以先看字节
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let hasBOM = data.starts(with: bom)
        guard let s = String(data: hasBOM ? data.dropFirst(3) : data, encoding: .utf8)
        else { throw DictFileError.notUTF8 }
        return try parse((hasBOM ? "\u{FEFF}" : "") + s)
    }

    public static func parse(_ text: String) throws -> DictFile {
        var text = text
        var bom = false
        if text.hasPrefix("\u{FEFF}") {
            bom = true
            text.removeFirst()
        }
        var all = text.components(separatedBy: "\n")
        var endsWithNewline = false
        if all.last == "" {
            all.removeLast()
            endsWithNewline = true
        }
        // 每行自己的 \r 留在行尾原样保留（可能一个文件里 CRLF、LF 混着）；认行时再去掉
        let crCount = all.filter { $0.hasSuffix("\r") }.count
        let lfCount = all.count - crCount - (endsWithNewline ? 0 : 1)
        let crlf = crCount > lfCount

        guard let start = all.firstIndex(where: { isMarker($0, "---") }),
            let end = all[(start + 1)...].firstIndex(where: { isMarker($0, "...") })
        else { throw DictFileError.noHeader }

        let yaml = all[(start + 1)..<end].map(stripCR).joined(separator: "\n")
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
            hasBOM: bom, crlf: crlf, endsWithNewline: endsWithNewline)
    }

    private static func stripCR(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    private static func isMarker(_ line: String, _ marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == marker
    }

    // MARK: 写

    public func render() -> String {
        var lines = headerLines
        for l in body {
            switch l {
            case .raw(let s): lines.append(s)
            case .entry(let e, let original):
                lines.append(original ?? Layout(columns: columns).format(e) + (crlf ? "\r" : ""))
            }
        }
        var out = lines.joined(separator: "\n")
        if endsWithNewline { out += "\n" }
        return (hasBOM ? "\u{FEFF}" : "") + out
    }

    /// 加在文件末尾。原来末尾没有换行的，补上
    public mutating func append(_ e: DictEntry) {
        if !endsWithNewline && crlf {
            // 原来最后一行没有换行：补的换行跟文件多数行一样用 CRLF
            if let last = body.indices.last {
                switch body[last] {
                case .raw(let s): body[last] = .raw(s.hasSuffix("\r") ? s : s + "\r")
                case .entry(let old, let o):
                    body[last] = .entry(old, original: o.map { $0.hasSuffix("\r") ? $0 : $0 + "\r" })
                }
            } else if let last = headerLines.indices.last, !headerLines[last].hasSuffix("\r") {
                headerLines[last] += "\r"
            }
        }
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
                if old == e {
                    body[i] = .entry(old, original: original)
                } else if let original {
                    // 只改 text/code/weight 那几格，其余格（比如 stem）和行尾的换行原样留着
                    body[i] = .entry(e, original: Layout(columns: columns).update(original, with: e))
                } else {
                    body[i] = .entry(e, original: nil)
                }
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

        func classify(_ rawLine: String) -> Line {
            let line = DictFile.stripCR(rawLine)
            guard let textIdx, !line.isEmpty, !line.hasPrefix("#"),
                !line.trimmingCharacters(in: .whitespaces).isEmpty
            else { return .raw(rawLine) }
            let fields = line.components(separatedBy: "\t")
            // 没有 Tab 又带空格的行（「奇怪 的行」）不认，原样保留
            if fields.count == 1 && line.contains(" ") { return .raw(rawLine) }
            guard textIdx < fields.count, !fields[textIdx].isEmpty else { return .raw(rawLine) }

            var code: String?
            if let codeIdx, codeIdx < fields.count, !fields[codeIdx].isEmpty { code = fields[codeIdx] }
            var weight: Int?
            if let weightIdx, weightIdx < fields.count, !fields[weightIdx].isEmpty {
                // 权重读不出来就整行原样保留，不去猜
                guard let w = Int(fields[weightIdx]) else { return .raw(rawLine) }
                weight = w
            }
            return .entry(DictEntry(text: fields[textIdx], code: code, weight: weight), original: rawLine)
        }

        /// 在原来的行上只改 text/code/weight 对应的格，别的格不动
        func update(_ original: String, with e: DictEntry) -> String {
            let hasCR = original.hasSuffix("\r")
            var cells = DictFile.stripCR(original).components(separatedBy: "\t")
            func set(_ idx: Int?, _ value: String?) {
                guard let idx else { return }
                if idx >= cells.count {
                    guard let value, !value.isEmpty else { return }
                    cells += Array(repeating: "", count: idx - cells.count + 1)
                }
                cells[idx] = value ?? ""
            }
            set(textIdx, e.text)
            set(codeIdx, e.code)
            set(weightIdx, e.weight.map { String($0) })
            // 末尾空出来的格去掉（至少留到 text 那一格）
            let keep = (textIdx ?? 0) + 1
            while cells.count > keep, cells.last == "" { cells.removeLast() }
            return cells.joined(separator: "\t") + (hasCR ? "\r" : "")
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

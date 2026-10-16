import Foundation

/// 导入表里一行的状态
public enum ImportStatus: Equatable, Sendable {
    /// 可以加
    case ok
    /// 有多个可能的编码，默认第一个
    case choose
    /// 有字算不出编码、编码不合法、或者这一行写得不对（权重不是整数、段数不对）
    case needsCode
    /// 个人词库里已经有了
    case alreadyPersonal
    /// 主词库或别的导入词库里已经有了
    case alreadyInDict
    /// 和这次导入里前面的某一行重复
    case duplicateInBatch
}

/// 导入表里的一行
public struct ImportRow: Equatable, Sendable, Identifiable {
    /// 在输入文本里的行号（从 1 起）
    public var id: Int
    public var text: String
    /// 编码；算不出时是空串，不合法的编码按给的原样放着，方便用户改
    public var code: String
    /// 自动算出来的所有可能编码（给了编码的行是空）
    public var choices: [String]
    public var weight: Int?
    public var status: ImportStatus
    public var selected: Bool

    public init(id: Int, text: String, code: String, choices: [String], weight: Int?,
                status: ImportStatus, selected: Bool) {
        self.id = id
        self.text = text
        self.code = code
        self.choices = choices
        self.weight = weight
        self.status = status
        self.selected = selected
    }
}

/// 批量导入：把一段文本解析成一行行待加的词，并标出每行的状态。
/// 格式：`词`、`词 编码`、`词<Tab>编码<Tab>权重`；空行和 `#` 行跳过；`---`…`...` 之间的头部跳过。
public enum WubiImport {
    public static func parse(_ text: String, encoder: WubiEncoder, index: WubiCodeIndex) -> [ImportRow] {
        var scalars = Substring(text).unicodeScalars
        if scalars.first == "\u{FEFF}" { scalars = scalars.dropFirst() }
        let body = String(scalars)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = body.components(separatedBy: "\n")

        // 头部：有一行 `---` 后面又有一行 `...`，就跳到 `...` 之后
        var start = 0
        if let open = lines.firstIndex(where: { trimmed($0) == "---" }),
            let close = lines[(open + 1)...].firstIndex(where: { trimmed($0) == "..." }) {
            start = close + 1
        }

        var rows: [ImportRow] = []
        var seen = Set<String>()   // 这次导入里已经出现过的「词 + 编码」
        for lineIndex in start..<lines.count {
            let line = trailingTrimmed(lines[lineIndex])
            let lead = line.drop { $0.isWhitespace }
            if lead.isEmpty || lead.hasPrefix("#") { continue }
            guard let fields = split(line) else { continue }

            var status: ImportStatus = .ok
            var weight: Int?
            if let w = fields.weight {
                if let n = Int(w) { weight = n } else { status = .needsCode }
            }
            if fields.extra { status = .needsCode }

            var code = ""
            var choices: [String] = []
            if let given = fields.code {
                code = given
                if !WubiEncoder.isValidCode(given) { status = .needsCode }
            } else {
                switch encoder.encode(fields.text) {
                case .codes(let list):
                    code = list[0]
                    choices = list
                    if list.count > 1, status == .ok { status = .choose }
                case .unknown, .singleCharacter:
                    status = .needsCode
                }
            }

            // 重复、已有：比「需要编码」优先（编码不合法的行没法查已有，只看重复）
            if !seen.insert(fields.text + "\t" + code).inserted {
                status = .duplicateInBatch
            } else if WubiEncoder.isValidCode(code) {
                let found = index.contains(text: fields.text, code: code)
                if found.inPersonal {
                    status = .alreadyPersonal
                } else if found.inOthers {
                    status = .alreadyInDict
                }
            }

            rows.append(ImportRow(
                id: lineIndex + 1, text: fields.text, code: code, choices: choices, weight: weight,
                status: status, selected: status == .ok || status == .choose))
        }
        return rows
    }

    /// 选中的、编码合法的行，变成要加进个人词库的词条
    public static func entries(from rows: [ImportRow]) -> [DictEntry] {
        rows.filter { $0.selected && WubiEncoder.isValidCode($0.code) }
            .map { DictEntry(text: $0.text, code: $0.code, weight: $0.weight) }
    }

    // MARK: 拆行

    private struct Fields {
        var text: String
        var code: String?
        var weight: String?
        /// 空格拆出多余的段
        var extra = false
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    private static func trailingTrimmed(_ s: String) -> String {
        var end = s.endIndex
        while end > s.startIndex, s[s.index(before: end)].isWhitespace { end = s.index(before: end) }
        return String(s[..<end])
    }

    /// 有 Tab 就按 Tab 拆（词可以含空格；第四列起是词库的 stem 等，忽略）；
    /// 没有 Tab 就按连续的半角空格和全角空格（U+3000）拆
    private static func split(_ line: String) -> Fields? {
        if line.contains("\t") {
            let parts = line.components(separatedBy: "\t").map(trimmed)
            guard let text = parts.first, !text.isEmpty else { return nil }
            return Fields(
                text: text,
                code: parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil,
                weight: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil)
        }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
        guard let text = parts.first else { return nil }
        return Fields(
            text: text,
            code: parts.count > 1 ? parts[1] : nil,
            weight: parts.count > 2 ? parts[2] : nil,
            extra: parts.count > 3)
    }
}

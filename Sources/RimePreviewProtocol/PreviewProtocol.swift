import Foundation

// 试打预览的通信协议：应用和辅助程序（rime-preview-helper）之间，
// 一行一个 JSON，通过辅助程序的 stdin / stdout 来回。
// 这个 target 只依赖 Foundation，辅助程序也要用它，所以不能依赖 RimeKit。

/// 能发给 librime 的特殊键
public enum PreviewKey: String, Codable, CaseIterable, Sendable, Equatable {
    case backspace, escape, `return`, pageUp, pageDown, up, down

    /// X11 键码（librime 的 process_key 用的）
    public var keysym: Int32 {
        switch self {
        case .backspace: 0xff08
        case .escape: 0xff1b
        case .return: 0xff0d
        case .pageUp: 0xff55
        case .pageDown: 0xff56
        case .up: 0xff52
        case .down: 0xff54
        }
    }
}

/// 应用发给辅助程序的请求。编码成 {"op":"open",…}、{"op":"input","text":…} 这样
public enum PreviewRequest: Codable, Sendable, Equatable {
    case open(userDir: String, schema: String)
    case input(String)
    case key(PreviewKey)
    case select(Int)
    case clear
    /// 查开关（比如繁简转换 zh_trad）现在开着没有
    case option(String)
    /// 本页第几个候选是不是对应整段输入（选了它以后不剩编码）。不改正在打的东西
    case covers(Int)

    private enum CodingKeys: String, CodingKey {
        case op, userDir, schema, text, name, index
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(String.self, forKey: .op)
        switch op {
        case "open":
            self = .open(userDir: try c.decode(String.self, forKey: .userDir), schema: try c.decode(String.self, forKey: .schema))
        case "input":
            self = .input(try c.decode(String.self, forKey: .text))
        case "key":
            self = .key(try c.decode(PreviewKey.self, forKey: .name))
        case "select":
            self = .select(try c.decode(Int.self, forKey: .index))
        case "clear":
            self = .clear
        case "option":
            self = .option(try c.decode(String.self, forKey: .name))
        case "covers":
            self = .covers(try c.decode(Int.self, forKey: .index))
        default:
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "不认识的 op：\(op)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .open(userDir, schema):
            try c.encode("open", forKey: .op)
            try c.encode(userDir, forKey: .userDir)
            try c.encode(schema, forKey: .schema)
        case let .input(text):
            try c.encode("input", forKey: .op)
            try c.encode(text, forKey: .text)
        case let .key(key):
            try c.encode("key", forKey: .op)
            try c.encode(key, forKey: .name)
        case let .select(index):
            try c.encode("select", forKey: .op)
            try c.encode(index, forKey: .index)
        case .clear:
            try c.encode("clear", forKey: .op)
        case let .option(name):
            try c.encode("option", forKey: .op)
            try c.encode(name, forKey: .name)
        case let .covers(index):
            try c.encode("covers", forKey: .op)
            try c.encode(index, forKey: .index)
        }
    }
}

public struct PreviewCandidate: Codable, Sendable, Equatable {
    public var text: String
    public var comment: String

    public init(text: String, comment: String) {
        self.text = text
        self.comment = comment
    }
}

/// 一次请求之后输入法的样子
public struct PreviewState: Codable, Sendable, Equatable {
    /// 这次请求上屏的文字（没有就是 nil）
    public var committed: String?
    public var preedit: String
    public var cursor: Int
    public var candidates: [PreviewCandidate]
    public var labels: [String]?
    public var pageNo: Int
    public var isLastPage: Bool
    public var highlighted: Int
    /// librime 的原始输入（preedit 里有分隔符、拼音的空格，这个没有）
    public var input: String
    /// 候选对应整段输入（不是只管前面一段）
    public var wholeInput: Bool

    public init(
        committed: String? = nil, preedit: String = "", cursor: Int = 0,
        candidates: [PreviewCandidate] = [], labels: [String]? = nil,
        pageNo: Int = 0, isLastPage: Bool = true, highlighted: Int = 0,
        input: String = "", wholeInput: Bool = false
    ) {
        self.committed = committed
        self.preedit = preedit
        self.cursor = cursor
        self.candidates = candidates
        self.labels = labels
        self.pageNo = pageNo
        self.isLastPage = isLastPage
        self.highlighted = highlighted
        self.input = input
        self.wholeInput = wholeInput
    }

    private enum CodingKeys: String, CodingKey {
        case committed, preedit, cursor, candidates, labels, pageNo, isLastPage, highlighted, input, wholeInput
    }

    /// input、wholeInput 是后加的，没有时用默认值
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        committed = try c.decodeIfPresent(String.self, forKey: .committed)
        preedit = try c.decode(String.self, forKey: .preedit)
        cursor = try c.decode(Int.self, forKey: .cursor)
        candidates = try c.decode([PreviewCandidate].self, forKey: .candidates)
        labels = try c.decodeIfPresent([String].self, forKey: .labels)
        pageNo = try c.decode(Int.self, forKey: .pageNo)
        isLastPage = try c.decode(Bool.self, forKey: .isLastPage)
        highlighted = try c.decode(Int.self, forKey: .highlighted)
        input = try c.decodeIfPresent(String.self, forKey: .input) ?? ""
        wholeInput = try c.decodeIfPresent(Bool.self, forKey: .wholeInput) ?? false
    }

    /// 什么都没有输入时的样子
    public static let empty = PreviewState()
}

public enum PreviewFailureKind: String, Codable, Sendable, Equatable {
    case loadFailed, unsupportedVersion, refusedDirectory, schemaMissing, notOpen, badRequest
}

public struct PreviewFailure: Codable, Sendable, Equatable {
    public var kind: PreviewFailureKind
    public var message: String

    public init(kind: PreviewFailureKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// 辅助程序回给应用的结果
public struct PreviewResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var librimeVersion: String?
    public var state: PreviewState?
    public var error: PreviewFailure?
    /// 查开关的结果（只有 option 请求才有）
    public var option: Bool?
    /// 候选是不是对应整段输入（只有 covers 请求才有）
    public var covers: Bool?

    public init(ok: Bool, librimeVersion: String? = nil, state: PreviewState? = nil, error: PreviewFailure? = nil,
                option: Bool? = nil, covers: Bool? = nil) {
        self.ok = ok
        self.librimeVersion = librimeVersion
        self.state = state
        self.error = error
        self.option = option
        self.covers = covers
    }

    public static func success(_ state: PreviewState, librimeVersion: String? = nil) -> PreviewResponse {
        PreviewResponse(ok: true, librimeVersion: librimeVersion, state: state)
    }

    public static func failure(_ kind: PreviewFailureKind, _ message: String) -> PreviewResponse {
        PreviewResponse(ok: false, error: PreviewFailure(kind: kind, message: message))
    }
}

/// 一行 JSON 的编码和解码
public enum PreviewLine {
    /// 编码成一行 JSON，结尾带 "\n"；不转义 "/"。JSON 字符串里的换行会被转义，所以不会出现第二行
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0a)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: some StringProtocol) throws -> T {
        try JSONDecoder().decode(type, from: Data(String(line).utf8))
    }
}

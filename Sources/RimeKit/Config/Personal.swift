import Foundation

/// 一条自定义短语：打 code 时，text 排在候选第一位
public struct Phrase: Sendable, Equatable, Codable {
    public var text: String
    public var code: String
    public var weight: Int?

    public init(text: String, code: String, weight: Int?) {
        self.text = text
        self.code = code
        self.weight = weight
    }

    /// 能不能写进短语文件：短语和编码都不能空、不能含换行和 Tab，短语不能以 # 开头（会被当成注释）
    public var isValid: Bool {
        let bad: (Character) -> Bool = { $0 == "\t" || $0.isNewline }
        return !text.isEmpty && !code.isEmpty && !text.hasPrefix("#")
            && !text.contains(where: bad) && !code.contains(where: bad)
    }

    /// Rime 短语文件里的一行：短语<Tab>编码[<Tab>权重]
    public var line: String {
        weight.map { "\(text)\t\(code)\t\($0)" } ?? "\(text)\t\(code)"
    }
}

/// custom_phrase.txt 这类短语文件的读写
public enum PhraseFile {
    public static let header = """
    # Rime table
    # coding: utf-8
    # 由\(AppInfo.name)（squirrel-macos）生成的自定义短语。格式：短语<Tab>编码<Tab>权重

    """

    /// 跳过空行、注释和格式不对的行
    public static func parse(_ text: String) -> [Phrase] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw)
            if line.hasPrefix("#") { return nil }
            let fields = line.components(separatedBy: "\t")
            guard fields.count >= 2, !fields[0].isEmpty, !fields[1].isEmpty else { return nil }
            let weight = fields.count >= 3 ? Int(fields[2]) : nil
            return Phrase(text: fields[0], code: fields[1], weight: weight)
        }
    }

    public static func render(_ phrases: [Phrase]) -> String {
        phrases.map { $0.line + "\n" }.joined()
    }

    /// 短语内容的指纹（应用时记进账本，用来判断手动短语改了没应用）：只看短语，不看文件头和注释
    public static func fingerprint(_ phrases: [Phrase]) -> String {
        Hashing.sha256(of: Data(render(phrases).utf8))
    }
}

/// 个人内容的正本（personal/ 目录）：个人词库和手动短语
public struct PersonalContent: Sendable, Equatable {
    /// personal/dicts/ 下的 *.dict.yaml，按文件名排序
    public var dicts: [URL]
    /// personal/phrases.txt 里的手动短语
    public var phrases: [Phrase]

    public init(dicts: [URL], phrases: [Phrase]) {
        self.dicts = dicts
        self.phrases = phrases
    }

    public static let empty = PersonalContent(dicts: [], phrases: [])

    public static func load(from paths: AppPaths) throws -> PersonalContent {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: paths.personalDicts.path)) ?? []
        let dicts = names.filter { $0.hasSuffix(".dict.yaml") }.sorted()
            .map { paths.personalDicts.appending(path: $0) }
        var phrases: [Phrase] = []
        if fm.fileExists(atPath: paths.personalPhrases.path) {
            phrases = PhraseFile.parse(try TextFile.read(paths.personalPhrases))
        }
        return PersonalContent(dicts: dicts, phrases: phrases)
    }

    /// 有没有叫这个名字的个人词库（文件名是 <名字>.dict.yaml）
    public func hasDict(named name: String) -> Bool {
        dicts.contains { $0.lastPathComponent == "\(name).dict.yaml" }
    }
}

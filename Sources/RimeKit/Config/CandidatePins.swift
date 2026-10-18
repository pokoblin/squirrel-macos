import Foundation
import Yams

/// 候选置顶：把某个编码下已有的候选写成手动短语，打这个编码时它排第一（规格：候选置顶设计）
public enum CandidatePins {
    /// 置顶：先去掉同编码的旧条目（一个编码只置顶一个），再把新的一条加在末尾。
    /// 返回新列表和被替换掉的条目
    public static func pinning(text: String, code: String, in phrases: [Phrase]) -> (phrases: [Phrase], replaced: [Phrase]) {
        let replaced = phrases.filter { $0.code == code }
        let kept = phrases.filter { $0.code != code }
        return (kept + [Phrase(text: text, code: code, weight: nil)], replaced)
    }

    /// 还原：只去掉这一条
    public static func removing(_ phrase: Phrase, from phrases: [Phrase]) -> [Phrase] {
        phrases.filter { $0 != phrase }
    }
}

public enum PhraseFileError: Error, Equatable, Sendable, CustomStringConvertible {
    case unreadable(String)

    public var description: String {
        switch self {
        case .unreadable(let reason): return "读不了 personal/phrases.txt：\(reason)"
        }
    }
}

/// personal/phrases.txt（手动短语的正本）的读写。改了马上写进去，「应用改动」时才进 Rime 目录
public struct PersonalPhraseStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    /// 没有文件时是空的
    public func load() throws -> [Phrase] {
        guard FileManager.default.fileExists(atPath: paths.personalPhrases.path) else { return [] }
        return PhraseFile.parse(try TextFile.read(paths.personalPhrases))
    }

    /// 拿着应用锁写（正在应用改动时抛 `ApplyError.busy`）。空列表删掉文件；注释行不保留
    public func save(_ phrases: [Phrase]) throws {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        try write(phrases)
    }

    /// 拿着应用锁读最新的文件、改、写回去：应用外改过的内容不会被盖掉。
    /// 读不了时抛 `PhraseFileError.unreadable`，不写
    public func update(_ change: ([Phrase]) -> [Phrase]) throws {
        let lock = try ApplyLock.acquire(paths)
        defer { withExtendedLifetime(lock) {} }
        let current: [Phrase]
        do {
            current = try load()
        } catch {
            throw PhraseFileError.unreadable(String(describing: error))
        }
        try write(change(current))
    }

    private func write(_ phrases: [Phrase]) throws {
        let fm = FileManager.default
        if phrases.isEmpty {
            if fm.fileExists(atPath: paths.personalPhrases.path) { try fm.removeItem(at: paths.personalPhrases) }
            return
        }
        try fm.createDirectory(at: paths.personal, withIntermediateDirectories: true)
        try Data((PhraseFile.header + PhraseFile.render(phrases)).utf8).write(to: paths.personalPhrases, options: .atomic)
    }

    /// 手动短语和上次应用时不一样。账本里没有记录时当作上次没有手动短语；读不了文件时不算
    public func needsApply() -> Bool {
        guard let phrases = try? load() else { return false }
        let recorded = (try? Ledger.load(paths))?.phrasesSHA256 ?? PhraseFile.fingerprint([])
        return PhraseFile.fingerprint(phrases) != recorded
    }
}

/// 这个方案里为什么整个不能置顶（候选置顶设计 5.4 第 7、8 条）
public enum PinBlock: Equatable, Sendable {
    /// 繁简转换开着：拿到的候选已经转过，写进去会让别的方案也出转换后的字
    case conversion
    /// 方案自带短语翻译器（雾凇这类）：置顶不一定排第一
    case ownPhrases

    public var message: String {
        switch self {
        case .conversion: return "繁体方案里不能置顶，请换到简体方案再置顶"
        case .ownPhrases: return "这个方案自带短语，置顶暂时只支持极点五笔这类方案"
        }
    }
}

extension PinBlock {
    /// 方案原文件里有短语翻译器 → 自带短语；编译后的方案里有简繁过滤器、它的开关开着 → 繁简转换。
    /// userDir 是试打副本（里面有 build/）。读不了文件、查不了开关时当作可以置顶
    public static func check(schema: String, userDir: URL, option: (String) async throws -> Bool) async -> PinBlock? {
        func yaml(_ path: String) -> Node? {
            (try? TextFile.read(userDir.appending(path: path))).flatMap { try? YAMLNode.parse($0) }
        }
        let source = yaml("\(schema).schema.yaml")
        let translators = source?["engine"]?["translators"]?.sequence?.compactMap(\.string) ?? []
        if translators.contains("table_translator@custom_phrase") { return .ownPhrases }
        guard let compiled = yaml("build/\(schema).schema.yaml") else { return nil }
        for filter in compiled["engine"]?["filters"]?.sequence?.compactMap(\.string) ?? [] {
            guard filter == "simplifier" || filter.hasPrefix("simplifier@") else { continue }
            let section = filter == "simplifier" ? "simplifier" : String(filter.dropFirst("simplifier@".count))
            let name = compiled[section]?["option_name"]?.string ?? "simplification"
            if (try? await option(name)) == true { return .conversion }
        }
        return nil
    }
}

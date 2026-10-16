import Foundation

/// 一个词在引擎里打出来的结果。page、index 从 0 起，界面显示时加 1
public enum CheckResult: Equatable, Sendable {
    /// 排在预期的位置
    case asExpected(page: Int, index: Int)
    /// 能打出来，但不在预期的位置（比如被别的词挤后了）
    case elsewhere(page: Int, index: Int)
    /// 看了 5 页也没找到，或者没有编码可打
    case missing
}

/// 检查加进去的词能不能真的打出来：在应用后的样子的副本上，用 librime 试打
public enum WubiCheck {
    /// 最多看几页
    static let maxPages = 5

    /// 打开方案一次，逐个词试打。
    /// 预期位置 = 这个词在 `index.words(for: code)` 里的序号；实际位置（跨页的总序号）一样就是 asExpected。
    /// 词不在索引里（比如索引是旧的）算 elsewhere。没有编码的词算 missing。
    /// 结果和 entries 一一对应
    public static func run(
        _ entries: [DictEntry], index: WubiCodeIndex, engine: any PreviewEngine,
        userDir: URL, schema: String
    ) async throws -> [CheckResult] {
        _ = try await engine.open(userDir: userDir, schema: schema)
        var results: [CheckResult] = []
        for entry in entries {
            guard let code = entry.code, !code.isEmpty else {
                results.append(.missing)
                continue
            }
            guard let match = try await PreviewProbe.find(
                entry.text, code: code, maxPages: maxPages, in: engine)
            else {
                results.append(.missing)
                continue
            }
            let expected = index.words(for: code).firstIndex { $0.text == entry.text }
            results.append(match.overall == expected
                ? .asExpected(page: match.page, index: match.index)
                : .elsewhere(page: match.page, index: match.index))
        }
        return results
    }

    /// 检查用哪个方案：已启用的方案里第一个以 target.schemaPrefix 开头、且不是简入繁出的。
    /// 简入繁出方案（id 以 `_trad` 结尾或含 `_trad_`）会把简体词转成繁体，检查会把简体词报成打不出来，
    /// 所以只在没有别的极点方案时才用它
    public static func checkSchema(in settings: Settings, target: WubiDictTarget) -> String? {
        let candidates = settings.schemas.filter { $0.hasPrefix(target.schemaPrefix) }
        return candidates.first { !($0.hasSuffix("_trad") || $0.contains("_trad_")) }
            ?? candidates.first
    }
}

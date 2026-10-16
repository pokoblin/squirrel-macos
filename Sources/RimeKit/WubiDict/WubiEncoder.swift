import Foundation
import Yams

/// 一个词的五笔编码算出来是什么样
public enum WubiEncoding: Equatable, Sendable {
    /// 至少一个，第一个是默认
    case codes([String])
    /// 主词库里没有的字，或者不是汉字的字符（空数组：每个字都认识，但这个长度没有组词规则，或空串）
    case unknown([Character])
    /// 一个字的词，编码要手填
    case singleCharacter
}

public enum WubiEncoderError: Error, Equatable, Sendable {
    /// 主词库头部没有 `encoder/rules`（认不出这个版本的极点五笔词库）
    case noRules
}

/// 按主词库头部 `encoder` 段里的组词规则，给词算五笔编码。
/// 规则、单字编码、排除规则都从词库里读，不写死。
public struct WubiEncoder: Sendable {
    private struct Rule: Sendable {
        let lengths: ClosedRange<Int>
        let formula: [(char: Character, code: Character)]
    }

    private let rules: [Rule]
    /// 字 → 全码（最长的那些，不含被排除的，按主词库里出现的先后）
    private let fullCodes: [Character: [String]]

    public init(mainDict: DictFile) throws {
        let header = (try? Yams.load(yaml: mainDict.headerYAML)) as? [String: Any]
        let encoder = header?["encoder"] as? [String: Any]
        var rules: [Rule] = []
        for item in (encoder?["rules"] as? [Any]) ?? [] {
            guard let r = item as? [String: Any], let formula = r["formula"] as? String else { continue }
            let range: ClosedRange<Int>
            if let n = r["length_equal"] as? Int {
                range = n...n
            } else if let pair = r["length_in_range"] as? [Any], pair.count == 2,
                let lo = pair[0] as? Int, let hi = pair[1] as? Int, lo <= hi {
                range = lo...hi
            } else {
                continue
            }
            // 公式是「大写字母 + 小写字母」一对一对的
            let letters = Array(formula)
            guard letters.count % 2 == 0, !letters.isEmpty else { continue }
            var pairs: [(Character, Character)] = []
            var valid = true
            for i in stride(from: 0, to: letters.count, by: 2) {
                let upper = letters[i], lower = letters[i + 1]
                guard upper.isASCII, upper.isUppercase, lower.isASCII, lower.isLowercase else {
                    valid = false
                    break
                }
                pairs.append((upper, lower))
            }
            if valid { rules.append(Rule(lengths: range, formula: pairs)) }
        }
        guard !rules.isEmpty else { throw WubiEncoderError.noRules }
        self.rules = rules

        let excludes = ((encoder?["exclude_patterns"] as? [Any]) ?? [])
            .compactMap { ($0 as? String).flatMap { try? NSRegularExpression(pattern: $0) } }
        func excluded(_ code: String) -> Bool {
            let range = NSRange(code.startIndex..., in: code)
            return excludes.contains { $0.firstMatch(in: code, range: range) != nil }
        }

        // 单字：按出现顺序收集编码，去掉被排除的，只留最长的那些
        var all: [Character: [String]] = [:]
        for e in mainDict.entries {
            guard e.text.count == 1, let ch = e.text.first, let code = e.code, !excluded(code) else { continue }
            if all[ch]?.contains(code) != true { all[ch, default: []].append(code) }
        }
        fullCodes = all.mapValues { codes in
            let longest = codes.map(\.count).max() ?? 0
            return codes.filter { $0.count == longest }
        }
    }

    public func encode(_ word: String) -> WubiEncoding {
        let chars = Array(word)
        if chars.count == 1 { return .singleCharacter }

        // 先挑出认不出的字（不是汉字的、主词库里没有的），去重、保持顺序
        var unknown: [Character] = []
        for ch in chars where !(Self.isHan(ch) && fullCodes[ch] != nil) && !unknown.contains(ch) {
            unknown.append(ch)
        }
        guard unknown.isEmpty, !chars.isEmpty else { return .unknown(unknown) }

        guard let rule = rules.first(where: { $0.lengths.contains(chars.count) }) else { return .unknown([]) }
        // 公式里用到的字（按字序），每个字的全码有几个就展开几种，前面的字在外层
        var indexes: [Int] = []
        for (upper, _) in rule.formula {
            guard let idx = Self.charIndex(upper, count: chars.count) else { return .unknown([]) }
            if !indexes.contains(idx) { indexes.append(idx) }
        }
        indexes.sort()
        var combos: [[Int: String]] = [[:]]
        for idx in indexes {
            let codes = fullCodes[chars[idx]] ?? []
            combos = combos.flatMap { combo in
                codes.map { code in combo.merging([idx: code]) { _, new in new } }
            }
        }

        var result: [String] = []
        for combo in combos {
            var code = ""
            for (upper, lower) in rule.formula {
                guard let idx = Self.charIndex(upper, count: chars.count), let full = combo[idx] else { continue }
                let letters = Array(full)
                // 码不够长的那一码不取
                if let i = Self.codeIndex(lower, count: letters.count) { code.append(letters[i]) }
            }
            if !code.isEmpty, !result.contains(code) { result.append(code) }
        }
        return result.isEmpty ? .unknown([]) : .codes(result)
    }

    /// 手填的编码：1 到 4 个小写字母 a–y
    public static func isValidCode(_ code: String) -> Bool {
        guard (1...4).contains(code.utf8.count) else { return false }
        return code.utf8.allSatisfy { (UInt8(ascii: "a")...UInt8(ascii: "y")).contains($0) }
    }

    /// 汉字：只有一个 Unicode 标量，且是表意文字
    static func isHan(_ ch: Character) -> Bool {
        ch.unicodeScalars.count == 1 && ch.unicodeScalars.first?.properties.isIdeographic == true
    }

    /// 公式里的大写字母是第几个字：A 起是第 1 个，`Z` 最后一个，`Y` 倒数第二
    private static func charIndex(_ letter: Character, count: Int) -> Int? {
        guard let a = letter.asciiValue else { return nil }
        let idx: Int
        switch letter {
        case "Z": idx = count - 1
        case "Y": idx = count - 2
        default: idx = Int(a) - Int(UInt8(ascii: "A"))
        }
        return (0..<count).contains(idx) ? idx : nil
    }

    /// 公式里的小写字母是编码里的第几码：`z` 最后一码，`y` 倒数第二；码不够长就是 nil（这一码不取）
    private static func codeIndex(_ letter: Character, count: Int) -> Int? {
        guard let a = letter.asciiValue else { return nil }
        let idx: Int
        switch letter {
        case "z": idx = count - 1
        case "y": idx = count - 2
        default: idx = Int(a) - Int(UInt8(ascii: "a"))
        }
        return (0..<count).contains(idx) ? idx : nil
    }
}

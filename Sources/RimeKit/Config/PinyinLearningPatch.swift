import Foundation
import Yams

/// 混输记词：把混输方案里的拼音反查换成会记住用户凑出的词的拼音翻译器，
/// 再用一个 Lua 过滤器给拼音打出的单字补上五笔编码（反查原来会显示，换掉以后没了）。
/// 设计：ai_docs/specs/2026-11-12-mixed-pinyin-learning-design.md
enum PinyinLearningPatch {
    static let namespace = "mixed_pinyin"
    static let translator = "script_translator@\(namespace)"
    static let replaced = "reverse_lookup_translator"
    static let replacedTag = "reverse_lookup"

    static func module(_ codeDictionary: String) -> String { "code_hint_\(codeDictionary)" }
    static func luaPath(_ codeDictionary: String) -> String { "lua/\(module(codeDictionary)).lua" }
    static func filter(_ codeDictionary: String) -> String { "lua_filter@*\(module(codeDictionary))" }

    /// 根据上游方案的 YAML 算补丁项；上游 engine/translators 里没有 reverse_lookup_translator 时返回 nil
    static func entries(_ learning: PinyinLearning, upstreamSchema root: Node) -> [Patch.Entry]? {
        let translators = root["engine"]?["translators"]?.sequence?.compactMap(\.string) ?? []
        guard translators.contains(replaced) else { return nil }
        // 上游能用前缀（繁体混输是「`」）强制打拼音时，反查翻译器留着只接前缀开头的输入：
        // 不带前缀的输入不再加 reverse_lookup 标签，交给记词的拼音翻译器
        let extraTags = root["abc_segmentor"]?["extra_tags"]?.sequence?.compactMap(\.string) ?? []
        let keepPrefix = !(root["reverse_lookup"]?["prefix"]?.string ?? "").isEmpty
        var result = [
            Patch.Entry(key: "engine/translators",
                        value: YAMLNode.list(translators.flatMap { name -> [Node] in
                            guard name == replaced else { return [YAMLNode.text(name)] }
                            return keepPrefix ? [YAMLNode.text(translator), YAMLNode.text(replaced)] : [YAMLNode.text(translator)]
                        })),
            Patch.Entry(key: namespace, value: YAMLNode.map([
                ("dictionary", YAMLNode.text(learning.dictionary)),
                ("prism", YAMLNode.text(learning.dictionary)),
                ("enable_user_dict", YAMLNode.bool(true)),
                ("enable_completion", YAMLNode.bool(true)),
                ("initial_quality", YAMLNode.int(learning.initialQuality)),
            ])),
        ]
        if keepPrefix, extraTags.contains(replacedTag) {
            result.append(Patch.Entry(key: "abc_segmentor/extra_tags",
                                      value: YAMLNode.list(extraTags.filter { $0 != replacedTag }.map(YAMLNode.text))))
        }
        let hint = YAMLNode.text(filter(learning.codeDictionary))
        // 上游有过滤器时插在最前面：简入繁出的 simplifier 后面查到的是繁体字，查不到五笔编码
        if let filters = root["engine"]?["filters"]?.sequence, !filters.isEmpty {
            result.append(Patch.Entry(key: "engine/filters/@before 0", value: hint))
        } else {
            result.append(Patch.Entry(key: "engine/filters", value: YAMLNode.list([hint])))
        }
        return result
    }

    static func luaScript(codeDictionary: String) -> String {
        """
        -- \(Patch.header.dropFirst(2).dropLast())
        -- 混输里拼音打出的单字后面显示五笔编码；五笔自己的候选不加
        local M = {}
        local wubi = { table = true, completion = true, user_table = true }
        function M.init(env) env.db = ReverseLookup("\(codeDictionary)") end
        function M.func(input, env)
          for cand in input:iter() do
            if not wubi[cand.type] and utf8.len(cand.text) == 1 and cand.comment == "" then
              local code = env.db:lookup(cand.text)
              if code ~= "" then cand.comment = code end
            end
            yield(cand)
          end
        end
        return M

        """
    }

    /// 这一项是不是生成器写的记词补丁（patch 是磁盘上整份补丁）。
    /// 按特征认，不要求和这一版算出来的一样：旧版本的清单或上游方案生成的也要认出来，
    /// 否则会被当成用户的补丁保留，以后切回自带词库时留下指向不存在的翻译器、脚本的配置
    static func isGenerated(_ entry: Patch.Entry, in patch: Patch) -> Bool {
        guard patch.entries.contains(where: { isNamespace($0.key) }) else { return false }
        let key = entry.key
        if isNamespace(key) { return true }
        if key == "engine/translators" || key.hasPrefix("engine/translators/") {
            return names(entry.value).contains(translator)
        }
        if key == "engine/filters" || key.hasPrefix("engine/filters/") {
            return names(entry.value).contains { $0.hasPrefix("lua_filter@*code_hint_") }
        }
        if key == "abc_segmentor/extra_tags" { return !names(entry.value).contains(replacedTag) }
        return false
    }

    /// 和这一版算出来的补丁（expected）一样。engine/filters 整份替换、值是 expected 的列表再加一个
    /// uniquifier（有手动短语时生成器加的去重）也算
    static func matches(_ entry: Patch.Entry, expected: Patch) -> Bool {
        guard let want = expected[entry.key] else { return false }
        if YAMLNode.same(entry.value, want) { return true }
        if entry.key == "engine/filters", let list = want.sequence {
            return YAMLNode.same(entry.value, YAMLNode.list(Array(list) + [YAMLNode.text("uniquifier")]))
        }
        return false
    }

    static func isNamespace(_ key: String) -> Bool { key == namespace || key.hasPrefix(namespace + "/") }

    static func names(_ node: Node) -> [String] {
        if let text = node.string { return [text] }
        return node.sequence?.compactMap(\.string) ?? []
    }
}

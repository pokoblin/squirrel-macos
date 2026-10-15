import Foundation
@testable import RimeKit

/// 按作者的五笔配置（docs/reference-wubi-profile.md）造一个脱敏的样本 Rime 目录：
/// 上游文件 + 同样的改法；个人词库和短语都是编的
enum WubiSample {
    static let manualPhrase = Phrase(text: "手动短语样本", code: "sdzd", weight: 1)
    /// 和测试机里加过的文本替换一样（tstx → 测试短语）
    static let textReplacement = Phrase(text: "测试短语", code: "tstx", weight: 1)
    static let pinyinWord = (text: "鼠须管样本词", code: "shu xu guan yang ben ci")
    static let wubiWord = (text: "五笔样本词", code: "tgtg")

    struct UpstreamChanged: Error, CustomStringConvertible {
        let description: String
    }

    /// 替换并检查次数：上游文件变了就报错，不会悄悄造出一个没改过的样本
    static func replace(_ text: String, _ old: String, _ new: String, count: Int) throws -> String {
        let found = text.components(separatedBy: old).count - 1
        guard found == count else {
            throw UpstreamChanged(description: "上游文件变了，造样本时「\(old)」找到 \(found) 处，应该是 \(count) 处")
        }
        return text.replacingOccurrences(of: old, with: new)
    }

    static func build(wubi: CachedPackage, dicts: CachedPackage, into rime: URL) throws {
        func put(_ text: String, _ path: String) throws {
            let url = rime.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func upstream(_ package: CachedPackage, _ path: String) throws -> String {
            try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8)
        }
        for package in [wubi, dicts] {
            for path in package.info.files where !GenerationContext.isUpstreamPatch(path) && path != "LICENSE" {
                try put(try upstream(package, path), path)
            }
        }

        var defaults = try upstream(wubi, "default.custom.yaml")
        defaults = try replace(defaults,
            "    - schema: wubi86_jidian             # 五笔\n    - schema: numbers                   # 大写数字\n    - schema: wubi86_jidian_pinyin      # 五笔拼音混输\n",
            "    - schema: wubi86_jidian_pinyin      # 五笔拼音混输\n    - schema: wubi86_jidian             # 五笔\n    - schema: numbers                   # 大写数字\n",
            count: 1)
        defaults = try replace(defaults, "#      - { when: has_menu, accept: minus, send: Page_Up }",
                               "      - { when: has_menu, accept: minus, send: Page_Up }", count: 1)
        defaults = try replace(defaults, "#      - { when: has_menu, accept: equal, send: Page_Down }",
                               "      - { when: has_menu, accept: equal, send: Page_Down }", count: 1)
        try put(defaults, "default.custom.yaml")
        try put(defaults, "default.custom.yaml.bak")   // 作者目录里有这样的备份文件：应该原样保留

        var squirrel = try upstream(wubi, "squirrel.custom.yaml")
        squirrel = try replace(squirrel, "      font_point: 18", "      font_point: 24", count: 2)
        squirrel = try replace(squirrel, "      label_font_point: 17", "      label_font_point: 20", count: 2)
        squirrel = try replace(squirrel, "      comment_font_point: 16", "      comment_font_point: 20", count: 2)
        try put(squirrel, "squirrel.custom.yaml")

        try put("""
            ---
            name: pinyin_ext
            version: "2026-10-14"
            sort: by_weight
            import_tables:
              - pinyin_user
              - cn_dicts/8105
              - cn_dicts/base
              - cn_dicts/ext
            ...

            """, "pinyin_ext.dict.yaml")
        try put("---\nname: pinyin_user\nversion: \"1\"\nsort: by_weight\n...\n\(pinyinWord.text)\t\(pinyinWord.code)\t100\n",
                "pinyin_user.dict.yaml")
        var user = try upstream(wubi, "wubi86_jidian_user.dict.yaml")
        if !user.hasSuffix("\n") { user += "\n" }
        try put(user + "\(wubiWord.text)\t\(wubiWord.code)\n", "wubi86_jidian_user.dict.yaml")

        let phrase = """
              "engine/translators/@before 0": table_translator@custom_phrase
              custom_phrase:
                dictionary: ""
                user_dict: custom_phrase
                db_class: stabledb
                enable_completion: false
                enable_sentence: false
                initial_quality: 100

            """
        try put("patch:\n  translator/dictionary: pinyin_ext\n" + phrase, "pinyin_simp.custom.yaml")
        for schema in ["wubi86_jidian", "wubi86_jidian_pinyin", "wubi86_jidian_trad", "wubi86_jidian_trad_pinyin"] {
            try put("patch:\n  reverse_lookup/dictionary: pinyin_ext\n" + phrase, "\(schema).custom.yaml")
        }
        try put(PhraseFile.header + PhraseFile.render([textReplacement, manualPhrase]), "custom_phrase.txt")
        try put("patch:\n  style/font_point: 20\n", "weasel.custom.yaml")   // 小狼毫用的，应该原样保留
    }
}

import Foundation
@testable import RimeKit

/// 接管测试用的样本：用 GenFixtures 的三个自造包，照作者五笔配置的写法改（整段改写上游补丁）
enum TakeoverFixtures {
    struct Env {
        let dir: TempDir
        let rime: URL
        let catalog: Catalog
        let packages: [String: CachedPackage]
    }

    static func env() throws -> Env {
        let dir = try TempDir()
        return Env(dir: dir, rime: dir.url.appending(path: "Rime", directoryHint: .isDirectory),
                   catalog: try GenFixtures.catalog(),
                   packages: try GenFixtures.makePackages(in: dir.url.appending(path: "packages", directoryHint: .isDirectory)))
    }

    static func analyze(_ e: Env, textReplacement: [Phrase] = [fromTR]) throws -> TakeoverProposal {
        let survey = try TakeoverSurvey.scan(e.rime, catalog: e.catalog)
        return try TakeoverAnalyzer.analyze(e.rime, catalog: e.catalog, survey: survey, packages: e.packages,
                                            textReplacement: textReplacement)
    }

    static let manual = Phrase(text: "私人短语", code: "srdy", weight: 1)
    static let fromTR = Phrase(text: "替换短语", code: "thdy", weight: 1)

    static func put(_ text: String, _ path: String, in dir: URL) throws {
        let url = dir.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// 包里的某个文件的内容
    static func upstream(_ id: String, _ path: String) -> String {
        GenFixtures.files[id]![path]!
    }

    /// 把包里的文件（不含上游补丁和 LICENSE）放进 Rime 目录，模拟用户照着上游说明装好的配置
    static func install(_ ids: [String], from packages: [String: CachedPackage], into rime: URL) throws {
        for id in ids {
            let package = packages[id]!
            for path in package.info.files where !GenerationContext.isUpstreamPatch(path) && path != "LICENSE" {
                try put(try String(contentsOf: package.filesDirectory.appending(path: path), encoding: .utf8), path, in: rime)
            }
        }
    }

    /// 上游 default.custom.yaml 改了方案顺序、多了一个翻页键
    static let wubiDefault = """
        patch:
          schema_list:
            - schema: wb_py
            - schema: wb
          menu:
            page_size: 5
          key_binder:
            bindings:
              - { when: has_menu, accept: bracketleft, send: Page_Up }
              - { when: has_menu, accept: minus, send: Page_Up }

        """

    /// 上游 squirrel.custom.yaml 改了字号：候选字浅色深色都是 24，序号只有浅色配色里有，改成 20
    static let wubiSquirrel = """
        patch:
          style:
            color_scheme: roseo
            color_scheme_dark: roseo_dark
          preset_color_schemes:
            roseo:
              name: 玫枫
              font_point: 24
              label_font_point: 20
            roseo_dark:
              name: 玫枫暗
              font_point: 24

        """

    /// 和应用注入的一样的短语翻译器补丁
    static let phraseInjection = """
          "engine/translators/@before 0": table_translator@custom_phrase
          custom_phrase:
            dictionary: ""
            user_dict: custom_phrase
            db_class: stabledb
            enable_completion: false
            enable_sentence: false
            initial_quality: 100

        """

    /// 五笔 + 大词库 + 两个个人词库 + 短语 + 两个应用不认识的文件
    static func wubiSample(_ packages: [String: CachedPackage], into rime: URL) throws {
        try install(["wubi", "words"], from: packages, into: rime)
        try put(wubiDefault, "default.custom.yaml", in: rime)
        try put(wubiSquirrel, "squirrel.custom.yaml", in: rime)
        try put("patch:\n  translator/dictionary: py_ext\n", "wpy.custom.yaml", in: rime)
        try put("patch:\n  reverse_lookup/dictionary: py_ext\n" + phraseInjection, "wb.custom.yaml", in: rime)
        try put("patch:\n  reverse_lookup/dictionary: py_ext\n" + phraseInjection, "wb_py.custom.yaml", in: rime)
        try put("---\nname: py_ext\nversion: \"1\"\nsort: by_weight\nimport_tables:\n  - py_user\n  - cn/a\n...\n",
                "py_ext.dict.yaml", in: rime)
        try put(GenFixtures.dict("py_user", ["私人词条\tsi ren ci tiao\t100"]), "py_user.dict.yaml", in: rime)
        try put(GenFixtures.dict("wb_user", ["私人五笔词\taaaa"]), "wb_user.dict.yaml", in: rime)
        try put(PhraseFile.header + PhraseFile.render([fromTR, manual]), "custom_phrase.txt", in: rime)
        try put("patch:\n  style/font_point: 20\n", "weasel.custom.yaml", in: rime)
        try put("随手记的东西\n", "notes.txt", in: rime)
        try put("var: {}\n", "user.yaml", in: rime)
    }
}

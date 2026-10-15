import Foundation
import Testing
@testable import RimeKit

@Suite struct TakeoverAnalyzerTests {
    typealias F = TakeoverFixtures

    @Test func 手写的五笔配置() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb_py", "wb"])
        #expect(p.settings.options == ["wubi": ["pinyinDictionary": "ext"]])
        #expect(p.settings.appearance == Appearance(fontPoint: 24, labelFontPoint: 20))
        #expect(p.settings.textReplacement == TextReplacementSettings(sync: true))
        #expect(p.settings.preservedPatches.keys.sorted() == ["default"])
        let bindings = try #require(p.settings.preservedPatches["default"]?.first)
        #expect(p.settings.preservedPatches["default"]?.count == 1)
        #expect(bindings.key == "key_binder/bindings")
        #expect(bindings.yaml.contains("minus"))
        #expect(p.personalDicts.map(\.lastPathComponent) == ["py_user.dict.yaml", "wb_user.dict.yaml"])
        #expect(p.manualPhrases == [F.manual])
        #expect(p.textReplacementMatches == 1)
        #expect(p.notes.isEmpty, "\(p.notes)")
    }

    @Test func 没有文本替换时短语都是手动的() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let p = try F.analyze(e, textReplacement: [])
        #expect(p.manualPhrases == [F.fromTR, F.manual])
        #expect(p.textReplacementMatches == 0)
        #expect(p.settings.textReplacement == TextReplacementSettings(sync: false))
    }

    @Test func 没有选项补丁时是自带词库() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb", "wb_py"])
        #expect(p.settings.options == ["wubi": ["pinyinDictionary": "builtin"]])
        #expect(p.settings.appearance == Appearance())
        #expect(p.settings.preservedPatches.isEmpty)
        #expect(p.personalDicts.isEmpty)
        #expect(p.notes.isEmpty, "\(p.notes)")
    }

    @Test func 只认出一部分选项补丁时提示_认不出的原样保留() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        try F.put("patch:\n  translator/dictionary: py_ext\n", "wpy.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.options == ["wubi": ["pinyinDictionary": "builtin"]])
        #expect(p.notes.contains { $0.contains("只认出一部分") })
        #expect(p.settings.preservedPatches["wpy"]?.map(\.key) == ["translator/dictionary"])
    }

    @Test func 深色字号和浅色不一样时用浅色的() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        try F.put(F.upstream("wubi", "squirrel.custom.yaml")
                    .replacingOccurrences(of: "      font_point: 18\n      label_font_point: 17", with: "      font_point: 24\n      label_font_point: 17")
                    .replacingOccurrences(of: "      name: 玫枫暗\n      font_point: 18", with: "      name: 玫枫暗\n      font_point: 22"),
                  "squirrel.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.appearance == Appearance(fontPoint: 24))
        #expect(p.notes.contains { $0.contains("深色") && $0.contains("font_point") })
        #expect(p.settings.preservedPatches.isEmpty)
    }

    @Test func 自己写的简短default补丁会提示上游默认项() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put("patch:\n  schema_list:\n    - schema: wb\n", "default.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb"])
        #expect(p.notes.contains { $0.contains("default.custom.yaml") && $0.contains("key_binder/bindings") })
        #expect(p.settings.preservedPatches["default"] == nil)
    }

    @Test func 和默认无关的整段补丁原样保留_含外观键的整段拆开() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["pinyin"], from: e.packages, into: e.rime)
        try F.put("patch:\n  schema_list:\n    - schema: py\n", "default.custom.yaml", in: e.rime)
        try F.put("""
            patch:
              style:
                font_point: 20
                corner_radius: 5
              app_options:
                com.example.app:
                  ascii_mode: true

            """, "squirrel.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.appearance == Appearance(fontPoint: 20))
        #expect(p.settings.preservedPatches["squirrel"]?.map(\.key) == ["app_options", "style/corner_radius"])
        #expect(p.notes.isEmpty, "\(p.notes)")
    }

    @Test func 每页候选数和上游默认不一样才写进设置() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml").replacingOccurrences(of: "page_size: 5", with: "page_size: 7"),
                  "default.custom.yaml", in: e.rime)
        #expect(try F.analyze(e).settings.appearance == Appearance(pageSize: 7))
    }

    @Test func 认不出的方案会提示() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)
        try F.put(F.upstream("wubi", "default.custom.yaml").replacingOccurrences(of: "    - schema: wb_py\n", with: "    - schema: wb_py\n    - schema: luna_pinyin\n"),
                  "default.custom.yaml", in: e.rime)
        let p = try F.analyze(e)
        #expect(p.settings.schemas == ["wb", "wb_py"])
        #expect(p.notes.contains { $0.contains("luna_pinyin") })
    }

    @Test func 一个方案都认不出() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.put("随手记\n", "notes.txt", in: e.rime)
        #expect(throws: TakeoverError.nothingRecognized) { try F.analyze(e) }
    }

    @Test func 用户改过的上游个人词库模板才算个人词库() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.install(["wubi"], from: e.packages, into: e.rime)   // wb_user.dict.yaml 和上游一样
        try F.put(F.upstream("wubi", "default.custom.yaml"), "default.custom.yaml", in: e.rime)
        #expect(try F.analyze(e).personalDicts.isEmpty)
    }

    @Test func 总词库导入的词库和应用生成的不一样时提示() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        try F.put("---\nname: py_ext\nimport_tables:\n  - py_user\n  - cn/a\n  - my_extra\n...\n", "py_ext.dict.yaml", in: e.rime)
        #expect(try F.analyze(e).notes.contains { $0.contains("py_ext.dict.yaml") && $0.contains("my_extra") })
    }

    @Test func 包没给全时报错() throws {
        let e = try F.env(); defer { e.dir.remove() }
        try F.wubiSample(e.packages, into: e.rime)
        let survey = try TakeoverSurvey.scan(e.rime, catalog: e.catalog)
        #expect(throws: TakeoverError.missingPackage("wubi")) {
            try TakeoverAnalyzer.analyze(e.rime, catalog: e.catalog, survey: survey, packages: [:], textReplacement: [])
        }
    }
}

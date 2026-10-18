import Foundation
import Testing
@testable import RimeKit

@Suite struct GeneratorPhraseTests {
    let mine = PersonalContent(dicts: [], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])

    func generate(_ schemas: [String], personal: PersonalContent, textReplacement: [Phrase] = [], _ dir: TempDir) throws -> (URL, GenerationResult) {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: schemas, options: ["wubi": ["pinyinDictionary": "builtin"]]),
                                  packages: packages, personal: personal, textReplacement: textReplacement), into: out)
        return (out, result)
    }

    @Test func 没有短语时不注入上游短语文件原样复制() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, result) = try generate(["py", "wb"], personal: .empty, dir)
        #expect(try GenFixtures.read(out, "custom_phrase.txt").hasSuffix("上游短语\tsy\t1\n"))
        #expect(result.files.contains(GeneratedFile(path: "custom_phrase.txt", origin: .package("pinyin"))))
        #expect(!GenFixtures.exists(out, "wb.custom.yaml"))
    }

    @Test func 自带短语翻译器的方案把短语接在上游文件后面() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, result) = try generate(["py"], personal: mine, dir)
        let text = try GenFixtures.read(out, "custom_phrase.txt")
        #expect(text.hasPrefix("# Rime table\n#@/db_name"))
        #expect(text.hasSuffix("上游短语\tsy\t1\n测试短语\ttstx\t1\n"))
        #expect(result.files.contains(GeneratedFile(path: "custom_phrase.txt", origin: .generated)))
        // 不用注入短语翻译器，只加去重
        #expect(try GenFixtures.patch(out, "py").entries.map(\.key) == ["engine/filters/@next"])
    }

    @Test func 双拼用它自己的短语文件() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, _) = try generate(["sp"], personal: mine, dir)
        let text = try GenFixtures.read(out, "custom_phrase_double.txt")
        #expect(text.hasPrefix(PhraseFile.header))
        #expect(text.hasSuffix("测试短语\ttstx\t1\n"))
    }

    @Test func 没有短语翻译器的方案注入一个() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (out, _) = try generate(["wb"], personal: mine, dir)
        let p = try GenFixtures.patch(out, "wb")
        #expect(p["engine/translators/@before 0"]?.string == "table_translator@custom_phrase")
        #expect(p["custom_phrase"]?["user_dict"]?.string == "custom_phrase")
        #expect(p["custom_phrase"]?["db_class"]?.string == "stabledb")
        #expect(p["custom_phrase"]?["initial_quality"]?.string == "100")
        #expect(try GenFixtures.read(out, "custom_phrase.txt") == PhraseFile.header + "测试短语\ttstx\t1\n")
    }

    @Test func 全拼双拼五笔一起启用时每个短语文件都有() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tr = [Phrase(text: "文本替换", code: "wbth", weight: 1)]
        let (out, _) = try generate(["py", "sp", "wb"], personal: mine, textReplacement: tr, dir)
        for file in ["custom_phrase.txt", "custom_phrase_double.txt"] {
            #expect(try GenFixtures.read(out, file).hasSuffix("测试短语\ttstx\t1\n文本替换\twbth\t1\n"), "\(file)")
        }
        #expect(GenFixtures.exists(out, "wb.custom.yaml"))
    }
}

/// 有手动短语（置顶）时给写短语的方案加去重（候选置顶设计 5.3）
@Suite struct GeneratorUniquifierTests {
    let mine = PersonalContent(dicts: [], phrases: [Phrase(text: "测试短语", code: "tstx", weight: nil)])

    func generate(_ settings: Settings, personal: PersonalContent, textReplacement: [Phrase] = [], _ dir: TempDir) throws -> (Patch, GenerationResult) {
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        var settings = settings
        settings.options = ["wubi": ["pinyinDictionary": "builtin"]]
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(settings, packages: packages, personal: personal, textReplacement: textReplacement), into: out)
        return (try GenFixtures.patch(out, "wb"), result)
    }

    func preserving(_ key: String, _ yaml: String) -> Settings {
        var settings = Settings(schemas: ["wb"])
        settings.preservedPatches["wb"] = [PreservedPatch(key: key, yaml: yaml)]
        return settings
    }

    @Test func 有手动短语时注入的方案加去重() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (p, result) = try generate(Settings(schemas: ["wb"]), personal: mine, dir)
        #expect(p["engine/filters/@next"]?.string == "uniquifier")
        #expect(result.warnings.isEmpty)
    }

    @Test func 只有文本替换短语时不加去重() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let tr = [Phrase(text: "文本替换", code: "wbth", weight: 1)]
        let (p, _) = try generate(Settings(schemas: ["wb"]), personal: .empty, textReplacement: tr, dir)
        #expect(p["engine/translators/@before 0"]?.string == "table_translator@custom_phrase")
        #expect(p["engine/filters/@next"] == nil)
    }

    @Test func 保留补丁整份替换过滤器时去重接在后面() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (p, _) = try generate(preserving("engine/filters", "[simplifier]"), personal: mine, dir)
        #expect(p["engine/filters"]?.sequence?.compactMap(\.string) == ["simplifier", "uniquifier"])
        #expect(p["engine/filters/@next"] == nil)
    }

    @Test func 整份过滤器里已经有去重时不重复加() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (p, _) = try generate(preserving("engine/filters", "[uniquifier]"), personal: mine, dir)
        #expect(p["engine/filters"]?.sequence?.compactMap(\.string) == ["uniquifier"])
        #expect(p["engine/filters/@next"] == nil)
    }

    @Test func 保留补丁已经加了去重时不重复加() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (p, result) = try generate(preserving("engine/filters/@next", "uniquifier"), personal: mine, dir)
        #expect(p.entries.filter { $0.key.hasPrefix("engine/filters") }.map(\.key) == ["engine/filters/@next"])
        #expect(p["engine/filters/@next"]?.string == "uniquifier")
        #expect(result.warnings.isEmpty)
    }

    @Test func 保留补丁占了next时不加并提醒() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let (p, result) = try generate(preserving("engine/filters/@next", "lua_filter@my"), personal: mine, dir)
        #expect(p["engine/filters/@next"]?.string == "lua_filter@my")
        #expect(result.warnings.contains { $0.contains("wb") && $0.contains("没有加去重") }, "\(result.warnings)")
    }
}

@Suite struct GeneratorPhraseValidationTests {
    @Test func 格式不对的短语跳过并提醒重复的只写一次() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let packages = try GenFixtures.makePackages(in: dir.url.appending(path: "cache"))
        let out = dir.url.appending(path: "out")
        let good = Phrase(text: "测试短语", code: "tstx", weight: 1)
        let personal = PersonalContent(dicts: [], phrases: [
            good,
            Phrase(text: "第一行\n第二行\tzz", code: "hh", weight: nil),
            Phrase(text: "#看起来像注释", code: "zs", weight: nil),
            Phrase(text: "带\tTab", code: "tb", weight: nil),
            Phrase(text: "编码坏了", code: "a b\n", weight: nil),
            good,
        ])
        let result = try ConfigGenerator().generate(
            try GenFixtures.input(Settings(schemas: ["sp"]), packages: packages, personal: personal), into: out)
        #expect(try GenFixtures.read(out, "custom_phrase_double.txt") == PhraseFile.header + "测试短语\ttstx\t1\n")
        #expect(result.warnings == ["有 4 条短语格式不对（含换行、Tab，或以 # 开头），没有写进去"])
    }
}

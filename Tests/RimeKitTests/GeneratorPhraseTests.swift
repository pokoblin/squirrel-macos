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
        #expect(!GenFixtures.exists(out, "py.custom.yaml"))   // 不用注入
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

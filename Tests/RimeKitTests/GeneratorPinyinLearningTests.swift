import Foundation
import Testing
import Yams
@testable import RimeKit

/// 混输记词（设计：ai_docs/specs/2026-11-12-mixed-pinyin-learning-design.md）
@Suite struct GeneratorPinyinLearningTests {
    typealias G = GenFixtures

    func generate(_ settings: Settings, personal: PersonalContent = .empty,
                  extra: [String: [String: String]] = [:]) throws -> (TempDir, URL, GenerationResult) {
        let dir = try TempDir()
        let packages = try G.makePackages(in: dir.url.appending(path: "cache"), extra: extra)
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(try G.input(settings, packages: packages, personal: personal), into: out)
        return (dir, out, result)
    }

    func strings(_ node: Node?) -> [String]? { node?.sequence?.compactMap(\.string) }

    @Test func 选大词库时混输换成会记词的拼音翻译器() throws {
        let (dir, out, result) = try generate(Settings(schemas: ["wb", "wb_py"]))
        defer { dir.remove() }
        let p = try G.patch(out, "wb_py")
        #expect(strings(p["engine/translators"]) == ["table_translator", "script_translator@mixed_pinyin"])
        let ns = try #require(p["mixed_pinyin"])
        #expect(ns["dictionary"]?.string == "py_ext")
        #expect(ns["prism"]?.string == "py_ext")
        #expect(ns["enable_user_dict"]?.string == "true")
        #expect(ns["enable_completion"]?.string == "true")
        #expect(ns["initial_quality"]?.string == "-2")
        #expect(strings(p["engine/filters"]) == ["lua_filter@*code_hint_wb"])
        #expect(try G.read(out, "lua/code_hint_wb.lua").contains(#"ReverseLookup("wb")"#))
        #expect(result.files.contains(GeneratedFile(path: "lua/code_hint_wb.lua", origin: .generated)))
        let wb = try G.patch(out, "wb")
        #expect(wb["engine/translators"] == nil)
        #expect(wb["mixed_pinyin"] == nil)
    }

    @Test func 上游已有过滤器时插到最前面() throws {
        let (dir, out, _) = try generate(Settings(schemas: ["wb_py_t"]))
        defer { dir.remove() }
        let p = try G.patch(out, "wb_py_t")
        #expect(p["engine/filters/@before 0"]?.string == "lua_filter@*code_hint_wb")
        #expect(p["engine/filters"] == nil)
        #expect(strings(p["engine/translators"]) == ["table_translator", "script_translator@mixed_pinyin"])
    }

    @Test func 选自带词库时不加记词补丁也不写脚本() throws {
        let (dir, out, _) = try generate(Settings(schemas: ["wb", "wb_py"], options: ["wubi": ["pinyinDictionary": "builtin"]]))
        defer { dir.remove() }
        #expect(!G.exists(out, "wb_py.custom.yaml"))
        #expect(!G.exists(out, "lua"))
    }

    @Test func 有手动短语时短语翻译器和去重都还在() throws {
        let mine = PersonalContent(dicts: [], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])
        let (dir, out, _) = try generate(Settings(schemas: ["wb_py"]), personal: mine)
        defer { dir.remove() }
        let p = try G.patch(out, "wb_py")
        #expect(strings(p["engine/translators"]) == ["table_translator", "script_translator@mixed_pinyin"])
        #expect(p["engine/translators/@before 0"]?.string == "table_translator@custom_phrase")
        #expect(strings(p["engine/filters"]) == ["lua_filter@*code_hint_wb", "uniquifier"])
    }

    @Test func 保留补丁改了翻译器列表时提示() throws {
        var settings = Settings(schemas: ["wb_py"])
        settings.preservedPatches["wb_py"] = [PreservedPatch(key: "engine/translators", yaml: "- table_translator\n")]
        let (dir, out, result) = try generate(settings)
        defer { dir.remove() }
        #expect(strings(try G.patch(out, "wb_py")["engine/translators"]) == ["table_translator"])
        #expect(result.warnings.contains { $0.contains("wb_py") && $0.contains("混输记词") })
    }

    @Test func 上游没有反查翻译器时跳过并提示() throws {
        let schema = G.wubiSchema(id: "wb_py").replacingOccurrences(of: "    - reverse_lookup_translator\n", with: "")
        let (dir, out, result) = try generate(Settings(schemas: ["wb_py"]), extra: ["wubi": ["wb_py.schema.yaml": schema]])
        defer { dir.remove() }
        #expect(try G.patch(out, "wb_py")["mixed_pinyin"] == nil)
        #expect(result.warnings.contains { $0.contains("wb_py") && $0.contains("reverse_lookup_translator") })
    }
}

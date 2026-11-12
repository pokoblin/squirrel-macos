import Foundation
import Testing
@testable import RimeKit

/// 用真实上游包生成、编译、打字。要联网，要宿主机装了鼠须管：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineGenerateTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1" && RimeTools.installed))
struct OnlineGenerateTests {
    func run(_ starter: Starter, _ dir: TempDir) async throws -> URL {
        let catalog = try Catalog.builtIn()
        var settings = Settings.starter(starter)
        settings.appearance.fontPoint = 24
        let store = PackageStore(paths: Fixtures.paths(dir))
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) { packages[spec.id] = try await store.fetch(spec) }
        let personal = PersonalContent(dicts: [], phrases: [Phrase(text: "测试短语", code: "tstx", weight: 1)])
        let out = dir.url.appending(path: "out")
        let result = try ConfigGenerator().generate(
            GenerationInput(settings: settings, catalog: catalog, packages: packages, personal: personal, textReplacementPhrases: []),
            into: out)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        let build = try RimeTools.build(out)
        #expect(build.status == 0)
        return out
    }

    @Test func 五笔加拼音混输() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try await run(.wubiPinyin, dir)
        let r = try RimeTools.type(out, schema: "wubi86_jidian_pinyin", ["g", "weixin", "qukuailian", "hulue", "hulve", "nuedai", "tstx"])
        #expect(r["g"]?.first == "一")
        #expect(r["weixin"]?.first == "微信")
        #expect(r["qukuailian"]?.first == "区块链")   // 雾凇大词库生效
        #expect(r["hulue"]?.first == "忽略")         // 雾凇词库写 lve，lue 也要能打
        #expect(r["hulve"]?.first == "忽略")
        #expect(r["nuedai"]?.first == "虐待")
        #expect(r["tstx"]?.first == "测试短语")
        let squirrel = try GenFixtures.patch(out, "squirrel")
        #expect(squirrel["preset_color_schemes/roseo_maple/font_point"]?.string == "24")
        #expect(squirrel["preset_color_schemes/roseo_maple_dark/font_point"]?.string == "24")
    }

    @Test func 雾凇全拼() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try await run(.rimeIce, dir)
        let r = try RimeTools.type(out, schema: "rime_ice", ["nihao", "tstx"])
        #expect(r["nihao"]?.first == "你好")
        #expect(r["tstx"]?.first == "测试短语")
        #expect(try GenFixtures.patch(out, "squirrel")["preset_color_schemes/purity_of_form_custom/font_point"]?.string == "24")
    }

    @Test func 小鹤双拼() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let out = try await run(.flypy, dir)
        let r = try RimeTools.type(out, schema: "double_pinyin_flypy", ["nihc", "tstx"])
        #expect(r["nihc"]?.first == "你好")
        #expect(r["tstx"]?.first == "测试短语")
    }
}

/// 混输记词用真实的极点五笔、雾凇检查（设计：ai_docs/specs/2026-11-12-mixed-pinyin-learning-design.md）。
/// 对照组是把清单里的 pinyinLearning 去掉后生成的配置，也就是改之前的样子。
/// RIMEKIT_ONLINE=1 swift test --filter OnlinePinyinLearningTests
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1" && RimeTools.installed))
struct OnlinePinyinLearningTests {
    static func catalogWithoutLearning() throws -> Catalog {
        let url = try #require(Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: nil)
            ?? Bundle.allBundles.lazy.compactMap { $0.url(forResource: "catalog", withExtension: "json") }.first)
        var root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var packages = try #require(root["packages"] as? [[String: Any]])
        for i in packages.indices {
            guard var options = packages[i]["options"] as? [[String: Any]] else { continue }
            for j in options.indices {
                guard var choices = options[j]["choices"] as? [[String: Any]] else { continue }
                for k in choices.indices { choices[k]["pinyinLearning"] = nil }
                options[j]["choices"] = choices
            }
            packages[i]["options"] = options
        }
        root["packages"] = packages
        return try Catalog.decode(JSONSerialization.data(withJSONObject: root))
    }

    /// 生成并编译；baseline 为 true 时用去掉记词的清单
    func make(_ dir: TempDir, _ settings: Settings, baseline: Bool, packages: [String: CachedPackage]) throws -> URL {
        let catalog = baseline ? try Self.catalogWithoutLearning() : try Catalog.builtIn()
        let out = dir.url.appending(path: baseline ? "baseline" : "learning")
        let result = try ConfigGenerator().generate(
            GenerationInput(settings: settings, catalog: catalog, packages: packages, personal: .empty, textReplacementPhrases: []),
            into: out)
        #expect(result.warnings.isEmpty, "\(result.warnings)")
        #expect(try RimeTools.build(out).status == 0)
        return out
    }

    func fetch(_ dir: TempDir, _ settings: Settings) async throws -> [String: CachedPackage] {
        let store = PackageStore(paths: Fixtures.paths(dir))
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(try Catalog.builtIn()) { packages[spec.id] = try await store.fetch(spec) }
        return packages
    }

    /// 五笔词库里的编码：全部一、二码，加上三、四码里每 step 个取 1 个
    func sampleCodes(_ out: URL, step: Int) throws -> [String] {
        let text = try GenFixtures.read(out, "wubi86_jidian.dict.yaml")
        var seen = Set<String>()
        var codes: [String] = []
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t")
            guard cols.count >= 2 else { continue }
            let code = String(cols[1])
            guard (1...4).contains(code.count), code.allSatisfy({ ("a"..."y").contains($0) }), seen.insert(code).inserted else { continue }
            codes.append(code)
        }
        codes.sort()
        let short = codes.filter { $0.count <= 2 }
        let long = codes.filter { $0.count > 2 }.enumerated().filter { ($0.offset + 1) % step == 0 }.map(\.element)
        return short + long
    }

    /// Process 一次最多 4096 个参数，分批跑
    func typeInBatches(_ dir: URL, schema: String, _ codes: [String]) throws -> [String: [String]] {
        var result: [String: [String]] = [:]
        for start in stride(from: 0, to: codes.count, by: 2000) {
            let batch = Array(codes[start..<min(start + 2000, codes.count)])
            result.merge(try RimeTools.type(dir, schema: schema, batch)) { _, new in new }
        }
        return result
    }

    func checkUnchanged(_ schema: String, step: Int, baseline: URL, learning: URL) throws {
        let codes = try sampleCodes(baseline, step: step)
        #expect(codes.count > 500)
        let before = try typeInBatches(baseline, schema: schema, codes)
        let after = try typeInBatches(learning, schema: schema, codes)
        var changed: [String] = []
        for code in codes {
            guard let first = before[code]?.first else { continue }
            if after[code]?.first != first { changed.append("\(code): \(first) → \(after[code]?.first ?? "（无）")") }
        }
        #expect(changed.isEmpty, "\(schema) 有 \(changed.count) 个五笔编码首选变了：\(changed.prefix(20))")

        let common = ["shi", "a", "xian"]
        let b = try RimeTools.type(baseline, schema: schema, common)
        let l = try RimeTools.type(learning, schema: schema, common)
        for code in common {
            #expect(Array((b[code] ?? []).prefix(5)) == Array((l[code] ?? []).prefix(5)), "\(schema) \(code)")
        }
        let bc = try RimeTools.typeWithComments(baseline, schema: schema, ["xian"])["xian"] ?? []
        let lc = try RimeTools.typeWithComments(learning, schema: schema, ["xian"])["xian"] ?? []
        #expect(bc.map(\.comment) == lc.map(\.comment), "\(schema) xian 的编码提示：\(bc) vs \(lc)")
        #expect(lc.first?.comment.isEmpty == false)
    }

    @Test func 混输记词不改五笔首选和常见拼音() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let settings = Settings.starter(.wubiPinyin)
        let packages = try await fetch(dir, settings)
        let baseline = try make(dir, settings, baseline: true, packages: packages)
        let learning = try make(dir, settings, baseline: false, packages: packages)
        try checkUnchanged("wubi86_jidian_pinyin", step: 8, baseline: baseline, learning: learning)
        try checkUnchanged("wubi86_jidian_trad_pinyin", step: 32, baseline: baseline, learning: learning)
    }

    @Test func 繁体混输用反引号打拼音和原来一样() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let settings = Settings.starter(.wubiPinyin)
        let packages = try await fetch(dir, settings)
        let baseline = try make(dir, settings, baseline: true, packages: packages)
        let learning = try make(dir, settings, baseline: false, packages: packages)
        let schema = "wubi86_jidian_trad_pinyin"
        let codes = ["`ni", "`gyx"]
        let before = try RimeTools.typeWithComments(baseline, schema: schema, codes)
        let after = try RimeTools.typeWithComments(learning, schema: schema, codes)
        for code in codes {
            let b = (before[code] ?? []).prefix(5).map { "\($0.text) \($0.comment)" }
            let a = (after[code] ?? []).prefix(5).map { "\($0.text) \($0.comment)" }
            #expect(!b.isEmpty, "\(code) 对照里就没有候选")
            #expect(a == b, "\(code)：\(b) → \(a)")
        }
    }

    @Test func 混输能连词能记词() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let settings = Settings.starter(.wubiPinyin)
        let out = try make(dir, settings, baseline: false, packages: try await fetch(dir, settings))
        let schema = "wubi86_jidian_pinyin"
        let r = try RimeTools.type(out, schema: schema, ["niuleitiao", "huangrenxun"])
        #expect(r["niuleitiao"]?.first == "牛肋条")
        #expect(r["huangrenxun"]?.first == "黄仁勋")
        // guoyixun 的候选是「过依循 过亿 过意 国医 过」：4 选「国医」，1 选「寻」
        #expect(try RimeTools.type(out, schema: schema, ["guoyixun41"])["guoyixun41"]?.first == "国医寻")
        #expect(try RimeTools.type(out, schema: schema, ["guoyixun"])["guoyixun"]?.first == "国医寻")
        _ = try RimeTools.type(out, schema: schema, ["guoyixun^k"])
        let after = try RimeTools.type(out, schema: schema, ["guoyixun"])["guoyixun"] ?? []
        #expect(after.first != "国医寻", "\(after)")
    }

    @Test func 只启用混输时也能记词() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let settings = Settings(schemas: ["wubi86_jidian_pinyin"])
        let out = try make(dir, settings, baseline: false, packages: try await fetch(dir, settings))
        let r = try RimeTools.type(out, schema: "wubi86_jidian_pinyin", ["niuleitiao", "hulue"])
        #expect(r["niuleitiao"]?.first == "牛肋条")
        #expect(r["hulue"]?.first == "忽略")
    }
}

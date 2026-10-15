import Foundation
import Testing
@testable import RimeKit

/// 用真实上游包造样本、接管、生成、编译、打字。要联网，要宿主机装了鼠须管，要先 ./tools/vm/build-probes.sh：
/// RIMEKIT_ONLINE=1 swift test --filter OnlineTakeoverTests
/// 加 RIMEKIT_SAMPLE_OUT=<目录> 会把五笔样本复制一份到那个目录（测试机里用）
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RIMEKIT_ONLINE"] == "1" && RimeTools.installed))
struct OnlineTakeoverTests {
    @Test func 五笔样本() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let catalog = try Catalog.builtIn()
        let store = PackageStore(paths: Fixtures.paths(dir))
        let wubi = try await store.fetch(try #require(catalog.package("wubi86-jidian")))
        let dicts = try await store.fetch(try #require(catalog.package("rime-ice-dicts")))
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        try WubiSample.build(wubi: wubi, dicts: dicts, into: rime)
        if let keep = ProcessInfo.processInfo.environment["RIMEKIT_SAMPLE_OUT"] {
            let target = URL(fileURLWithPath: keep, isDirectory: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: rime, to: target)
        }
        let tr = [WubiSample.textReplacement]

        let survey = try TakeoverSurvey.scan(rime, catalog: catalog)
        let p = try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: ["wubi86-jidian": wubi], textReplacement: tr)
        let starter = Settings.starter(.wubiPinyin)
        #expect(p.settings.schemas == starter.schemas)
        #expect(p.settings.options == starter.options)
        #expect(p.settings.appearance == Appearance(fontPoint: 24, labelFontPoint: 20, commentFontPoint: 20))
        #expect(p.settings.textReplacement == TextReplacementSettings(sync: true))
        #expect(p.settings.preservedPatches.mapValues { $0.map(\.key) } == ["default": ["key_binder/bindings"]])
        #expect(p.personalDicts.map(\.lastPathComponent) == ["pinyin_user.dict.yaml", "wubi86_jidian_user.dict.yaml"])
        #expect(p.manualPhrases == [WubiSample.manualPhrase])
        #expect(p.textReplacementMatches == 1)
        #expect(p.notes.isEmpty, "\(p.notes)")

        let packages = ["wubi86-jidian": wubi, "rime-ice-dicts": dicts]
        let preview = try TakeoverPreview.make(p, rime: rime, catalog: catalog, packages: packages, textReplacement: tr,
                                               staging: dir.url.appending(path: "staging", directoryHint: .isDirectory))
        #expect(preview.kept == ["default.custom.yaml.bak", "weasel.custom.yaml"])
        // 生成规则会给每个启用的、没自带短语的方案注入短语翻译器（设计 5.1 第 7 条），作者原来只给 5 个方案加了
        #expect(preview.added == ["numbers.custom.yaml"])

        let out = dir.url.appending(path: "out", directoryHint: .isDirectory)
        _ = try ConfigGenerator().generate(p.generationInput(catalog: catalog, packages: packages, textReplacement: tr), into: out)
        #expect(try RimeTools.build(out).status == 0)
        let r = try RimeTools.type(out, schema: "wubi86_jidian_pinyin",
                                   ["g", "weixin", "qukuailian", "tstx", "sdzd", "shuxuguanyangbenci", WubiSample.wubiWord.code])
        #expect(r["g"]?.first == "一")
        #expect(r["weixin"]?.first == "微信")
        #expect(r["qukuailian"]?.first == "区块链")
        #expect(r["tstx"]?.first == "测试短语")
        #expect(r["sdzd"]?.first == "手动短语样本")
        #expect(r["shuxuguanyangbenci"]?.contains(WubiSample.pinyinWord.text) == true, "\(r["shuxuguanyangbenci"] ?? [])")
        #expect(r[WubiSample.wubiWord.code]?.contains(WubiSample.wubiWord.text) == true, "\(r[WubiSample.wubiWord.code] ?? [])")
        let bindings = try #require(try GenFixtures.patch(out, "default")["key_binder/bindings"])
        #expect(YAMLNode.canonical(bindings).contains("minus"))
        #expect(YAMLNode.canonical(bindings).contains("equal"))
        let squirrel = try GenFixtures.patch(out, "squirrel")
        #expect(squirrel["preset_color_schemes/roseo_maple_dark/font_point"]?.string == "24")
    }

    @Test func 雾凇生成的配置接管后什么都不变() async throws {
        let dir = try TempDir(); defer { dir.remove() }
        let catalog = try Catalog.builtIn()
        var settings = Settings(schemas: ["rime_ice", "double_pinyin_flypy"])
        settings.appearance.fontPoint = 22
        settings.appearance.pageSize = 7
        let store = PackageStore(paths: Fixtures.paths(dir))
        var packages: [String: CachedPackage] = [:]
        for spec in try settings.requiredPackages(catalog) { packages[spec.id] = try await store.fetch(spec) }
        let rime = dir.url.appending(path: "Rime", directoryHint: .isDirectory)
        _ = try ConfigGenerator().generate(
            GenerationInput(settings: settings, catalog: catalog, packages: packages,
                            personal: PersonalContent(dicts: [], phrases: [WubiSample.manualPhrase]), textReplacementPhrases: []),
            into: rime)

        let survey = try TakeoverSurvey.scan(rime, catalog: catalog)
        let p = try TakeoverAnalyzer.analyze(rime, catalog: catalog, survey: survey, packages: packages, textReplacement: [])
        #expect(p.settings.schemas == settings.schemas)
        #expect(p.settings.appearance == settings.appearance)
        #expect(p.settings.preservedPatches.isEmpty, "\(p.settings.preservedPatches)")
        #expect(p.manualPhrases == [WubiSample.manualPhrase])
        #expect(p.notes.isEmpty, "\(p.notes)")
        let preview = try TakeoverPreview.make(p, rime: rime, catalog: catalog, packages: packages, textReplacement: [],
                                               staging: dir.url.appending(path: "staging", directoryHint: .isDirectory))
        #expect(preview.replaced == [], "\(preview.replaced)")
        #expect(preview.added == [])
        #expect(preview.kept == [])
    }
}

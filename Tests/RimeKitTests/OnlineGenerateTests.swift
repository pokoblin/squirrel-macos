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
        let r = try RimeTools.type(out, schema: "wubi86_jidian_pinyin", ["g", "weixin", "qukuailian", "tstx"])
        #expect(r["g"]?.first == "一")
        #expect(r["weixin"]?.first == "微信")
        #expect(r["qukuailian"]?.first == "区块链")   // 雾凇大词库生效
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

import Foundation
import Testing
@testable import RimeKit

@Suite struct BuiltInCatalogTests {
    @Test func 内置清单能读出来而且通过校验() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.packages.map(\.id) == ["rime-ice", "rime-ice-dicts", "wubi86-jidian"])
    }

    @Test func 第一版的方案都在() throws {
        let ids = Set(try Catalog.builtIn().packages.flatMap(\.schemas).map(\.id))
        #expect(ids == ["rime_ice", "double_pinyin_flypy",
                        "wubi86_jidian", "wubi86_jidian_pinyin", "wubi86_jidian_trad",
                        "wubi86_jidian_trad_pinyin", "pinyin_simp", "numbers"])
    }

    @Test func 下载来源和上游目录结构一致() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.package("rime-ice")?.source == .githubReleaseAsset(repo: "iDvel/rime-ice", tag: "nightly", asset: "full.zip"))
        #expect(catalog.package("rime-ice-dicts")?.source == .githubReleaseAsset(repo: "iDvel/rime-ice", tag: "nightly", asset: "cn_dicts.zip"))
        #expect(catalog.package("wubi86-jidian")?.source == .githubBranch(repo: "KyleBing/rime-wubi86-jidian", branch: "master"))
        #expect(catalog.package("rime-ice-dicts")?.anchor == "cn_dicts/8105.dict.yaml")
    }

    @Test func 极点五笔有拼音词库选项默认用雾凇() throws {
        let wubi = try #require(try Catalog.builtIn().package("wubi86-jidian"))
        let option = try #require(wubi.options.first { $0.id == "pinyinDictionary" })
        #expect(option.defaultChoice == "rime-ice")
        let ice = try #require(option.choice("rime-ice"))
        #expect(ice.dependencies == ["rime-ice-dicts"])
        #expect(ice.generatedDicts.map(\.name) == ["pinyin_ext"])
        #expect(ice.patches["pinyin_simp"] == ["translator/dictionary": "pinyin_ext"])
        #expect(ice.patches["wubi86_jidian_pinyin"] == ["reverse_lookup/dictionary": "pinyin_ext"])
        #expect(option.choice("builtin")?.dependencies == [])
    }

    @Test func 极点五笔标出了个人词库模板() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.package("wubi86-jidian")?.userDicts == ["wubi86_jidian_user.dict.yaml", "wubi86_jidian_user_hamster.dict.yaml"])
        #expect(catalog.package("rime-ice")?.userDicts == [])
    }

    @Test func GPL的包都标了许可证() throws {
        let catalog = try Catalog.builtIn()
        #expect(catalog.package("rime-ice")?.license == "GPL-3.0")
        #expect(catalog.package("rime-ice-dicts")?.license == "GPL-3.0")
        #expect(catalog.package("wubi86-jidian")?.license == "Apache-2.0")
    }
}

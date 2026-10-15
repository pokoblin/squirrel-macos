import Foundation
import Testing
@testable import RimeKit

@Suite struct SettingsTests {
    func catalog() throws -> Catalog { try Catalog.decode(Data(PackageOptionTests.json.utf8)) }

    @Test func 合法的设置通过校验() throws {
        var s = Settings(schemas: ["wb", "wpy"])
        s.appearance.fontPoint = 24
        s.appearance.pageSize = 7
        try s.validate(try catalog())
    }

    @Test func 各种不合法的设置() throws {
        let c = try catalog()
        #expect(throws: SettingsError.noSchemas) { try Settings(schemas: []).validate(c) }
        #expect(throws: SettingsError.unknownSchema("nope")) { try Settings(schemas: ["nope"]).validate(c) }
        #expect(throws: SettingsError.duplicateSchema("wb")) { try Settings(schemas: ["wb", "wb"]).validate(c) }
        #expect(throws: SettingsError.unknownOption(package: "wubi", option: "x")) {
            try Settings(schemas: ["wb"], options: ["wubi": ["x": "y"]]).validate(c)
        }
        #expect(throws: SettingsError.unknownChoice(package: "wubi", option: "pinyinDictionary", choice: "zzz")) {
            try Settings(schemas: ["wb"], options: ["wubi": ["pinyinDictionary": "zzz"]]).validate(c)
        }
        var big = Settings(schemas: ["wb"])
        big.appearance.fontPoint = 100
        #expect(throws: SettingsError.outOfRange(field: "候选字字号", value: 100, range: 8...72)) { try big.validate(c) }
        var page = Settings(schemas: ["wb"])
        page.appearance.pageSize = 0
        #expect(throws: SettingsError.outOfRange(field: "每页候选数", value: 0, range: 1...10)) { try page.validate(c) }
        var old = Settings(schemas: ["wb"])
        old.formatVersion = 9
        #expect(throws: SettingsError.unsupportedFormat(9)) { try old.validate(c) }
    }

    @Test func 没选的选项用默认值() throws {
        let c = try catalog()
        let wubi = try #require(c.package("wubi"))
        let option = try #require(wubi.options.first)
        #expect(Settings(schemas: ["wb"]).choice(option, of: wubi).id == "ext")
        #expect(Settings(schemas: ["wb"], options: ["wubi": ["pinyinDictionary": "builtin"]]).choice(option, of: wubi).id == "builtin")
    }

    @Test func 要用到的包包括选项的依赖() throws {
        let c = try catalog()
        #expect(try Settings(schemas: ["wb"]).requiredPackages(c).map(\.id) == ["dicts", "wubi"])
        #expect(try Settings(schemas: ["wb"], options: ["wubi": ["pinyinDictionary": "builtin"]]).requiredPackages(c).map(\.id) == ["wubi"])
    }

    @Test func 起步方案都能通过内置清单的校验() throws {
        let c = try Catalog.builtIn()
        for starter in Starter.allCases {
            try Settings.starter(starter).validate(c)
        }
        #expect(Settings.starter(.rimeIce).schemas == ["rime_ice"])
        #expect(Settings.starter(.flypy).schemas == ["double_pinyin_flypy"])
        #expect(Settings.starter(.wubiPinyin).schemas.first == "wubi86_jidian_pinyin")
        #expect(try Settings.starter(.wubiPinyin).requiredPackages(c).map(\.id) == ["rime-ice-dicts", "wubi86-jidian"])
    }

    @Test func 存进去再读出来不变() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let store = SettingsStore(paths: Fixtures.paths(dir))
        #expect(try store.load() == nil)
        var s = Settings.starter(.wubiPinyin)
        s.appearance.fontPoint = 24
        s.appearance.candidateListLayout = .linear
        s.preservedPatches = ["default": [PreservedPatch(key: "key_binder/bindings", yaml: "[]")]]
        try store.save(s)
        #expect(try store.load() == s)
    }

    @Test func 读到不认识的格式版本() throws {
        let dir = try TempDir(); defer { dir.remove() }
        let paths = Fixtures.paths(dir)
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try Data(#"{"formatVersion":9}"#.utf8).write(to: paths.settingsFile)
        #expect(throws: SettingsError.unsupportedFormat(9)) { try SettingsStore(paths: paths).load() }
    }
}
